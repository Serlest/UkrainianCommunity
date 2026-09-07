import {strict as assert} from "node:assert";
import {test} from "node:test";
import {db} from "../firebase/admin";
import {dispatchAnnouncements} from "./service";
import {parseDraft} from "./contract";
test("push dispatch resumes a failed page without duplicating successful deliveries or reaching unsupported clients", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
 const now = Date.now(), id = "ann-delivery-fixture", ref = db.collection("announcements").doc(id);
 const draft = parseDraft({id,title:{uk:"a",de:"a"},body:{uk:"b",de:"b"},groups:["guests"],userIds:[],regions:[],targetPlatforms:["ios"],mode:"once",feedback:false,push:true,startsAt:now-100,expiresAt:now+60000},"owner",now);
 const refs = ["ann-fixture-a","ann-fixture-b","ann-fixture-c"].map((d) => db.collection("announcementDevices").doc(d));
 try {
  await db.doc("appConfig/announcements").set({enabled:true,iosEnabled:true,pushEnabled:true});
  await ref.set({...draft,status:"published",pushState:"pending"});
  for(let i=0;i<refs.length;i++) await refs[i].set({verified:true,platform:i===2?"android":"ios",capability:1,uid:null,token:"c123456789012345678901",registrationType:"fid",updatedAt:now});
  const delivered: string[] = []; let failOnce = true;
  const sender: Parameters<typeof dispatchAnnouncements>[0] = async (docs, message) => {
   assert.equal(message.data?.announcementId,id);
   assert.equal(message.data?.body,undefined);
   delivered.push(docs[0].id);
   if(docs[0].id===refs[1].id && failOnce) {failOnce=false;return {targetCount:1,successCount:0,failureCount:1};}
   return {targetCount:1,successCount:1,failureCount:0};
  };
  await assert.rejects(dispatchAnnouncements(sender));
  await dispatchAnnouncements(sender); await dispatchAnnouncements(sender);
  assert.deepEqual(delivered,[refs[0].id,refs[1].id,refs[1].id]);
  assert.equal((await ref.get()).data()?.pushState,"completed");
 } finally {await db.recursiveDelete(ref);for(const r of refs) await r.delete();}
});

test("retention removes only expired announcement data", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
 const {cleanupAnnouncementData} = await import("./service");
 const now=Date.now(), old=db.doc("announcements/old-retention"), fresh=db.doc("announcements/fresh-retention"), receipt=db.doc("users/ann-retention/announcementReceipts/old"), device=db.doc("announcementDevices/old-retention");
 try {
  await old.set({expiresAt:now-181*86400000});await old.collection("metrics").doc("anon").set({presented:true});
  await fresh.set({expiresAt:now+86400000});await receipt.set({retentionExpiresAt:now-1});await device.set({updatedAt:now-91*86400000});
  await cleanupAnnouncementData(now);
  assert.equal((await old.get()).exists,false);assert.equal((await fresh.get()).exists,true);
  assert.equal((await receipt.get()).exists,false);assert.equal((await device.get()).exists,false);
 } finally {await db.recursiveDelete(old);await fresh.delete();await receipt.delete();await device.delete();}
});
