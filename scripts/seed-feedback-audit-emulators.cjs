// Fixed disposable demo project and loopback endpoints; never connects to production.
const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
for(const [key,value] of Object.entries({GCLOUD_PROJECT:'demo-uac-release-audit',FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099'}))process.env[key]=value;
const {initializeApp}=req('firebase-admin/app'),{getFirestore,Timestamp}=req('firebase-admin/firestore'),{getAuth}=req('firebase-admin/auth');
initializeApp({projectId:'demo-uac-release-audit'});
(async()=>{const db=getFirestore(),auth=getAuth();const terms=(await db.doc('legalDocuments/terms').get()).get('activeVersion');const privacy=(await db.doc('legalDocuments/privacy').get()).get('activeVersion');if(!terms||!privacy)throw Error('Disposable legal fixtures required');
for(const [suffix,role] of [['reporter','user'],['manager','owner'],['other','user'],['admin','admin']]){const uid='feedback-audit-'+suffix;
try{await auth.getUser(uid);}catch{await auth.createUser({uid,email:uid+'@uac.test',password:'Emulator-Only-2026!',emailVerified:true});}
await db.doc('users/'+uid).set({id:uid,createdAt:Timestamp.now(),updatedAt:Timestamp.now(),acceptedTermsAt:Timestamp.now(),acceptedPrivacyAt:Timestamp.now(),bio:'',displayName:uid,fullName:uid,email:uid+'@uac.test',globalRole:role,role:role,accountStatus:'active',blockState:'active',requiresMultiFactorAuth:false,acceptedTermsVersion:terms,acceptedPrivacyVersion:privacy,selectedFederalState:'tirol',city:'Innsbruck'});
}const source=await db.doc('news/closure-news').get();if(!source.exists)throw Error('Missing isolated news fixture');await db.doc('news/feedback-audit-target').set({...source.data(),id:'feedback-audit-target',title:'Feedback isolated target',localizations:{},authorId:'feedback-audit-other',moderationStatus:'approved'});console.log('Seeded isolated feedback accounts and report target');})().catch(e=>{console.error(e.message);process.exit(1)});
