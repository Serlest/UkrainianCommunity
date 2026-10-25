// Block 11 connected audit. Requires existing disposable closure fixtures; never creates credentials.
const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
const project='demo-uac-release-audit';
for(const [key,value] of Object.entries({GCLOUD_PROJECT:project,GOOGLE_CLOUD_PROJECT:project,FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099',FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:29199'})) {
 if(process.env[key] && process.env[key]!==value) throw Error('Conflicting emulator endpoint: '+key);
 process.env[key]=value;
}
const {initializeApp}=req('firebase-admin/app');
const {Firestore,Timestamp}=req('firebase-admin/firestore');
initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:'owner',expires_in:3600})}});
const db=new Firestore({projectId:project,host:'127.0.0.1:28080',ssl:false});
const {buildAdminSearchGrams}=req('./lib/users/adminUserSearch.js');
(async()=>{
 const target=db.doc('users/closure-member');const original=(await target.get()).data();
 if(!original)throw Error('Missing original controlled demo account');
 await db.doc('users/closure-owner').update({globalRole:'owner',accountStatus:'active',blockState:'active',requiresMultiFactorAuth:true,passkeyEpoch:'moderation-demo-epoch'});
 const data={...original,displayName:'Audit Member',fullName:'Audit Member',globalRole:'user',role:'user',requiresMultiFactorAuth:false,
   accountStatus:'active',blockState:'active',isBlocked:false,warningCount:0,banExpiresAt:null,statusUpdatedAt:null,statusUpdatedBy:null,statusReason:null,statusMessage:null};
 delete data.adminSearchGramsV1;delete data.auditFixture;
 data.adminSearchGramsV1=buildAdminSearchGrams('closure-member',data);
 await target.set(data);
 const base=(await db.doc('organizations/closure-org').get()).data();if(!base)throw Error('Missing controlled demo organization template');
 await db.doc('organizations/users-audit-org').set({...base,id:'users-audit-org',name:'User Administration Audit Organization',localizations:{},ownerId:'closure-owner',adminIds:['closure-member'],moderatorIds:[],updatedAt:Timestamp.now(),moderationStatus:'approved'});
 console.log(JSON.stringify({project,productionWrites:false,target:'closure-member',organization:'users-audit-org'}));
})();
