import {test, before, after} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc} from 'firebase/firestore';
let env;
before(async () => { env = await initializeTestEnvironment({projectId:'demo-uac-announcement-rules',firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}}); });
after(async () => { await env?.cleanup(); });
test('clients including owner cannot bypass announcement callables', async () => {
 await env.withSecurityRulesDisabled(async context => {
  for (const role of ['owner','admin','user']) await setDoc(doc(context.firestore(),'users',role),
   {id:role,globalRole:role,accountStatus:'active',blockState:'active',emailVerified:true});
 });
 for (const role of ['guest','owner','admin','user']) {
  const db = role === 'guest' ? env.unauthenticatedContext().firestore() : env.authenticatedContext(role,{email_verified:true}).firestore();
  for (const path of ['announcements/private','announcementDevices/secret','announcements/private/metrics/person','users/user/announcementReceipts/private','announcementTranslationLimits/owner']) {
   await assertFails(getDoc(doc(db,path))); await assertFails(setDoc(doc(db,path),{status:'published',verified:true,acknowledgedAt:1}));
  }
 }
});
