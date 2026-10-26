import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {test, before, after} from 'node:test';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc} from 'firebase/firestore';

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const projectId = 'demo-uac-analytics15-rules';
let env;
const paths = [
  'analyticsDailyStats/2026-10-26', 'analyticsTopContent/seven_days',
  'analyticsRegionStats/seven_days', 'analyticsUserStats/seven_days',
  'analyticsContentStats/seven_days', 'analyticsContentStats/seven_days/items/news_fixture',
  'analyticsOrganizationStats/seven_days', 'analyticsOrganizationStats/seven_days/organizations/fixture',
];
const cases = [
  ['owner', 'owner', 'active', true, true, true],
  ['app-admin', 'admin', 'active', true, true, false],
  ['org-owner', 'user', 'active', true, true, false],
  ['org-admin', 'user', 'active', true, true, false],
  ['org-editor', 'user', 'active', true, true, false],
  ['member', 'user', 'active', true, true, false],
  ['warned-member', 'user', 'warned', true, true, false],
  ['blocked-member', 'user', 'blocked', true, true, false],
  ['inactive-owner', 'owner', 'deactivated', true, true, false],
  ['owner-no-mfa', 'owner', 'active', false, true, false],
  ['owner-stale-legal', 'owner', 'active', true, false, false],
];
before(async () => {
  if (!enabled) return;
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:28080');
  env = await initializeTestEnvironment({projectId, firestore: {
    host: '127.0.0.1', port: 28080,
    rules: await readFile(new URL('../../Firebase/firestore.rules', import.meta.url), 'utf8'),
  }});
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'legalDocuments/terms'), {activeVersion:'audit'}),
      setDoc(doc(db, 'legalDocuments/privacy'), {activeVersion:'audit'}),
      ...paths.map(path => setDoc(doc(db,path), {fixture:true})),
      ...cases.map(([id,role,status,mfa,legal]) => setDoc(doc(db,'users/'+id), {
        globalRole:role, accountStatus:status, blockState:status==='blocked'?'blocked':'active',
        requiresMultiFactorAuth:role==='owner'||role==='admin',
        acceptedTermsVersion:legal?'audit':'old', acceptedPrivacyVersion:'audit',
      })),
      ...['owner','admin','editor'].map(role=>setDoc(doc(db,'organizations/org-'+role),{ownerId:'org-owner',admins:['org-admin'],editors:['org-editor']})),
    ]);
  });
});
after(async () => { if (env) await env.cleanup(); });
for (const [id,role,status,mfa,legal,allow] of cases) {
  test('owner analytics rules: '+id, {skip:!enabled}, async () => {
    const db = env.authenticatedContext(id,{email_verified:true,firebase:{sign_in_provider:'password',...(mfa?{sign_in_second_factor:'totp'}:{})}}).firestore();
    for (const path of paths) {
      await (allow ? assertSucceeds(getDoc(doc(db,path))) : assertFails(getDoc(doc(db,path))));
      await assertFails(setDoc(doc(db,path),{fixture:'client-mutation'},{merge:true}));
    }
  });
}
test('owner analytics rules: guest denied every root and nested report', {skip:!enabled}, async () => {
  const db = env.unauthenticatedContext().firestore();
  for (const path of paths) await assertFails(getDoc(doc(db,path)));
});
