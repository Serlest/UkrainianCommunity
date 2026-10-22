import {after, before, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, collection, query, where, getDocs} from 'firebase/firestore';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';
let env;
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-uac-content-review-rules',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  for(const uid of ['org-owner','org-admin','org-moderator','outsider','platform-owner','platform-admin']) await setDoc(doc(db,'users',uid),{globalRole:uid==='platform-owner'?'owner':uid==='platform-admin'?'admin':'user',accountStatus:'active',blockState:'active'});
  await setDoc(doc(db,'organizations','review-org'),{id:'review-org',ownerId:'org-owner',adminIds:['org-admin'],moderatorIds:['org-moderator'],sourceType:'organization',moderationStatus:'approved'});
  for(const kind of ['news','events']) for(const status of ['pendingReview','needsRevision','rejected','archived']) await setDoc(doc(db,kind,status),{id:status,moderationStatus:status,sourceType:'organization',organizationId:'review-org'});
 });
 await seedCurrentLegalVersions(env);
});
after(async()=>{if(env)await env.cleanup();});
const db=uid=>env.authenticatedContext(uid,{email_verified:true,email:uid+'@example.test'}).firestore();
test('returned content is readable by current team and platform reviewers; outsider and anonymous cannot read it',async()=>{
 for(const kind of ['news','events']) {
  for(const uid of ['org-owner','org-admin','org-moderator','platform-owner','platform-admin']) await assertSucceeds(getDoc(doc(db(uid),kind,'needsRevision')));
  await assertFails(getDoc(doc(db('outsider'),kind,'needsRevision')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),kind,'needsRevision')));
 }
});
test('organization review list supports returned content and preserves existing pending/rejected/archive reads',async()=>{
 for(const kind of ['news','events']) {
  const q=query(collection(db('org-owner'),kind),where('sourceType','==','organization'),where('organizationId','==','review-org'),where('moderationStatus','in',['pendingReview','needsRevision','rejected','archived']));
  await assertSucceeds(getDocs(q));
  for(const status of ['pendingReview','rejected','archived']) await assertSucceeds(getDoc(doc(db('org-owner'),kind,status)));
 }
});
