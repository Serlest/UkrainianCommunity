// Disposable local fixtures for the Build80 SDK journey. Never contacts a live project.
const {createRequire} = require('node:module');
const localRequire = createRequire(require('node:path').join(__dirname, '../functions/package.json'));
const projectId = 'demo-uac-release-audit';
for (const [key, value] of Object.entries({GCLOUD_PROJECT: projectId, FIRESTORE_EMULATOR_HOST: '127.0.0.1:28080', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19099', FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:29199'})) {
  if (process.env[key] && process.env[key] !== value) throw new Error(`Refusing conflicting ${key}`);
  process.env[key] = value;
}
const {initializeApp} = localRequire('firebase-admin/app');
const {getFirestore, Timestamp} = localRequire('firebase-admin/firestore');
const {getAuth} = localRequire('firebase-admin/auth');
initializeApp({projectId});
(async () => {
  const db = getFirestore(), auth = getAuth();
  for (const role of ['owner', 'user']) {
    const uid = `fix80-sdk-${role}`;
    await auth.createUser({uid, email: `fix80-${role}@uac.test`, password: 'Emulator-Only-2026!', emailVerified: true});
    await db.doc(`users/${uid}`).set({id: uid, globalRole: role, accountStatus: 'active', blockState: 'active', requiresMultiFactorAuth: false});
  }
  await db.doc('news/fix80-sdk-news').set({id: 'fix80-sdk-news', title: 'Build80 SDK fixture', moderationStatus: 'pendingReview', updatedAt: Timestamp.now()});
  await db.doc('users/fix80-sdk-owner/blockedUsers/fix80-sdk-deleted').set({displayName: 'Deleted fixture', blockedAt: Timestamp.now()});
  console.log('Build80 SDK fixture ready in local demo project.');
})().catch(error => {console.error(error.message); process.exitCode = 1;});
