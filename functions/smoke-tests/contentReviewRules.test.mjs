import {after, before, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc, collection, query, where, getDocs, updateDoc, Timestamp} from 'firebase/firestore';
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

function fullDocument(kind,id,status) {
 const stamp=Timestamp.fromMillis(1792670000000);
 const shared={id,title:'Original title',sourceType:'organization',organizationId:'review-org',authorId:'org-owner',authorName:'Author',
 createdAt:stamp,updatedAt:stamp,moderationStatus:status,likeCount:0,likeState:'notLiked',viewCount:0,commentCount:0,regionScope:'austria',
 moderationReason:'Verify the source',moderatedByUserId:'platform-owner',moderatedAt:stamp,moderationOperationId:'review-1',resubmittedByUserId:'org-owner',resubmittedFromRevision:'1792670000:0'};
 return kind==='news'?{...shared,subtitle:'Summary',body:'Full body',publishedAt:stamp}:
 {...shared,summary:'Summary',details:'Full details',city:'Wien',venue:'Community Centre',startDate:stamp,endDate:stamp,price:0,registeredCount:0,registrationState:'open',requiresRegistration:false,visibility:'public',isAllDay:false};
}
test('complete editor saves preserve server review fields across current and returned states',async()=>{
 for(const kind of ['news','events'])for(const status of ['approved','pendingReview','needsRevision','rejected']) {
  const id='edit-'+status, fields=fullDocument(kind,id,status);
  await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),kind,id),fields));
  await assertSucceeds(updateDoc(doc(db('org-owner'),kind,id),{title:'Corrected title',updatedAt:Timestamp.now(),
    ...(kind==='news'&&status==='approved'?{moderationStatus:'pendingReview'}:{})}));
  await assertFails(updateDoc(doc(db('org-owner'),kind,id),{moderationReason:'Forged reason'}));
  await assertFails(updateDoc(doc(db('org-owner'),kind,id),{moderatedByUserId:'org-owner'}));
 }
});
test('new publications cannot forge review or resubmission evidence',async()=>{
 for(const kind of ['news','events']) {
  const id='forged-'+kind, fields=fullDocument(kind,id,'approved');
  await assertFails(setDoc(doc(db('org-owner'),kind,id),fields));
 }
});
