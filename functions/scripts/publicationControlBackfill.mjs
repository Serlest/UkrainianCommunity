#!/usr/bin/env node
import {writeFile,mkdir} from "node:fs/promises";
import {resolve} from "node:path";
import {contentAutomationAccessToken} from "./contentAutomationCredential.mjs";
import {encode,decode} from "./publicationControlSync.mjs";
const project=process.env.UAC_FIREBASE_PROJECT_ID??"ukrainiancommunity-dbd5f",root=`projects/${project}/databases/(default)/documents`,base=`https://firestore.googleapis.com/v1/${root}`;
const apply=process.argv.includes("--apply"),output=resolve(process.env.UAC_CONTROL_BACKUP??"build/publication-control-backfill");
await mkdir(output,{recursive:true,mode:0o700});
const token=await contentAutomationAccessToken();
async function request(url,body) {
 const r=await fetch(url,{method:body?"POST":"GET",headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
 if(!r.ok){const e=Error(`HTTP ${r.status}`);e.status=r.status;throw e;}return r.json();
}
async function list(collection,fields=[]) {
 let pageToken,all=[];
 do {
  const url=new URL(base+'/'+collection);url.searchParams.set('pageSize','500');if(pageToken)url.searchParams.set('pageToken',pageToken);
  for(const f of fields)url.searchParams.append('mask.fieldPaths',f);
  const data=await request(url);all.push(...data.documents??[]);pageToken=data.nextPageToken;
 }while(pageToken);return all;
}
const value=d=>Object.fromEntries(Object.entries(d.fields??{}).map(([k,v])=>[k,decode(v)]));
const day=date=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Vienna',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
const summary={apply,indexed:0,alreadyIndexed:0,skipped:0,archivedLegacy:0,retentionUpdated:0};
for(const [kind,col] of [['news','news'],['event','events']]) {
 const rows=await list(col,['title','localizations.uk.title','localizations.de.title','createdAt','moderationStatus','federalState','regionScope']);
 await writeFile(`${output}/${col}-metadata.json`,JSON.stringify(rows));
 const candidates=rows.filter(row=>{const d=value(row);return d.moderationStatus==='approved'&&d.createdAt instanceof Date&&d.createdAt>=new Date(Date.now()-31*86400000);});
 for(let start=0;start<candidates.length;start+=5)await Promise.all(candidates.slice(start,start+5).map(async doc=>{
  const d=value(doc),id=doc.name.split('/').at(-1),data={kind,contentId:id,title:d.title??id,titleUK:d.localizations?.uk?.title??d.title??id,titleDE:d.localizations?.de?.title??d.title??id,region:d.regionScope==='austria'||d.federalState==='austria'?'austria':['burgenland','kaernten','niederoesterreich','oberoesterreich','salzburg','steiermark','tirol','vorarlberg','wien'].includes(d.federalState)?d.federalState:'unknown',firstPublicAt:d.createdAt,day:day(d.createdAt),timingSource:'legacyCreation',sourceState:d.moderationStatus,expiresAt:new Date(d.createdAt.getTime()+45*86400000),updatedAt:new Date()};
  if(!apply){summary.indexed++;return;}
  try {await request(base+':commit',{writes:[{verify:doc.name,currentDocument:{updateTime:doc.updateTime}},{update:{name:`${root}/publicationControlItems/${kind}_${id}`,fields:encode(data).mapValue.fields},currentDocument:{exists:false}}]});summary.indexed++;}
  catch(e){if([409,412].includes(e.status))summary.alreadyIndexed++;else throw e;}
 }));
}
const owners=await request(base+':runQuery',{structuredQuery:{from:[{collectionId:'users'}],where:{fieldFilter:{field:{fieldPath:'globalRole'},op:'EQUAL',value:{stringValue:'owner'}}},select:{fields:[{fieldPath:'globalRole'}]},limit:2}});
const owner=owners.filter(row=>row.document);if(owner.length!==1)throw Error('Exactly one owner required');
const uid=owner[0].document.name.split('/').at(-1),legacy=await list(`users/${uid}/contentPlanningDrafts`);
await writeFile(`${output}/legacy-planning-backup.json`,JSON.stringify(legacy),{flag:"wx",mode:0o600}).catch(error=>{if(error.code!=="EEXIST")throw error;});
for(const doc of legacy) {
 const d=value(doc);let changes={};
 if(d.state==='approved'&&!d.publishedContentId){changes={legacyState:d.state,state:'archived',archivedAt:new Date(),archiveReason:'Retired legacy planning queue; unsupported state; no automatic publication'};summary.archivedLegacy++;}
 else if(!['completed','archived'].includes(d.state)){summary.skipped++;continue;}
 if(!d.retentionExpiresAt) {
  const anchor=d.completedAt??d.archivedAt??d.updatedAt??new Date();const expiry=new Date(anchor);expiry.setUTCMonth(expiry.getUTCMonth()+6);changes.retentionExpiresAt=expiry;changes.retentionPolicy='contentPlanningReceipt6Months';summary.retentionUpdated++;
 }
 if(Object.keys(changes).length&&apply)await request(base+':commit',{writes:[{update:{name:doc.name,fields:encode(changes).mapValue.fields},updateMask:{fieldPaths:Object.keys(changes)},currentDocument:{updateTime:doc.updateTime}}]});
}
await writeFile(`${output}/summary.json`,JSON.stringify(summary,null,2));console.log(JSON.stringify(summary));
