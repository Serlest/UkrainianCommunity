const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
for(const [k,v] of Object.entries({GCLOUD_PROJECT:'demo-uac-release-audit',FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099'})) {
 if(process.env[k]&&process.env[k]!==v)throw Error('Refusing non-fixed emulator endpoint');process.env[k]=v;
}
const {initializeApp}=req('firebase-admin/app'),{getFirestore,Timestamp}=req('firebase-admin/firestore'),{getAuth}=req('firebase-admin/auth');
initializeApp({projectId:'demo-uac-release-audit'});
(async()=>{
 const db=getFirestore(),auth=getAuth();
 for(const id of ['terms','privacy']){const ref=db.doc('legalDocuments/'+id);if(!(await ref.get()).exists)await ref.set({activeVersion:'audit',isPublished:true});}
 const terms=(await db.doc('legalDocuments/terms').get()).get('activeVersion'),privacy=(await db.doc('legalDocuments/privacy').get()).get('activeVersion');
 for(const [uid,role] of [['banners-audit-owner-20261026','owner'],['banners-audit-member-20261026','user']]){
  try{await auth.getUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;await auth.createUser({uid,email:uid+'@uac.test',password:'Emulator-Only-2026!',emailVerified:true});}
  const previous=await db.doc('users/'+uid).get();
  await db.doc('users/'+uid).set({id:uid,globalRole:role,accountStatus:'active',blockState:'active',requiresMultiFactorAuth:false,createdAt:previous.get('createdAt')??Timestamp.now(),updatedAt:Timestamp.now(),acceptedTermsVersion:terms,acceptedPrivacyVersion:privacy,acceptedTermsAt:Timestamp.now(),acceptedPrivacyAt:Timestamp.now()});
 }
 console.log('Fixed emulator owner/member seeded; no production endpoints.');
})().catch(e=>{console.error(e.message);process.exit(1)});
