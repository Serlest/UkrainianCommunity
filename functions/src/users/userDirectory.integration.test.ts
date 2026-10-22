import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {after, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db,adminAuth} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {manageUserDirectory} from "./userDirectory";
import {adminReviewRevision} from "./adminMutationTransaction";
import {warnUser,banUser,restoreUser} from "./accountStatusManagement";
import {assignAppAdmin} from "./platformRoleManagement";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const prefix = `directory-${randomUUID()}`;
const actor = `${prefix}-owner`;
const request = (data: object,uid=actor) => ({auth:{uid,token:{email_verified:true,firebase:{sign_in_second_factor:"totp"}}},data} as never);
const refs: string[] = [];
async function seed(id:string,data:object) { refs.push(`users/${id}`); await db.doc(`users/${id}`).set(data); }
after(async()=>{ if (!enabled) return; for (const path of refs) await db.recursiveDelete(db.doc(path)); });
test("directory searches, filters and sorts the entire dataset with stable pages beyond 100",{skip:!enabled},async()=>{
 assert.match(process.env.GCLOUD_PROJECT??"",/^demo-/);
 await seed(actor,{globalRole:"owner",accountStatus:"active",createdAt:Timestamp.fromMillis(999999)}); await seedCurrentLegalForIntegration(actor);
 const batch=db.batch();
 for(let i=0;i<137;i++) { const id=`${prefix}-${String(i).padStart(3,"0")}`;refs.push(`users/${id}`);batch.set(db.doc(`users/${id}`),{displayName:`Nutzer ${String(i).padStart(3,"0")}`,fullName:"Searchfixture",selectedFederalState:i%2?"tirol":"wien",createdAt:Timestamp.fromMillis(1000+i),accountStatus:i===136?"bannedPermanent":"active"}); }
 await batch.commit();
 const list=(options:object={})=>manageUserDirectory.run(request({action:"list",principalId:actor,query:"searchfixture",...options}));
 const seen:string[]=[];let cursor:string|null|undefined;
 do {const page=await list({cursor});assert.equal(page.totalMatches,137);seen.push(...page.userIds!);cursor=page.cursor;} while(cursor);
 assert.equal(new Set(seen).size,137);assert.equal(seen[0],`${prefix}-136`);
 assert.equal((await list({sort:"oldest"})).userIds![0],`${prefix}-000`);
 assert.equal((await list({sort:"nameAscending"})).userIds![0],`${prefix}-000`);
 assert.equal((await list({filter:"banned"})).totalMatches,1);
 assert.equal((await list({region:"tirol"})).totalMatches,68);
 assert.equal((await list({query:"",region:"wien",sort:"oldest"})).userIds![0],`${prefix}-000`);
 const compact=await list({includeOrganizations:false});assert.deepEqual(compact.organizations,[]);assert.equal(compact.totalMatches,137);
 await assert.rejects(list({includeOrganizations:"false"}),{code:"invalid-argument"});
 const page=await list();await assert.rejects(list({cursor:page.cursor,region:"wien"}),{code:"invalid-argument"});
 await assert.rejects(manageUserDirectory.run(request({action:"list",principalId:"other"})),{code:"permission-denied"});
 await assert.rejects(manageUserDirectory.run({data:{action:"list"}} as never),{code:"unauthenticated"});
});
test("organization roles include archived/draft memberships; choice picker returns only allowed actionable organizations",{skip:!enabled},async()=>{
 const uid=`${prefix}-member`;
 for (const [i,status] of ["draft","archived","approved"].entries()) {const path=`organizations/${prefix}-org${i}`;refs.push(path);await db.doc(path).set({name:`Org ${i}`,moderationStatus:status,ownerId:uid,adminIds:[uid],moderatorIds:[uid],updatedAt:new Timestamp(10,123000)});}
 const memberships=await manageUserDirectory.run(request({action:"memberships",principalId:actor,userId:uid}));assert.equal(memberships.organizations!.length,3);assert.equal(memberships.organizations![0].accessRevision,"10:123000");
 const filtered=await manageUserDirectory.run(request({action:"list",principalId:actor,filter:"organizationOwners"}));
 // A role orphan with no profile must not create a phantom user.
 assert.equal(filtered.totalMatches,0);
 await seed(uid,{displayName:"Owner member",globalRole:"user",createdAt:Timestamp.now()});
 assert.equal((await manageUserDirectory.run(request({action:"list",principalId:actor,filter:"organizationAdmins"}))).totalMatches,0);
 assert.equal((await manageUserDirectory.run(request({action:"list",principalId:actor,filter:"organizationModerators"}))).totalMatches,0);
 const choices=await manageUserDirectory.run(request({action:"organizations",principalId:actor,query:prefix}));assert.equal(choices.organizations!.length,1);
 const batch=db.batch();for(let i=0;i<65;i++){const path=`organizations/${prefix}-choice${String(i).padStart(3,"0")}`;refs.push(path);batch.set(db.doc(path),{name:"WorkspaceCandidate",ownerId:actor,moderationStatus:"approved"});}await batch.commit();
 let cursor:string|null|undefined;let count=0;
 do {const page=await manageUserDirectory.run(request({action:"organizations",principalId:actor,query:"WorkspaceCandidate",cursor}));count+=page.organizations!.length;assert.ok(page.organizations!.length<=30);cursor=page.cursor;}while(cursor);
 assert.equal(count,65);
});
test("reviewed status mutation is idempotent, rejects conflicting receipts and stale state",{skip:!enabled},async()=>{
 const uid=`${prefix}-target`;await seed(uid,{globalRole:"user",accountStatus:"active",blockState:"active"});
 const expectedRevision=adminReviewRevision((await db.doc(`users/${uid}`).get()).data()!);
 const input={targetUserId:uid,reason:"Reviewed warning",principalId:actor,operationId:randomUUID(),expectedRevision};
 const responses=await Promise.all([warnUser.run(request(input)),warnUser.run(request(input))]);assert.deepEqual(responses[0],responses[1]);
 assert.equal((await db.doc(`users/${uid}`).get()).get("warningCount"),1);
 assert.equal((await db.collection(`users/${uid}/notificationInbox`).get()).size,1);
 await assert.rejects(warnUser.run(request({...input,reason:"Different reason"})),{code:"already-exists"});
 await assert.rejects(restoreUser.run(request({...input,operationId:randomUUID()})),{code:"aborted"});
 const metadata={accountStatus:"active",globalRole:"user",blockState:"warned",warningCount:3,isBlocked:false,statusUpdatedAt:new Timestamp(12,34)};
 assert.equal(adminReviewRevision(metadata),"b67b214b23081af5639162586e602327df6ec8d90cc718613815f1fe61b313d3");
});
test("current actor rights are rechecked inside status and platform-role transactions",{skip:!enabled},async t=>{
 const uid=`${prefix}-race`;await seed(uid,{globalRole:"user",accountStatus:"active"});await adminAuth.createUser({uid,email:`${uid}@example.org`,emailVerified:true});
 const original=db.runTransaction.bind(db);let revoke=true;
 t.mock.method(db,"runTransaction",async (...args: Parameters<typeof db.runTransaction>)=>{if(revoke){revoke=false;await db.doc(`users/${actor}`).update({globalRole:"user"});}return original(...args);});
 await assert.rejects(warnUser.run(request({targetUserId:uid,reason:"Race"})),{code:"permission-denied"});
 assert.equal((await db.doc(`users/${uid}`).get()).get("accountStatus"),"active");
 await db.doc(`users/${actor}`).update({globalRole:"owner"});revoke=true;
 await assert.rejects(assignAppAdmin.run(request({targetUserId:uid,reason:"Race"})),{code:"permission-denied"});
 assert.equal((await db.doc(`users/${uid}`).get()).get("globalRole"),"user");
 await db.doc(`users/${actor}`).update({globalRole:"owner"});await adminAuth.deleteUser(uid);
});
test("modern retry resumes session revocation without a duplicate notification",{skip:!enabled},async t=>{
 const uid=`${prefix}-revoke`;await seed(uid,{globalRole:"user",accountStatus:"active",blockState:"active"});
 const input={targetUserId:uid,principalId:actor,operationId:randomUUID(),expectedRevision:adminReviewRevision((await db.doc(`users/${uid}`).get()).data()!)};
 let calls=0;t.mock.method(adminAuth,"revokeRefreshTokens",async()=>{calls++;if(calls===1)throw Error("temporary");});
 await assert.rejects(banUser.run(request(input)),{code:"internal"});await banUser.run(request(input));
 assert.equal(calls,2);assert.equal((await db.collection(`users/${uid}/notificationInbox`).get()).size,1);
 await db.doc(`users/${uid}`).update({accountStatus:"active",blockState:"active"});
 await assert.rejects(banUser.run(request(input)),{code:"aborted"});assert.equal(calls,2);
});
