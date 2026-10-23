import {test} from 'node:test';
import assert from 'node:assert/strict';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {collection,doc,setDoc,query,where,orderBy,documentId,limit,startAfter,getDocs} from 'firebase/firestore';

test('subscription prefix pages exclude ordinary likes and protect other users',async()=>{
 const env=await initializeTestEnvironment({projectId:'demo-uac-subscription-pages',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 try {
  await seedCurrentLegalVersions(env);
  await env.withSecurityRulesDisabled(async ctx=>{
   for(const uid of ['member','other']) await setDoc(doc(ctx.firestore(),'users/'+uid),{id:uid,globalRole:'user',accountStatus:'active',blockState:'active',acceptedTermsVersion:'2026.13',acceptedPrivacyVersion:'2026.13'});
   for(const id of ['organization_follow_a_member','organization_follow_b_member','organization_follow_c_member','news_like_a_member'])
    await setDoc(doc(ctx.firestore(),'likes/'+id),{userId:'member',subscribedOrganizationId:'org'});
   await setDoc(doc(ctx.firestore(),'likes/organization_follow_z_other'),{userId:'other',subscribedOrganizationId:'org'});
  });
  const db=env.authenticatedContext('member',{email_verified:true}).firestore();
  const base=query(collection(db,'likes'),where('userId','==','member'),where(documentId(),'>=','organization_follow_'),where(documentId(),'<','organization_follow_\uf8ff'),orderBy(documentId()),limit(2));
  const first=await assertSucceeds(getDocs(base));
  const next=await assertSucceeds(getDocs(query(base,startAfter(first.docs.at(-1).id))));
  assert.equal(first.size,2);assert.equal(next.size,1);assert.ok([...first.docs,...next.docs].every(x=>x.id.startsWith('organization_follow_')));
  await assertFails(getDocs(query(collection(db,'likes'),where('userId','==','other'),orderBy(documentId()),limit(20))));
 } finally {await env.cleanup();}
});
