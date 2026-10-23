import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {collection,doc,setDoc,query,orderBy,documentId,limit,startAfter,getDocs} from 'firebase/firestore';

test('saved content pages advance within the authenticated account for every content type',async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-uac-saved-pages',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 try {
  await env.withSecurityRulesDisabled(async ctx=>{
   for(const kind of ['newsBookmarks','eventBookmarks','organizationBookmarks'])
    for(const id of ['a','b','c']) await setDoc(doc(ctx.firestore(),'users/owner/'+kind+'/'+id),{id,userId:'owner'});
  });
  const db=env.authenticatedContext('owner',{email_verified:true}).firestore();
  for(const kind of ['newsBookmarks','eventBookmarks','organizationBookmarks']){
   const base=query(collection(db,'users/owner/'+kind),orderBy(documentId()),limit(2));
   const first=await assertSucceeds(getDocs(base));
   const next=await assertSucceeds(getDocs(query(base,startAfter(first.docs.at(-1).id))));
   assert.deepEqual(first.docs.map(x=>x.id),['a','b']);assert.deepEqual(next.docs.map(x=>x.id),['c']);
   await assertFails(getDocs(query(collection(env.authenticatedContext('other').firestore(),'users/owner/'+kind),orderBy(documentId()),limit(20))));
  }
 } finally {await env.cleanup();}
});
