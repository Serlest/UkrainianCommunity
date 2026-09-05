// Opt-in local fixtures for FirestoreRepositoryCursorEmulatorTests. Never deploy.
// Usage: node scripts/seed-cursor-sdk-emulators.cjs seed|cleanup cursor-<UUID>
const {createRequire} = require('node:module');
const localRequire = createRequire(require('node:path').join(__dirname, '../functions/package.json'));
const project = 'demo-uac-release-audit';
const fixed = {GCLOUD_PROJECT: project, GOOGLE_CLOUD_PROJECT: project,
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:28080', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19099',
  FIREBASE_STORAGE_EMULATOR_HOST: '127.0.0.1:29199'};
for (const [key, value] of Object.entries(fixed)) {
  if (process.env[key] && process.env[key] !== value) throw new Error(`Refusing conflicting ${key}`);
  process.env[key] = value;
}
const [mode, run] = process.argv.slice(2);
if (!['seed', 'cleanup'].includes(mode) || !/^cursor-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(run || '')) {
  throw new Error('Expected seed|cleanup and cursor-<lowercase UUID>');
}
const {initializeApp} = localRequire('firebase-admin/app');
const {getAuth} = localRequire('firebase-admin/auth');
const {Firestore, Timestamp} = localRequire('firebase-admin/firestore');
// Auth supports this explicit emulator credential; no ADC or service account.
initializeApp({projectId: project, credential: {getAccessToken: async () => ({access_token: 'owner', expires_in: 3600})}});
// Admin getFirestore() rejects custom credentials before checking emulator mode.
// Its exported Firestore client supports an explicit insecure loopback transport:
// ssl:false selects insecure gRPC and supplies the emulator's Bearer owner header.
// Pin the project as well so the client never discovers it via ADC/metadata.
const db = new Firestore({projectId: project, host: fixed.FIRESTORE_EMULATOR_HOST, ssl: false, preferRest: false});
const auth = getAuth();
const seconds = 2000000000; // 2033; test refuses to run after this time is no longer future.
const rows = [111111000, 123456000].flatMap((nanos, group) => [
  [`${group}-before`, nanos - 1000], [`${group}-a`, nanos], [`${group}-b`, nanos],
  [`${group}-c`, nanos], [`${group}-after`, nanos + 1000],
].map(([suffix, n]) => ({id: `${run}-${suffix}`, time: new Timestamp(seconds, n)})));
const paths = [`users/${run}`, ...rows.flatMap(({id}) => [
  `news/${id}`, `events/${id}`, `organizations/${id}`, `likes/${id}`,
  `users/${run}/contentPlanningDrafts/${id}-scheduled`, `users/${run}/contentPlanningDrafts/${id}-recent`,
])];
async function cleanup() {
  // Exact owned paths only. No collection wipe or recursiveDelete.
  for (const path of [...paths].reverse()) {
    const ref = db.doc(path), snapshot = await ref.get();
    if (!snapshot.exists) continue;
    if (snapshot.get('cursorFixtureRun') !== run) throw new Error(`Refusing unowned document ${path}`);
    await ref.delete({lastUpdateTime: snapshot.updateTime});
    if ((await ref.get()).exists) throw new Error(`Cleanup read-back failed: ${path}`);
  }
  let user;
  try { user = await auth.getUser(run); }
  catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  if (user) {
    if (user.email !== `${run}@uac.test` || user.displayName !== run) throw new Error('Refusing unowned Auth user');
    await auth.deleteUser(run);
    try { await auth.getUser(run); throw new Error('Auth cleanup read-back failed'); }
    catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
  }
}
let createdAuth = false;
async function seed() {
  // Regional repository queries also include national cards. Fail on contamination;
  // do not hide it by deleting fixtures owned by another journey/run.
  for (const collection of ['news', 'events', 'organizations']) {
    for (const [field, value] of [['federalState', 'vorarlberg'], ['regionScope', 'austria']]) {
      const existing = await db.collection(collection).where('moderationStatus', '==', 'approved').where(field, '==', value).limit(1).get();
      if (!existing.empty) throw new Error(`Fixture region is occupied in ${collection}; use a clean local demo run`);
    }
  }
  if (!(new Timestamp(seconds, 0).toMillis() > Date.now() + 86400000)) throw new Error('Refresh future fixture seconds before running');
  await auth.createUser({uid: run, email: `${run}@uac.test`, password: 'Emulator-Only-2026!', emailVerified: true, displayName: run});
  createdAuth = true;
  const batch = db.batch();
  batch.create(db.doc(`users/${run}`), {id: run, cursorFixtureRun: run, email: `${run}@uac.test`,
    emailVerified: true, globalRole: 'owner', accountStatus: 'active', blockState: 'active', requiresMultiFactorAuth: false});
  for (const {id, time} of rows) {
    const common = {id, cursorFixtureRun: run, title: id, name: id, description: 'Cursor SDK fixture',
      body: 'Cursor SDK fixture', summary: 'Cursor SDK fixture', details: 'Cursor SDK fixture',
      city: 'Bregenz', venue: 'Local fixture', regionScope: 'federalState', federalState: 'vorarlberg',
      moderationStatus: 'approved', sourceType: 'organization', organizationId: id,
      authorId: run, ownerId: run, createdAt: time, updatedAt: time, publishedAt: time,
      startDate: new Timestamp(seconds - 3600, 0), endDate: time};
    for (const collection of ['news', 'events', 'organizations']) batch.create(db.doc(`${collection}/${id}`), common);
    batch.create(db.doc(`likes/${id}`), {cursorFixtureRun: run, userId: run, subscribedOrganizationId: `${run}-0-a`, createdAt: time});
    for (const [suffix, state] of [['scheduled', 'scheduled'], ['recent', 'readyForReview']]) {
      batch.create(db.doc(`users/${run}/contentPlanningDrafts/${id}-${suffix}`), {
        cursorFixtureRun: run, kind: 'news', state, title: id,
        payload: {title: id, body: 'Cursor SDK fixture'}, createdAt: time, updatedAt: time, scheduledAt: time,
      });
    }
  }
  await batch.commit();
}
(async () => {
  if (mode === 'seed') {
    try { await seed(); }
    catch (error) { if (createdAuth) await cleanup(); throw error; }
  } else await cleanup();
  console.log(JSON.stringify({mode, project, run, documents: paths.length, seconds, status: 'complete'}));
})().catch(error => {console.error(error.message); process.exitCode = 1;});
