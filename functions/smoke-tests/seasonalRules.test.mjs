import {after, before, beforeEach, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {assertFails, assertSucceeds, initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc, getDoc, collection, getDocs, setDoc, deleteDoc, serverTimestamp} from 'firebase/firestore';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';
let environment;
before(async () => {
  environment = await initializeTestEnvironment({projectId:'demo-uac-seasonal', firestore:{rules:readFileSync(new URL('../../Firebase/firestore.rules',import.meta.url),'utf8')}});
});
after(async () => environment?.cleanup());
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    for (const [id,role,status] of [['owner','owner','active'],['reader','user','active'],['admin','admin','active'],['blocked','owner','blocked']]) {
      await setDoc(doc(context.firestore(),'users',id),{id,globalRole:role,accountStatus:status,blockState:'active'});
    }
  });
  await seedCurrentLegalVersions(environment);
});
const db = uid => uid ? environment.authenticatedContext(uid,{email:`${uid}@example.com`,email_verified:true}).firestore() : environment.unauthenticatedContext().firestore();
const payload = (revision='revision-00000001') => ({schemaVersion:1,payload:'{"schemaVersion":1,"themes":[]}',revision,updatedBy:'owner',updatedAt:serverTimestamp()});
test('public schedule is a single public get; drafts and collection enumeration remain private', async () => {
  await assertSucceeds(setDoc(doc(db('owner'),'seasonalLibraries/current'),payload()));
  await assertSucceeds(setDoc(doc(db('owner'),'seasonalPresentations/current'),payload()));
  for (const uid of [null,'reader','admin','owner']) await assertSucceeds(getDoc(doc(db(uid),'seasonalPresentations/current')));
  for (const uid of [null,'reader','admin']) await assertFails(getDoc(doc(db(uid),'seasonalLibraries/current')));
  await assertSucceeds(getDoc(doc(db('owner'),'seasonalLibraries/current')));
  await assertFails(getDocs(collection(db('owner'),'seasonalLibraries')));
  await assertFails(getDoc(doc(db(null),'seasonalPresentations/other')));
});
test('only current verified active owner can create either document',async () => {
  for(const path of ['seasonalLibraries/current','seasonalPresentations/current']) {
    for(const uid of [null,'reader','admin','blocked']) await assertFails(setDoc(doc(db(uid),path),{...payload(),updatedBy:uid??'owner'}));
    await assertSucceeds(setDoc(doc(db('owner'),path),payload()));
  }
});
test('schema, payload budget, revision changes, actor and timestamp are enforced; delete is denied',async () => {
  const ref=doc(db('owner'),'seasonalLibraries/current');
  await assertSucceeds(setDoc(ref,payload()));
  await assertFails(setDoc(ref,payload()));
  await assertFails(setDoc(ref,{...payload('revision-00000002'),payload:'x'.repeat(240001)}));
  await assertFails(setDoc(ref,{...payload('revision-00000002'),schemaVersion:2}));
  await assertFails(setDoc(ref,{...payload('revision-00000002'),updatedBy:'reader'}));
  await assertFails(setDoc(ref,{...payload('revision-00000002'),updatedAt:new Date(0)}));
  await assertFails(setDoc(ref,{...payload('revision-00000002'),extra:true}));
  await assertSucceeds(setDoc(ref,payload('revision-00000002')));
  await assertFails(deleteDoc(ref));
});
test('saving a reusable library does not change the public schedule',async () => {
  const schedule=doc(db('owner'),'seasonalPresentations/current');
  await assertSucceeds(setDoc(schedule,payload()));
  await assertSucceeds(setDoc(doc(db('owner'),'seasonalLibraries/current'),payload('revision-00000002')));
  const snapshot=await assertSucceeds(getDoc(schedule));
  if(snapshot.data().revision!=='revision-00000001') throw Error('Library write changed live presentation');
});
