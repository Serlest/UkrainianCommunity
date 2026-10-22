import {strict as assert} from "node:assert";
import {before, after, test} from "node:test";
import type {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {buildAdminSearchGrams, adminSearchControlPath} from "../users/adminUserSearch";
import {manage, feed, acknowledge} from "./service";
import {audiencePage} from "./audience";
import {parseDraft} from "./contract";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const req = (uid: string | undefined, data: unknown) => ({data, auth: uid ? {uid, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}} : undefined}) as CallableRequest;
const owner = "management-ann-owner", user = "management-ann-zzz";
const now = Date.now();
const make = (id: string, change = {}) => parseDraft({id, title: {uk:"Тест",de:"Test"},body:{uk:"Текст",de:"Text"},groups:["registered"],userIds:[],regions:[],targetPlatforms:["ios"],mode:"acknowledge",feedback:true,push:true,startsAt:now-1000,expiresAt:now+3600000,...change},owner,now);
const accountIDs = [owner,user,...Array.from({length:55},(_,i)=>`management-ann-${String(i).padStart(3,"0")}`),"management-ann-blocked"];
const scanIDs: string[] = [];
const campaignIDs = Array.from({length:35},(_,i)=>`management-history-${String(i).padStart(3,"0")}`);
before(async()=> {
 if (!enabled) return;
 await db.doc("appConfig/announcements").set({enabled:true,iosEnabled:true,pushEnabled:true});
 await db.doc(adminSearchControlPath).set({ready:true,version:1});
 await Promise.all(accountIDs.map(async id=> {
  const data={globalRole:id===owner?"owner":"user",accountStatus:id.endsWith("blocked")?"bannedPermanent":"active",displayName:id===user?"Олена Levytska":"Person "+id,email:id===user?"olena@example.test":id+"@example.test",selectedFederalState:"wien",requiresMultiFactorAuth:id===owner};
  await db.doc(`users/${id}`).set({...data,adminSearchGramsV1:buildAdminSearchGrams(id,data)});
 }));
 await seedCurrentLegalForIntegration(owner,user);
});
after(async()=> {
 if (!enabled) return;
 await Promise.all([...accountIDs,...scanIDs].map(id=>db.recursiveDelete(db.doc(`users/${id}`))));
 await Promise.all(campaignIDs.map(id=>db.recursiveDelete(db.doc(`announcements/${id}`))));
 await db.recursiveDelete(db.doc("organizations/announcement-role-fixture"));
 await db.doc(adminSearchControlPath).delete();
});
test("indexed recipient search reaches past page one, searches email, excludes blocked and binds cursors",{skip:!enabled},async()=> {
 const found=await manage(req(owner,{operation:"users",searchVersion:2,query:"OLENA@EXAMPLE.TEST"}));
 assert.ok("items" in found && found.items); assert.deepEqual(found.items.map((u:any)=>u.id),[user]);
 const first=await manage(req(owner,{operation:"users",searchVersion:2,query:""}));
 assert.ok("items" in first && first.items && "cursor" in first && first.cursor); assert.equal(first.items.length,50);
 const second=await manage(req(owner,{operation:"users",searchVersion:2,query:"",cursor:first.cursor}));
 assert.ok("items" in second && second.items); assert.ok(second.items.some((u:any)=>u.id===user));
 assert.equal([...first.items,...second.items].some((u:any)=>u.id.endsWith("blocked")),false);
 assert.equal(new Set([...first.items,...second.items].map((u:any)=>u.id)).size,first.items.length+second.items.length);
 await assert.rejects(manage(req(owner,{operation:"users",searchVersion:2,query:"different",cursor:first.cursor})));
 for(const uid of [undefined,user]) await assert.rejects(manage(req(uid,{operation:"users",searchVersion:2,query:"olena"})));
 // Older builds still pass an ordinary document ID as cursor.
 const legacy=await manage(req(owner,{operation:"users"}));
 assert.ok("cursor" in legacy); await manage(req(owner,{operation:"users",cursor:legacy.cursor}));
});
test("bounded indexed candidate pages continue past an empty page without losing a later match",{skip:!enabled},async()=> {
 for(let i=0;i<260;i++) scanIDs.push(`management-scan-${String(i).padStart(3,"0")}`);
 scanIDs.push("management-scan-zzz");
 await Promise.all(scanIDs.map(async id=> {
  const profile={displayName:id.endsWith("zzz")?"needle qzz":"needless person",accountStatus:"active"};
  await db.doc(`users/${id}`).set({...profile,adminSearchGramsV1:buildAdminSearchGrams(id,profile)});
 }));
 const first=await manage(req(owner,{operation:"users",searchVersion:2,query:"needle qzz"}));
 assert.ok("items" in first && first.items && "cursor" in first && first.cursor); assert.equal(first.items.length,0);
 const next=await manage(req(owner,{operation:"users",searchVersion:2,query:"needle qzz",cursor:first.cursor}));
 assert.ok("items" in next && next.items); assert.deepEqual(next.items.map((i:any)=>i.id),["management-scan-zzz"]);
});
test("selected recipients resolve names and email; deleted accounts are explicitly unavailable",{skip:!enabled},async()=> {
 const result=await manage(req(owner,{operation:"resolveUsers",userIds:[user,"management-ann-missing",user]}));
 assert.ok("users" in result && result.users); assert.equal(result.users.length,2);
 assert.equal(result.users[0].email,"olena@example.test"); assert.equal(result.users[1].available,false);
 await assert.rejects(manage(req(user,{operation:"resolveUsers",userIds:[owner]})));
 await assert.rejects(manage(req(owner,{operation:"resolveUsers",userIds:Array(101).fill(user)})));
});
test("batched organization roles and preview count each matching active account once",{skip:!enabled},async()=> {
 await db.doc("organizations/announcement-role-fixture").set({ownerId:user,adminIds:[user],moderatorIds:[user]});
 const ids=accountIDs.slice(0,34);
 const profiles=await db.getAll(...ids.map(id=>db.doc(`users/${id}`)));
 const resolved=await audiencePage(profiles,["organizationOwners","organizationAdmins","organizationModerators"]);
 assert.deepEqual(new Set(resolved.find(u=>u.uid===user)!.organizationRoles),new Set(["communityOwner","communityAdmin","communityModerator"]));
 const draft=make("management-preview",{groups:["organizationOwners","organizationAdmins"],userIds:[user],regions:["wien"]});
 const preview=await manage(req(owner,{operation:"preview",draft})); assert.ok("accounts" in preview); assert.equal(preview.accounts,1);
});
test("active feed avoids retained history; paged history and legacy feed retain receipts and cancelled messages",{skip:!enabled},async()=> {
 for(let i=0;i<campaignIDs.length;i++) {
  const draft=make(campaignIDs[i]);
  await db.doc(`announcements/${draft.id}`).set({...draft,status:i===0?"cancelled":"published",expiresAt:i<30?now-100:now+3600000,startsAt:i===34?now+100000:now-1000});
 }
 await db.doc(`users/${user}/announcementReceipts/${campaignIDs[0]}`).set({presentedAt:now-500});
 const active=await feed(req(user,{platform:"ios",capability:1,feedMode:"active"}));
 assert.equal(active.items.filter(i=>campaignIDs.includes(i.id)).length,4);
 const history=await feed(req(user,{platform:"ios",capability:1,feedMode:"history"}));
 assert.ok(history.cursor); assert.equal(history.items.length,30); assert.ok(history.items.some(i=>i.status==="cancelled"));
 const second=await feed(req(user,{platform:"ios",capability:1,feedMode:"history",cursor:history.cursor}));
 assert.equal(second.items.length,4);
 const legacy=await feed(req(user,{platform:"ios",capability:1})); assert.equal(legacy.items.length,34);
 for(const [phase,expected] of [["active",4],["scheduled",1],["completed",29],["cancelled",1]] as const) {
  const result=await manage(req(owner,{operation:"list",phase}));
  assert.ok("items" in result && result.items); assert.equal(result.items.filter((i:any)=>campaignIDs.includes(i.id)).length,expected);
 }

 await assert.rejects(feed(req(user,{platform:"ios",capability:1,feedMode:"invented"})));
});
test("statistics distinguish unique accounts from multiple push devices and retries",{skip:!enabled},async()=> {
 const id=campaignIDs[31];
 for(let i=0;i<2;i++) await acknowledge(req(user,{platform:"ios",capability:1,id,event:"presented"}));
 const ref=db.doc(`announcements/${id}`);
 await ref.collection("deliveries").doc("device-a").set({success:true,attempts:2});
 await ref.collection("deliveries").doc("device-b").set({success:true,attempts:1});
 await ref.collection("deliveries").doc("device-c").set({success:false,attempts:3});
 const stats=await manage(req(owner,{operation:"stats",id}));
 assert.ok("presented" in stats); assert.equal(stats.presented,1); assert.equal(stats.pushSuccess,2); assert.equal(stats.pushFailure,1);
});
