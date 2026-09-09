// Mirror only publicly readable published legal documents into a fixed local demo project.
const {createRequire} = require('node:module');
const localRequire = createRequire(require('node:path').join(__dirname, '../functions/package.json'));
const projectId = 'demo-uac-release-audit';
for (const [key, value] of Object.entries({GCLOUD_PROJECT: projectId, FIRESTORE_EMULATOR_HOST: '127.0.0.1:28080'})) {
  if (process.env[key] && process.env[key] !== value) throw new Error(`Refusing conflicting ${key}`);
  process.env[key] = value;
}
const {initializeApp} = localRequire('firebase-admin/app');
const {getFirestore, Timestamp} = localRequire('firebase-admin/firestore');
initializeApp({projectId});
function decode(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('nullValue' in value) return null;
  if ('timestampValue' in value) return Timestamp.fromDate(new Date(value.timestampValue));
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([key, child]) => [key, decode(child)]));
  throw new Error('Unsupported public document value');
}
async function publicDocument(path) {
  const response = await fetch('https://firestore.googleapis.com/v1/projects/ukrainiancommunity-dbd5f/databases/(default)/documents/' + path);
  if (!response.ok) throw new Error(`Public read failed: ${response.status}`);
  const data = await response.json();
  return decode({mapValue: {fields: data.fields}});
}
(async () => {
  const db = getFirestore();
  for (const type of ['terms', 'privacy', 'organizationRules']) {
    const pointerPath = `legalDocuments/${type}`, pointer = await publicDocument(pointerPath);
    const versionPath = `${pointerPath}/versions/${pointer.activeVersion}`;
    const version = await publicDocument(versionPath);
    await db.doc(versionPath).set(version);
    await db.doc(pointerPath).set(pointer);
    console.log(`Mirrored ${type} ${pointer.activeVersion} into local demo only.`);
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
