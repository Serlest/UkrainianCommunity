import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {Firestore, FieldValue} from '@google-cloud/firestore';
import {OAuth2Client} from 'google-auth-library';
import {contentAutomationCredential} from './contentAutomationCredential.mjs';
import {validateDirectoryCategoryPayload} from '../lib/directory/directoryValidation.js';
import {directoryMaterials} from '../lib/directory/directoryRecentModel.js';

// Explicit one-time bootstrap only. Normal editorial publication uses the authorized callable.
const [mode, catalogPath, backupPath] = process.argv.slice(2);
if (!['--plan','--apply','--verify'].includes(mode) || !catalogPath || !backupPath) throw Error('Usage: --plan|--apply|--verify catalog.json backup.json');
const projectId = process.env.FIRESTORE_EMULATOR_HOST ? 'demo-uac-directory-bootstrap' : 'ukrainiancommunity-dbd5f';
const raw = fs.readFileSync(catalogPath, 'utf8');
const catalog = JSON.parse(raw);
const sha = createHash('sha256').update(raw).digest('hex');
if (catalog.length !== 25 || new Set(catalog.map(c=>c.id)).size !== 25) throw Error('Expected reviewed 25-category baseline');
for (const c of catalog) validateDirectoryCategoryPayload(JSON.stringify(c), c.id);
const authClient = new OAuth2Client();
if (!process.env.FIRESTORE_EMULATOR_HOST) {
 const token = await (await contentAutomationCredential()).getAccessToken();
 authClient.setCredentials({access_token:token.access_token,expiry_date:Date.now()+token.expires_in*1000});
}
const db = new Firestore({projectId, ...(process.env.FIRESTORE_EMULATOR_HOST ? {} : {authClient})});
const collection = db.collection('directoryCategories');
const marker = db.doc('appConfig/directoryCatalog');
const identity = doc => ({id:doc.id, updateTime:doc.updateTime.toDate().toISOString(), data:doc.data()});
const signature = docs => JSON.stringify(docs.map(d=>[d.id,d.updateTime.toMillis(),d.data().revision,d.data().payload??null,d.data().isDeleted??false]).sort());
try {
 const current = await collection.get();
 const before = await marker.get();
 if(mode === '--plan') {
   if(before.exists) throw Error('Marker exists; use verify, never repeat bootstrap');
   const backup = {projectId, capturedAt:new Date().toISOString(), catalogSHA256:sha, catalog, signature:signature(current.docs), documents:current.docs.map(identity)};
   fs.writeFileSync(backupPath, JSON.stringify(backup,null,2), {flag:'wx',mode:0o600});
   console.log(JSON.stringify({mode,backupPath,sha,preserve:current.docs.map(d=>d.id),create:catalog.filter(c=>!current.docs.some(d=>d.id===c.id)).map(c=>c.id)}));
 } else if(mode === '--apply') {
   const backup = JSON.parse(fs.readFileSync(backupPath,'utf8'));
   if(backup.projectId!==projectId || backup.catalogSHA256!==sha) throw Error('Backup does not match reviewed catalog/project');
   await db.runTransaction(async tx => {
     const [live, config] = await Promise.all([tx.get(collection),tx.get(marker)]);
     if(config.exists || signature(live.docs)!==backup.signature) throw Error('Production changed after backup; re-plan required');
     const all = new Map(live.docs.map(d=>[d.id,d.data()]));
     for(const c of catalog) if(!all.has(c.id)) all.set(c.id,{payload:JSON.stringify(c),revision:1});
     const states = await Promise.all([...all.keys()].map(id=>tx.get(collection.doc(id).collection('recentState').doc('v1'))));
     for(const c of catalog) if(!live.docs.some(d=>d.id===c.id)) {
       const data={id:c.id,payload:JSON.stringify(c),revision:1,updatedBy:'directory-bootstrap-2026-10-17',updatedAt:FieldValue.serverTimestamp(),migration:'directory-cloud-v1'};
       tx.create(collection.doc(c.id),data);
       tx.create(collection.doc(c.id).collection('versions').doc('1'),{...data,previousRevision:0,action:'historical-bootstrap'});
     }
     for(const state of states) {
       const data=all.get(state.ref.parent.parent.id);
       const known=new Set(state.data()?.knownIDs??[]);
       if(data.payload) {validateDirectoryCategoryPayload(data.payload,state.ref.parent.parent.id);for(const m of directoryMaterials(data.payload)) known.add(m.id);}
       tx.set(state.ref,{schemaVersion:1,knownIDs:[...known].sort()});
     }
     tx.create(marker,{schemaVersion:1,source:'firestore',migrationComplete:true,baselineCategoryIDs:catalog.map(c=>c.id),catalogSHA256:sha,migratedAt:FieldValue.serverTimestamp()});
   });
   console.log('APPLIED atomic bootstrap; existing category documents preserved');
 } else {
   const backup=JSON.parse(fs.readFileSync(backupPath,'utf8'));
   if(!before.exists || before.data().migrationComplete!==true) throw Error('Missing migration marker');
   const map=new Map(current.docs.map(d=>[d.id,d]));
   for(const c of catalog) {
     const doc=map.get(c.id);if(!doc) throw Error('Missing '+c.id);
     const old=backup.documents.find(d=>d.id===c.id);
     const expected=old?.data.payload??JSON.stringify(c);
     if(doc.data().payload!==expected || doc.data().revision!==(old?.data.revision??1)) throw Error('Readback mismatch '+c.id);
     const state=await doc.ref.collection('recentState').doc('v1').get();
     const known=new Set(state.data()?.knownIDs??[]);
     if(directoryMaterials(expected).some(m=>!known.has(m.id))) throw Error('Missing historical IDs '+c.id);
   }
   console.log(JSON.stringify({verifiedCategories:catalog.length,preserved:backup.documents.map(d=>d.id),marker:before.data(),recentEvents:(await db.collection('directoryRecentAdditions').count().get()).data().count}));
 }
} finally {await db.terminate();}
