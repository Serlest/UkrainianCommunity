// Disposable fixtures for the connected iOS audit. Fixed loopback/demo transport only.
const {createRequire}=require('node:module');
const req=createRequire(require('node:path').join(__dirname,'../functions/package.json'));
const project='demo-uac-release-audit';
for(const [key,value] of Object.entries({GCLOUD_PROJECT:project,GOOGLE_CLOUD_PROJECT:project,FIRESTORE_EMULATOR_HOST:'127.0.0.1:28080',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:19099',FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:29199'})) {
 if(process.env[key] && process.env[key]!==value) throw Error('Refusing conflicting '+key);
 process.env[key]=value;
}
const {initializeApp}=req('firebase-admin/app');
const {getAuth}=req('firebase-admin/auth');
const {Firestore,Timestamp}=req('firebase-admin/firestore');
initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:'owner',expires_in:3600})}});
const db=new Firestore({projectId:project,host:'127.0.0.1:28080',ssl:false});
const auth=getAuth();
(async()=>{
 const now=Timestamp.now(),future=Timestamp.fromMillis(Date.now()+7*86400000);
 for(const role of ['owner','member','other','editor']) {
  const uid='closure-'+role,email=uid+'@uac.test';
  try {
   const existing=await auth.getUser(uid);
   if(existing.email!==email)throw Error('Unowned identity');
   await auth.updateUser(uid,{password:'Emulator-Only-2026!',emailVerified:true,displayName:uid});
  } catch(e) {
   if(e.code!=='auth/user-not-found')throw e;
   await auth.createUser({uid,email,password:'Emulator-Only-2026!',emailVerified:true,displayName:uid});
  }
  await db.doc('users/'+uid).set({id:uid,email,fullName:uid,displayName:uid,globalRole:role==='owner'?'owner':'user',accountStatus:'active',blockState:'active',requiresMultiFactorAuth:false,selectedFederalState:'tirol',acceptedTermsVersion:'2026.1',acceptedPrivacyVersion:'2026.1',createdAt:now,updatedAt:now,auditFixture:'closure-20261025'});
 }
 for(const role of ['owner','member','other','editor']) {
  const uid='closure-'+role;
  await db.doc('publicProfiles/'+uid).set({id:uid,displayName:uid,city:'Innsbruck',federalState:'tirol',updatedAt:now});
 }
 await db.doc('directoryEditors/closure-editor').set({enabled:true,revision:1,updatedAt:now});
 const {createHash}=require('node:crypto');
 const hash=s=>createHash('sha256').update(s).digest('hex');
 for(const type of ['terms','privacy','organizationRules']) {
  const locales=Object.fromEntries(['de','uk'].map(locale=>{const title='Audit '+type+' '+locale,contentMarkdown='Local test document. Not production legal terms.';return [locale,{title,contentMarkdown,contentHash:hash(contentMarkdown)}];}));
  const contentHash=hash(Object.keys(locales).sort().map(locale=>[locale,locales[locale].title,locales[locale].contentMarkdown,locales[locale].contentHash].join('\n')).join('\n---\n'));
  const metadata={documentType:type,version:'2026.1',versionNumber:202601,status:'published',requiresAcceptance:true,defaultLocale:'de',canonicalLocale:'de'};
  await db.doc('legalDocuments/'+type).set({...metadata,activeVersion:'2026.1'});
  await db.doc('legalDocuments/'+type+'/versions/2026.1').set({...metadata,locales,contentHash,updatedAt:now,publishedAt:now});
 }
 const common={moderationStatus:'approved',regionScope:'federalState',federalState:'tirol',authorId:'closure-owner',authorName:'Closure Owner',sourceType:'organization',organizationId:'closure-org',organizationName:'Closure Organization',createdAt:now,updatedAt:now,publishedAt:now};
 await db.doc('organizations/closure-org').set({id:'closure-org',name:'Closure Organization',description:'Isolated test organization',shortDescription:'Isolated test organization',fullDescription:'Isolated test organization details',regionScope:'federalState',federalState:'tirol',ownerId:'closure-owner',adminIds:[],moderatorIds:[],city:'Innsbruck',moderationStatus:'approved',createdAt:now,updatedAt:now,likeState:'notLiked',likeCount:0,subscriberCount:0,eventsHeldCount:0,volunteersCount:0,helpedPeopleCount:0,languages:[],socialLinks:{}});
 await db.doc('news/closure-news').set({...common,id:'closure-news',title:'Closure News',subtitle:'SDK fixture',summary:'SDK fixture',body:'SDK fixture details',likeState:'notLiked',likeCount:0,commentCount:0,viewCount:0});
 const {publishedAt: _newsPublishedAt, ...eventCommon}=common;
 await db.doc('events/closure-event').set({...eventCommon,id:'closure-event',title:'Closure Event',summary:'SDK fixture',details:'SDK fixture details',city:'Innsbruck',venue:'Test hall',startDate:future,endDate:Timestamp.fromMillis(future.toMillis()+3600000),requiresRegistration:true,capacity:10000,registeredCount:0,registrationState:'notRegistered',price:0,pricing:{kind:'free'},category:'meetups',additionalCategories:[],audience:'everyone',tags:[],visibility:'public',isAllDay:false,likeState:'notLiked',likeCount:0,commentCount:0,viewCount:0});
 if(process.argv.includes('--load')) {
  const source=(await db.doc('events/closure-event').get()).data();
  await db.doc('events/closure-large-event').set({...source,id:'closure-large-event',registeredCount:1000});
  for(let offset=0;offset<1000;offset+=200) {
   const batch=db.batch();
   for(let index=offset;index<Math.min(offset+200,1000);index++) {
    const uid='closure-attendee-'+String(index).padStart(4,'0');
    const registeredAt=Timestamp.fromMillis(now.toMillis()+index*1000);
    batch.set(db.doc('publicProfiles/'+uid),{id:uid,displayName:'Audit Attendee '+index,city:'Innsbruck',federalState:'tirol',updatedAt:now,auditFixture:'closure-20261025'});
    batch.set(db.doc('registrations/event_closure-large-event_'+uid),{id:'event_closure-large-event_'+uid,eventId:'closure-large-event',userId:uid,registeredAt,createdAt:registeredAt,auditFixture:'closure-20261025'});
   }
   await batch.commit();
  }
 }
 console.log(JSON.stringify({project,fixture:'closure-20261025',users:4,content:3,loadAttendees:process.argv.includes('--load')?1000:0,status:'seeded'}));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
