import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {collection,doc,setDoc,getDoc,getDocs,query,where,orderBy,limit,runTransaction,writeBatch,Timestamp} from 'firebase/firestore';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';

const occurredAt=Timestamp.fromMillis(Date.now()-3600000);
const entry=(id,targetId='post')=>({id,actionType:'savedNews',targetId,targetType:'news',title:'Saved story',createdAt:occurredAt});
async function record(db,id,targetId='post') {
 const ref=doc(db,`users/member/activityLog/${id}`);
 await runTransaction(db,async tx=>{
  const existing=await tx.get(ref);
  if(existing.exists()) {
   assert.equal(existing.data().actionType,'savedNews');
   assert.equal(existing.data().targetId,targetId);
   assert.equal(existing.data().targetType,'news');
   return;
  }
  tx.set(ref,entry(id,targetId));
 });
}

test('activity retry is idempotent with immutable rules; bounded private history clears only older records',async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-uac-activity-history',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 try {
  // This suite owns its dedicated demo namespace. A retry must not reuse an
  // immutable "stable" entry from an earlier run with a different occurredAt.
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx=>{
   const db=ctx.firestore();
   for(const uid of ['member','other']) await setDoc(doc(db,'users/'+uid),{id:uid,globalRole:'user',accountStatus:'active',blockState:'active',acceptedTermsVersion:'2026.13',acceptedPrivacyVersion:'2026.13'});
   for(let offset=0;offset<615;offset+=400) {
    const batch=writeBatch(db);
    for(let n=offset;n<Math.min(offset+400,615);n++) {
     const id='old-'+n;
     batch.set(doc(db,'users/member/activityLog/'+id),{...entry(id),createdAt:Timestamp.fromMillis(n*1000)});
    }
    await batch.commit();
   }
  });
  await seedCurrentLegalVersions(env);
  const db=env.authenticatedContext('member',{email_verified:true}).firestore();
  await assertSucceeds(record(db,'stable'));
  const before=await getDoc(doc(db,'users/member/activityLog/stable'));
  await assertSucceeds(record(db,'stable'));
  const after=await getDoc(before.ref);
  assert.ok(before.data().createdAt.isEqual(after.data().createdAt));
  assert.ok(before.data().createdAt.isEqual(occurredAt));
  assert.equal((await getDocs(query(collection(db,'users/member/activityLog'),orderBy('createdAt','desc'),limit(100)))).size,100);
  await assertFails(setDoc(before.ref,entry('stable'))); // Updates remain forbidden.
  await assertFails(getDocs(collection(db,'users/other/activityLog')));
  await assertFails(setDoc(doc(db,'users/other/activityLog/forbidden'),entry('forbidden')));
  await assert.rejects(record(db,'stable','wrong-target'));
  const old=query(collection(db,'users/member/activityLog'),where('createdAt','<=',Timestamp.fromMillis(500000)),limit(400));
  let cleared=0;
  for(;;) {
   const page=await assertSucceeds(getDocs(old)); if(page.empty) break;
   const batch=writeBatch(db); page.docs.forEach(x=>batch.delete(x.ref));
   await assertSucceeds(batch.commit()); cleared+=page.size;
  }
  assert.equal(cleared,501);
  assert.equal((await getDocs(collection(db,'users/member/activityLog'))).size,115);
  assert.ok((await getDoc(before.ref)).exists());
 } finally {await env.cleanup();}
});
