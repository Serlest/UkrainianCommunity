import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {collection,doc,setDoc,query,where,orderBy,limit,startAfter,getDocs,getDoc,Timestamp,writeBatch,runTransaction} from 'firebase/firestore';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';

const history=(db,uid='member')=>collection(db,`users/${uid}/recentViews`);
const row=(n)=>({itemId:String(n),itemType:'news',title:`Story ${n}`,viewedAt:Timestamp.fromMillis(n*1000)});
const unchangedDelete=async(db,documents)=>runTransaction(db,async transaction=>{
 const current=await Promise.all(documents.map(x=>transaction.get(x.ref)));
 documents.forEach((x,i)=>{
  if(x.data().viewedAt.isEqual(current[i].data()?.viewedAt)) transaction.delete(x.ref);
 });
});

test('private recent history supports writes, bounded retention and chunked clearing',async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-uac-recent-history',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 try {
  await env.withSecurityRulesDisabled(async ctx=>{
   const db=ctx.firestore();
   for(const uid of ['member','other']) await setDoc(doc(db,'users/'+uid),{id:uid,globalRole:'user',accountStatus:'active',blockState:'active',acceptedTermsVersion:'2026.13',acceptedPrivacyVersion:'2026.13'});
   for(let offset=0;offset<835;offset+=400){
    const batch=writeBatch(db);
    for(let n=offset;n<Math.min(offset+400,835);n++) batch.set(doc(history(db),'news_'+n),row(n));
    await batch.commit();
   }
  });
  await seedCurrentLegalVersions(env);
  const db=env.authenticatedContext('member',{email_verified:true}).firestore();
  await assertSucceeds(setDoc(doc(history(db),'event_test'),{...row(840),itemId:'test',itemType:'event'}));
  await assertFails(getDocs(history(db,'other')));
  await assertFails(setDoc(doc(history(db,'other'),'news_1'),row(1)));
  await assertFails(setDoc(doc(history(db),'bad_id'),row(1)));
  const newest=await assertSucceeds(getDocs(query(history(db),orderBy('viewedAt','desc'),limit(30))));
  assert.equal(newest.size,30);
  const stale=query(history(db),orderBy('viewedAt','desc'),startAfter(newest.docs.at(-1)),limit(400));
  let removed=0;
  for(;;){
   const page=await assertSucceeds(getDocs(stale)); if(page.empty) break;
   await assertSucceeds(unchangedDelete(db,page.docs)); removed+=page.size;
  }
  assert.equal(removed,806);
  assert.equal((await getDocs(history(db))).size,30);
  // A new view between the selection and transaction must survive deletion.
  const old=await getDocs(query(history(db),orderBy('viewedAt','desc'),limit(1)));
  await setDoc(old.docs[0].ref,{viewedAt:Timestamp.fromMillis(900000)},{merge:true});
  await unchangedDelete(db,old.docs);
  assert.equal((await getDoc(old.docs[0].ref)).data().viewedAt.toMillis(),900000);
  const clearing=query(history(db),where('viewedAt','<=',Timestamp.fromMillis(850000)),limit(400));
  const pending=await getDocs(clearing);
  await assertSucceeds(unchangedDelete(db,pending.docs));
  assert.equal((await getDocs(history(db))).size,1);
 } finally {await env.cleanup();}
});
