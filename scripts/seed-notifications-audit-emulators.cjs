// Disposable, fixed loopback namespace. This script cannot select a live project.
const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
for(const [key,value] of Object.entries({GCLOUD_PROJECT:'demo-uac-release-audit',FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099'})) {
  if(process.env[key]&&process.env[key]!==value)throw Error('Conflicting emulator endpoint');
  process.env[key]=value;
}
const {initializeApp}=req('firebase-admin/app'),{getFirestore,Timestamp}=req('firebase-admin/firestore'),{getAuth}=req('firebase-admin/auth');
initializeApp({projectId:'demo-uac-release-audit'});
(async()=>{
 const db=getFirestore(),auth=getAuth(),run='notifications-audit-owner-20261026';
 const terms=(await db.doc('legalDocuments/terms').get()).get('activeVersion'),privacy=(await db.doc('legalDocuments/privacy').get()).get('activeVersion');
 if(!terms||!privacy)throw Error('Missing disposable legal fixtures');
 for(const [uid,role] of [[run,'owner'],[run+'-other','user']]){
  try{await auth.getUser(uid);}catch(e){if(e.code!=='auth/user-not-found')throw e;await auth.createUser({uid,email:uid+'@uac.test',password:'Emulator-Only-2026!',emailVerified:true});}
  await db.doc('users/'+uid).set({id:uid,createdAt:Timestamp.now(),updatedAt:Timestamp.now(),acceptedTermsAt:Timestamp.now(),acceptedPrivacyAt:Timestamp.now(),displayName:uid,fullName:uid,email:uid+'@uac.test',globalRole:role,accountStatus:'active',blockState:'active',requiresMultiFactorAuth:false,acceptedTermsVersion:terms,acceptedPrivacyVersion:privacy,selectedFederalState:'tirol',city:'Innsbruck',notificationAuditFixture:true});
 }
 await db.doc('appConfig/announcements').set({enabled:true,iosEnabled:true,pushEnabled:false});
 const inbox=db.collection('users').doc(run).collection('notificationInbox'),batch=db.batch();
 const base=Math.floor(Date.now()/1000)-3600;
 for(let i=0;i<461;i++){
  const id='n13-'+String(i).padStart(3,'0');
  batch.set(inbox.doc(id),{id:'copied-incorrect-id',recipientUserId:'copied-incorrect-person',type:'systemAnnouncement',sourceType:'system',sourceId:'n13-fixture',actionType:'none',title:'Isolated notification '+i,message:'Message '+i,createdAt:new Timestamp(i===460?Math.floor(Date.now()/1000)+86400:base+Math.floor(i/3),(i%3)*1000),isRead:false,archivedAt:null,deletedAt:null,notificationAuditFixture:true});
 }
 await batch.commit();
 console.log(JSON.stringify({project:'demo-uac-release-audit',run,notifications:461,futureProtected:1,status:'seeded'}));
})().catch(e=>{console.error(e.message);process.exit(1)});
