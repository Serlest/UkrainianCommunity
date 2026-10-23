import {before,after,test} from 'node:test';
import {readFileSync} from 'node:fs';
import {assertFails,assertSucceeds,initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,serverTimestamp} from 'firebase/firestore';
let env;
const data=()=>({isEnabled:true,donationURL:'https://www.paypal.me/example',titleUK:'Підтримати',messageUK:'Дякуємо\nза підтримку',buttonTitleUK:'Відкрити',titleDE:'Unterstützen',messageDE:'Vielen Dank',buttonTitleDE:'Öffnen',updatedAt:serverTimestamp(),updatedBy:'owner'});
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-uac-donation-rules',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
 await env.withSecurityRulesDisabled(async ctx=>{
  for(const role of ['owner','admin','user']) await setDoc(doc(ctx.firestore(),'users/'+role),{globalRole:role,accountStatus:'active',acceptedTermsVersion:'2026.13',acceptedPrivacyVersion:'2026.18'});
  await setDoc(doc(ctx.firestore(),'legalDocuments/terms'),{activeVersion:'2026.13'});
  await setDoc(doc(ctx.firestore(),'legalDocuments/privacy'),{activeVersion:'2026.18'});
 });
});
after(async()=>{await env?.cleanup();});
const db=role=>env.authenticatedContext(role,{email_verified:true}).firestore();
test('only owner can write; the public config remains readable',async()=>{
 await assertSucceeds(setDoc(doc(db('owner'),'appConfig/donation'),data()));
 for(const role of ['admin','user'])await assertFails(setDoc(doc(db(role),'appConfig/donation'),{...data(),updatedBy:role}));
 await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(),'appConfig/donation')));
});
test('HTTPS host, credentials, port and whitespace validation',async()=>{
 for(const donationURL of ['https://not a valid host','http://example.org','https://user:secret@example.org','https://-bad.example.org','https://127.0.0.1','https://example.org:8080','https://example.org/white space','https://example.c2','https://'+('a'.repeat(64))+'.org'])
  await assertFails(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),donationURL}));
 for(const donationURL of ['https://example.org','https://example.org/path?x=1#part','https://www.paypal.me/example','https://example.org:443'])
  await assertSucceeds(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),donationURL}));
});
test('text and URL limits apply; enabled support requires complete translations',async()=>{
 for(const [field,limit] of [['titleUK',120],['titleDE',120],['messageUK',2000],['messageDE',2000],['buttonTitleUK',80],['buttonTitleDE',80]]){
  await assertFails(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),[field]:'x'.repeat(limit+1)}));
  await assertSucceeds(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),[field]:'x'.repeat(limit)}));
  await assertFails(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),[field]:'   '}));
 }
 await assertFails(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),donationURL:'https://example.org/'+ 'a'.repeat(2048)}));
 await assertSucceeds(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),isEnabled:false,donationURL:'',titleDE:''}));
 await assertFails(setDoc(doc(db('owner'),'appConfig/donation'),{...data(),updatedAt:new Date(0)}));
});
