import {before,after,test} from 'node:test';
import {readFileSync} from 'node:fs';
import {assertFails,assertSucceeds,initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,serverTimestamp} from 'firebase/firestore';
let env;
const fingerprint='12345678 12345678 12345678 12345678 12345678 12345678 12345678 12345678';
const entry=(id,actor='owner')=>({id,createdAt:serverTimestamp(),category:'audit',severity:'info',severityRank:1,eventType:'configurationUpdated',actorUserId:actor,actorRole:actor==='owner'?'owner':'admin',targetType:'donationConfig',targetId:'donation',summary:'Project support configuration updated',outcome:'success',metadata:{resultRevision:fingerprint,isEnabled:'false',confirmation:'serverReadback'},moduleName:'ProjectSupport',operationName:'saveDonationConfig',isReviewed:false,isAppAdminReadable:false,retentionPolicy:'normalAudit'});
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-uac-support19-journal',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 await env.withSecurityRulesDisabled(async ctx=>{const db=ctx.firestore();for(const [uid,role] of [['owner','owner'],['admin','admin'],['user','user']])await setDoc(doc(db,'users/'+uid),{globalRole:role,accountStatus:'active',acceptedTermsVersion:'t',acceptedPrivacyVersion:'p'});await setDoc(doc(db,'legalDocuments/terms'),{activeVersion:'t'});await setDoc(doc(db,'legalDocuments/privacy'),{activeVersion:'p'});});
});
after(async()=>{await env?.cleanup();});
const db=id=>env.authenticatedContext(id,{email_verified:true}).firestore();
test('only owner can record support configuration confirmation; admin cannot read it',async()=>{
 await assertSucceeds(setDoc(doc(db('owner'),'systemLogs/confirmed'),entry('confirmed')));
 await assertSucceeds(getDoc(doc(db('owner'),'systemLogs/confirmed')));
 await assertFails(getDoc(doc(db('admin'),'systemLogs/confirmed')));
 for(const actor of ['admin','user'])await assertFails(setDoc(doc(db(actor),'systemLogs/'+actor),entry(actor,actor)));
});
test('support audit exception cannot expand into other operations or malformed revisions',async()=>{
 for(const patch of [{eventType:'contentDeleted'},{targetType:'userProfile'},{targetId:'other'},{operationName:'deleteAccount'},{moduleName:'Other'},{outcome:'failed'},{actorRole:'admin'},{isAppAdminReadable:true},{metadata:{resultRevision:'[redacted]',isEnabled:'false',confirmation:'serverReadback'}},{metadata:{resultRevision:fingerprint,isEnabled:'false',confirmation:'optimistic'}},{metadata:{resultRevision:fingerprint,isEnabled:'false',confirmation:'serverReadback',extra:'not allowed'}}]) {
  await assertFails(setDoc(doc(db('owner'),'systemLogs/rejected'),{...entry('rejected'),...patch}));
 }
});
