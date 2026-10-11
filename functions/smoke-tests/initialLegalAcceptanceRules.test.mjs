import {before, after, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, setDoc, writeBatch, serverTimestamp, updateDoc} from 'firebase/firestore';
let env;
const hash = 'a'.repeat(64);
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-uac-build80-legal', firestore: {rules: readFileSync(new URL('../../Firebase/firestore.rules', import.meta.url), 'utf8')}});
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    for (const type of ['terms', 'privacy']) {
      const value = {documentType: type, version: '2026.13', versionNumber: 202613, status: 'published', requiresAcceptance: type === 'terms', contentHash: hash};
      await setDoc(doc(context.firestore(), `legalDocuments/${type}`), {...value, activeVersion: value.version});
      await setDoc(doc(context.firestore(), `legalDocuments/${type}/versions/${value.version}`), value);
    }
  });
});
after(async () => { await env?.cleanup(); });
function database(uid, verified = false) {return env.authenticatedContext(uid, {email_verified: verified, email: `${uid}@example.org`}).firestore();}
function user(uid) {return {id: uid, fullName: 'Test', displayName: 'Test', city: 'Wien', email: `${uid}@example.org`, bio: '', globalRole: 'user', isBlocked: false, blockState: 'active', accountStatus: 'active', warningCount: 0, selectedFederalState: 'Wien', acceptedTermsAt: serverTimestamp(), acceptedPrivacyAt: serverTimestamp(), acceptedTermsVersion: '2026.13', acceptedPrivacyVersion: '2026.13', termsVersion: '2026.13', privacyVersion: '2026.13', minimumAgeConfirmedAt: serverTimestamp(), minimumAgeVersion: '14+', communityMemberships: [], createdAt: serverTimestamp(), updatedAt: serverTimestamp()};}
function registration(uid, override = {}, types = ['terms', 'privacy']) {
  const db = database(uid), batch = writeBatch(db);
  batch.set(doc(db, `users/${uid}`), user(uid));
  for (const type of types) batch.set(doc(db, `legalAcceptanceLogs/${uid}_${type}_2026.13`), {userId: uid, documentType: type, version: '2026.13', acceptedAt: serverTimestamp(), appVersion: '1.1', locale: 'uk', contentHash: hash, acceptedFromPlatform: 'ios', ...override});
  return batch.commit();
}
test('unverified registration atomically stores both exact receipts and they cannot be rewritten', async () => {
  await assertSucceeds(registration('valid'));
  await assertFails(updateDoc(doc(database('valid'), 'legalAcceptanceLogs/valid_terms_2026.13'), {contentHash: 'b'.repeat(64)}));
});
test('Android registration uses the same atomic legal evidence contract', async () => {
  await assertSucceeds(registration('android', {acceptedFromPlatform: 'android'}));
});
test('forged hash and incomplete receipt pair are rejected', async () => {
  await assertFails(registration('forged', {contentHash: 'b'.repeat(64)}));
  await assertFails(registration('incomplete', {}, ['terms']));
});
test('a profile cannot be created without the exact legal receipt pair', async () => {
  await assertFails(setDoc(doc(database('legacy'), 'users/legacy'), user('legacy')));
});
test('outdated terms or privacy blocks account writes until acknowledged', async () => {
  await assertSucceeds(registration('current'));
  const profile = doc(database('current', true), 'users/current');
  await assertSucceeds(updateDoc(profile, {displayName: 'Current user', updatedAt: serverTimestamp()}));
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'legalDocuments/terms'), {activeVersion: '2026.14'});
  });
  await assertFails(updateDoc(profile, {displayName: 'Stale terms', updatedAt: serverTimestamp()}));
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'users/current'), {acceptedTermsVersion: '2026.14'});
    await updateDoc(doc(context.firestore(), 'legalDocuments/privacy'), {activeVersion: '2026.14'});
  });
  await assertFails(updateDoc(profile, {displayName: 'Stale privacy', updatedAt: serverTimestamp()}));
  await env.withSecurityRulesDisabled(async context => {
    await updateDoc(doc(context.firestore(), 'users/current'), {acceptedPrivacyVersion: '2026.14'});
  });
  await assertSucceeds(updateDoc(profile, {displayName: 'Both current', updatedAt: serverTimestamp()}));
});
