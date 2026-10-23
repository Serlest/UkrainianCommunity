// Disposable local Auth/Firestore fixture; never contacts a production project.
const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
for (const [key,value] of Object.entries({GCLOUD_PROJECT:'demo-uac-release-audit',FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099'})) {
 if (process.env[key] && process.env[key] !== value) throw new Error('Refusing conflicting '+key);
 process.env[key]=value;
}
const {initializeApp}=req('firebase-admin/app');
const {getFirestore,Timestamp}=req('firebase-admin/firestore');
const {getAuth}=req('firebase-admin/auth');
initializeApp({projectId:'demo-uac-release-audit'});
(async()=>{
 const auth=getAuth(),db=getFirestore();
 await auth.deleteUser('projection-sdk-user').catch(()=>{});
 await db.doc('publicProfiles/projection-sdk-user').delete();
 await auth.createUser({uid:'projection-sdk-user',email:'projection@uac.test',password:'Emulator-Only-2026!',emailVerified:true});
 await db.doc('legalDocuments/terms').set({activeVersion:'test-terms'});
 await db.doc('legalDocuments/privacy').set({activeVersion:'test-privacy'});
 await db.doc('users/projection-sdk-user').set({id:'projection-sdk-user',email:'projection@uac.test',
  fullName:'Original',displayName:'Original',city:'Wien',bio:'',selectedFederalState:'tirol',globalRole:'user',accountStatus:'active',blockState:'active',
  acceptedTermsVersion:'test-terms',acceptedPrivacyVersion:'test-privacy',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
 console.log('Local projection fixture ready.');
})().catch(e=>{console.error(e.message);process.exit(1)});
