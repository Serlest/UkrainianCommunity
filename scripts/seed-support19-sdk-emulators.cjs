// Reset only the named disposable loopback project, then add a non-owner reader.
if (!process.argv.includes('--reset-disposable-demo')) throw Error('Explicit disposable reset required');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
for (const [name, expected] of Object.entries({GCLOUD_PROJECT:'demo-uac-release-audit',GOOGLE_CLOUD_PROJECT:'demo-uac-release-audit',FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099'})) {
  if (process.env[name] && process.env[name] !== expected) throw Error('Conflicting demo transport');
  process.env[name] = expected;
}
const seeded = spawnSync(process.execPath, [path.join(__dirname,'seed-legal18-sdk-emulators.cjs'),'--reset-disposable-demo'], {stdio:'inherit'});
if (seeded.status !== 0) process.exit(seeded.status || 1);
const req=require('node:module').createRequire(path.resolve('functions/package.json'));
const {initializeApp}=req('firebase-admin/app'),{getAuth}=req('firebase-admin/auth'),{Firestore,Timestamp}=req('firebase-admin/firestore');
initializeApp({projectId:'demo-uac-release-audit',credential:{getAccessToken:async()=>({access_token:'owner',expires_in:3600})}});
(async()=>{
 const db=new Firestore({projectId:'demo-uac-release-audit',host:'127.0.0.1:28080',ssl:false});
 await getAuth().createUser({uid:'support19-sdk-admin',email:'support19-sdk-admin@uac.test',password:'Emulator-Only-2026!',emailVerified:true});
 const owner=(await db.doc('users/legal18-sdk-owner').get()).data();
 await db.doc('users/support19-sdk-admin').set({...owner,id:'support19-sdk-admin',email:'support19-sdk-admin@uac.test',globalRole:'admin',displayName:'Support SDK Admin',createdAt:Timestamp.now()});
 console.log('Support19 owner/admin SDK fixtures ready on loopback');
})().catch(error=>{console.error(error);process.exitCode=1;});
