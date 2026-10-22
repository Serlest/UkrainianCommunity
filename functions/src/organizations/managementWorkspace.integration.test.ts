import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {seedVerifiedAuthForIntegration} from "../auth/authIntegrationFixture";
import {assignOrganizationAdmin,assignOrganizationModerator,removeOrganizationAdmin,transferOrganizationOwnership} from "./roleManagement";
import {organizationSearchGrams,readOrganizationWorkspace,reconcileWorkspaceIndex,workspaceIndexState,manageOrganizationWorkspace} from "./managementWorkspace";
const enabled=Boolean(process.env.FIRESTORE_EMULATOR_HOST);
function local(){assert.match(process.env.FIRESTORE_EMULATOR_HOST??"",/^(127\.0\.0\.1|localhost):/);assert(process.env.GCLOUD_PROJECT?.startsWith("demo-"));}
const request=(uid:string,data:unknown)=>({auth:{uid,token:{email_verified:true}},data} as never);
async function user(id:string,globalRole="user"){
 await seedVerifiedAuthForIntegration(id);await db.doc(`users/${id}`).set({globalRole,accountStatus:"active",blockState:"active",displayName:id,city:"Innsbruck"});await seedCurrentLegalForIntegration(id);
}
async function revision(id:string){const t=(await db.doc(`organizations/${id}`).get()).get("updatedAt") as Timestamp;return `${t.seconds}:${t.nanoseconds}`;}
test("Role mutation CAS, replay, conflicting operation, legacy no-op and stale removal protect current roles and notify once",{skip:!enabled},async()=>{
 local();await user("workspace-owner","owner");await user("workspace-target");await user("workspace-org-owner");
 const id="role-safe";await db.doc(`organizations/${id}`).set({name:"Organization",ownerId:"workspace-org-owner",adminIds:[],moderatorIds:[],updatedAt:new Timestamp(1792670000,123456000),moderationStatus:"approved"});
 const base={organizationId:id,targetUserId:"workspace-target",principalId:"workspace-owner",operationId:"assign-1",expectedRevision:await revision(id),expectedRole:"none"};
 await assert.rejects(assignOrganizationAdmin.run(request("workspace-owner",{...base,principalId:"wrong"})),{code:"permission-denied"});
 const results=await Promise.all([assignOrganizationAdmin.run(request("workspace-owner",base)),assignOrganizationAdmin.run(request("workspace-owner",base))]);assert.deepEqual(results[0],results[1]);
 assert.equal((await db.collection("users/workspace-target/notificationInbox").where("sourceId","==",id).get()).size,1);
 await assert.rejects(assignOrganizationModerator.run(request("workspace-owner",base)),{code:"already-exists"});
 await assignOrganizationAdmin.run(request("workspace-owner",{organizationId:id,targetUserId:"workspace-target"}));
 assert.equal((await db.collection("users/workspace-target/notificationInbox").where("sourceId","==",id).get()).size,1);
 await assert.rejects(assignOrganizationModerator.run(request("workspace-owner",{...base,operationId:"stale"})),{code:"aborted"});
 await assignOrganizationModerator.run(request("workspace-owner",{organizationId:id,targetUserId:"workspace-target"}));
 await assert.rejects(removeOrganizationAdmin.run(request("workspace-owner",{organizationId:id,targetUserId:"workspace-target"})),{code:"aborted"});
 assert.deepEqual((await db.doc(`organizations/${id}`).get()).get("moderatorIds"),["workspace-target"]);
 const transfer={organizationId:id,targetUserId:"workspace-target",principalId:"workspace-owner",operationId:"transfer-1",expectedRevision:await revision(id),expectedRole:"communityModerator"};
 const first=await transferOrganizationOwnership.run(request("workspace-owner",transfer));assert.deepEqual(await transferOrganizationOwnership.run(request("workspace-owner",transfer)),first);
 await transferOrganizationOwnership.run(request("workspace-owner",{organizationId:id,targetUserId:"workspace-target"}));
 const oldOwnerNotices=await db.collection("users/workspace-org-owner/notificationInbox").where("sourceId","==",id).get();
 assert.equal(oldOwnerNotices.size,1);assert.equal(oldOwnerNotices.docs[0].get("metadata.previousRole"),"communityOwner");assert.equal(oldOwnerNotices.docs[0].get("metadata.newOwnerId"),"workspace-target");
 await db.doc("users/workspace-owner").update({globalRole:"user"});
 await assert.rejects(transferOrganizationOwnership.run(request("workspace-owner",transfer)),{code:"permission-denied"});
});
test("Workspace pages137 organizations without truncation, filters by region and multilingual search, scopes ordinary managers",{skip:!enabled},async()=>{
 local();await db.recursiveDelete(db.collection("organizations"));const batch=db.batch();
 for(let i=0;i<137;i++){
  const id=`org-${String(i).padStart(3,"0")}`,data={name:`Organization ${i}`,localizations:{de:{name:i===135?"Gesundheit Müller":"Gemeinschaft"},uk:{name:"Українська громада"}},city:"Innsbruck",federalState:i%2?"tirol":"wien",moderationStatus:"approved",ownerId:i%3?"someone":"scope-owner",adminIds:i===136?["scope-admin"]:[],moderatorIds:[],updatedAt:Timestamp.now()};
  batch.set(db.doc(`organizations/${id}`),{...data,workspaceSearchV1:organizationSearchGrams(id,data)});
 }await batch.commit();
 const actor={uid:"workspace-owner",globalRole:"owner" as const};
 for(const ready of [false,true]){
  await db.doc(workspaceIndexState).set({ready});let cursor:string|undefined;const ids:string[]=[];
  do{const page=await readOrganizationWorkspace(db,actor,{action:"list",cursor});ids.push(...page.ids!);cursor=page.cursor??undefined;}while(cursor);
  assert.equal(ids.length,137);assert.equal(new Set(ids).size,137);
  const found=await readOrganizationWorkspace(db,actor,{action:"list",search:"gesundheit muller",region:"tirol"});assert.deepEqual(found.ids,["org-135"]);
  const scoped=await readOrganizationWorkspace(db,{uid:"scope-admin",globalRole:"user"},{action:"list"});assert.deepEqual(scoped.ids,["org-136"]);
  const absent=await readOrganizationWorkspace(db,{uid:"outsider",globalRole:"user"},{action:"list"});assert.deepEqual(absent.ids,[]);
  const focus=await readOrganizationWorkspace(db,actor,{action:"list",organizationId:"org-136"});assert.deepEqual(focus.ids,["org-136"]);
 }
 const old=(await db.doc("organizations/org-135").get()).get("updatedAt");await db.doc("organizations/org-135").update({name:"Renamed"});await reconcileWorkspaceIndex(db,"org-135");assert.deepEqual((await db.doc("organizations/org-135").get()).get("updatedAt"),old);
});
test("Content counters cover all6 statuses and pages by status, subscribers remain separate with bounded pages",{skip:!enabled},async()=>{
 local();const org="org-000";const actor={uid:"workspace-owner",globalRole:"owner" as const};
 const batch=db.batch();const statuses=["draft","pendingReview","needsRevision","approved","rejected","archived"];
 for(let i=0;i<65;i++)batch.set(db.doc(`news/workspace-${String(i).padStart(3,"0")}`),{organizationId:org,sourceType:"organization",title:`News ${i}`,moderationStatus:statuses[i%6]});
 for(let i=0;i<65;i++){const uid=`subscriber-${String(i).padStart(3,"0")}`;batch.set(db.doc(`publicProfiles/${uid}`),{displayName:uid,city:"Wien"});batch.set(db.doc(`likes/follower-${String(i).padStart(3,"0")}`),{userId:uid,subscribedOrganizationId:org});}
 await batch.commit();const stats=await readOrganizationWorkspace(db,actor,{action:"stats",organizationId:org});assert.equal(stats.counts!.news,65);
 const first=await readOrganizationWorkspace(db,actor,{action:"content",organizationId:org,contentType:"news"});assert.equal(first.items!.length,30);assert.equal(first.counts!.needsRevision,11);assert(first.cursor);
 const returned=await readOrganizationWorkspace(db,actor,{action:"content",organizationId:org,contentType:"news",status:"needsRevision"});assert.equal(returned.items!.length,11);
 const followers=await readOrganizationWorkspace(db,actor,{action:"subscribers",organizationId:org});assert.equal(followers.users!.length,30);assert(followers.cursor);
 const next=await readOrganizationWorkspace(db,actor,{action:"subscribers",organizationId:org,cursor:followers.cursor});assert.equal(next.users!.length,30);assert.equal(new Set([...followers.users!,...next.users!].map(x=>x.id)).size,60);
 await assert.rejects(readOrganizationWorkspace(db,{uid:"outsider",globalRole:"user"},{action:"stats",organizationId:org}),{code:"permission-denied"});
});
test("Workspace callable binds principal and current account",{skip:!enabled},async()=>{
 local();await user("workspace-reader","owner");
 await assert.rejects(manageOrganizationWorkspace.run(request("workspace-reader",{action:"list",principalId:"other"})),{code:"permission-denied"});
 const page=await manageOrganizationWorkspace.run(request("workspace-reader",{action:"list",principalId:"workspace-reader"}));assert.equal(page.ids!.length,30);
});
