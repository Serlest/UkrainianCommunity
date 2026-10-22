import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {directoryGrantState, manageDirectoryEditorAccess} from "./directoryEditorAccess";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const prefix = `directory-access-${randomUUID()}`, owner = `${prefix}-owner`, target = `${prefix}-target`, reader = `${prefix}-reader`;
const request = (action: string, data: Record<string,unknown> = {}, actor = owner) => ({auth:{uid:actor,token:{email_verified:true}}, data:{action,principalId:actor,...data}} as never);
async function seed() {
  await Promise.all([owner,target,reader].map(uid=>db.doc(`users/${uid}`).set({globalRole:uid===owner?"owner":"user",accountStatus:"active",blockState:"active",displayName:uid,language:"de",createdAt:Timestamp.now()})));
  await seedCurrentLegalForIntegration(owner,target,reader);
}
async function cleanup() {
  for (const collection of ["auditLogs","systemLogs"]) {
    const docs = await db.collection(collection).where(collection==="auditLogs"?"targetUserId":"targetId","==",target).get();
    await Promise.all(docs.docs.map(d=>d.ref.delete()));
  }
  for (const uid of [owner,target,reader]) { await db.recursiveDelete(db.doc(`users/${uid}`)); await db.doc(`directoryEditors/${uid}`).delete(); }
}
const mutate = (state: ReturnType<typeof directoryGrantState>, value: boolean, op = randomUUID()) => request("set",{userId:target,enabled:value,expectedRevision:state.revision,operationId:op});

test("directory access: current owner only, CAS, atomic audit/notice, retry, legacy writes, orphan revoke", {skip:!enabled}, async()=>{
  await seed();
  try {
    const ref = db.doc(`directoryEditors/${target}`);
    const absent = directoryGrantState(await ref.get());
    await assert.rejects(manageDirectoryEditorAccess.run(request("list",{},reader)),{code:"permission-denied"});
    await assert.rejects(manageDirectoryEditorAccess.run(request("inspect",{userIds:[target],principalId:reader})),{code:"permission-denied"});
    await assert.rejects(manageDirectoryEditorAccess.run(request("set",{userId:target,enabled:true,operationId:randomUUID()})),{code:"invalid-argument"});
    await db.doc(`users/${target}`).update({accountStatus:"deactivated"});
    await assert.rejects(manageDirectoryEditorAccess.run(mutate(absent,true)),{code:"permission-denied"});
    await db.doc(`users/${target}`).update({accountStatus:"active"});
    const operation = randomUUID(), grantRequest = mutate(absent,true,operation);
    const [first,again] = await Promise.all([manageDirectoryEditorAccess.run(grantRequest),manageDirectoryEditorAccess.run(grantRequest)]);
    assert.deepEqual(first,again);
    assert.equal((first as {enabled:boolean}).enabled,true);
    const inbox = await db.collection(`users/${target}/notificationInbox`).get();
    assert.equal(inbox.size,1); assert.equal(inbox.docs[0].get("type"),"systemAnnouncement");
    assert.equal(inbox.docs[0].get("title"),"Ratgeberzugriff erteilt");
    assert.equal(inbox.docs[0].get("userId"),target);
    assert.equal((await db.collection(`users/${reader}/notificationInbox`).get()).size,0);
    assert.equal((await db.collection("auditLogs").where("targetUserId","==",target).get()).size,1);
    assert.equal((await db.collection("systemLogs").where("targetId","==",target).get()).docs[0].get("isAppAdminReadable"),false);
    await assert.rejects(manageDirectoryEditorAccess.run(mutate(absent,false)),{code:"aborted"});
    const current = directoryGrantState(await ref.get());
    await manageDirectoryEditorAccess.run(mutate(current,false));
    assert.equal((await ref.get()).get("enabled"),false);
    await assert.rejects(manageDirectoryEditorAccess.run(grantRequest),{code:"aborted"});
    const afterRevoke = directoryGrantState(await ref.get());
    // Existing released clients may replace the record or delete it directly.
    await ref.set({enabled:true,grantedBy:owner,grantedAt:Timestamp.now()});
    await assert.rejects(manageDirectoryEditorAccess.run(mutate(afterRevoke,false)),{code:"aborted"});
    const legacy = directoryGrantState(await ref.get());
    assert.ok(legacy.revision?.includes(":"));
    await db.doc(`users/${target}`).delete();
    await manageDirectoryEditorAccess.run(mutate(legacy,false));
    assert.equal((await ref.get()).get("enabled"),false);
    const list = await manageDirectoryEditorAccess.run(request("list")) as {grants:{id:string}[]};
    assert.ok(!list.grants.some(g=>g.id===target));
    await db.doc(`users/${owner}`).update({globalRole:"user"});
    await assert.rejects(manageDirectoryEditorAccess.run(request("list")),{code:"permission-denied"});
  } finally { await cleanup(); }
});

test("directory access inspect and grants pagination has no first-page blind spot", {skip:!enabled},async()=>{
  await seed(); const ids = Array.from({length:45},(_,i)=>`${prefix}-page-${String(i).padStart(2,"0")}`);
  try {
    const batch = db.batch(); for (const uid of ids) batch.set(db.doc(`directoryEditors/${uid}`),{enabled:true,grantedAt:Timestamp.now()}); await batch.commit();
    const found = new Set<string>(); let cursor: string|null = null;
    do {
      const page = await manageDirectoryEditorAccess.run(request("list",{cursor})) as {grants:{id:string}[];cursor:string|null};
      for (const grant of page.grants) found.add(grant.id); cursor=page.cursor;
    } while (cursor);
    for (const uid of ids) assert.ok(found.has(uid));
    const inspect = await manageDirectoryEditorAccess.run(request("inspect",{userIds:[ids[44],target]})) as {grants:{id:string;enabled:boolean;revision:string|null}[]};
    assert.equal(inspect.grants[0].enabled,true); assert.equal(inspect.grants[1].revision,null);
    await assert.rejects(manageDirectoryEditorAccess.run(request("inspect",{userIds:Array(41).fill(target)})),{code:"invalid-argument"});
  } finally { await Promise.all(ids.map(uid=>db.doc(`directoryEditors/${uid}`).delete())); await cleanup(); }
});
