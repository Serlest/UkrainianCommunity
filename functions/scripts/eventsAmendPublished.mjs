#!/usr/bin/env node
// Events maintenance uses the Firestore SDK's conditional update, never create/delete or REST patch.
import {Firestore, Timestamp} from '@google-cloud/firestore';
import {OAuth2Client} from 'google-auth-library';
import {readFile, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {contentAutomationCredential} from './contentAutomationCredential.mjs';
import {EXPECTED_OWNER_ID} from './verifiedContentPublisherCore.mjs';
const base='/Users/serlest/.codex/uac-content-automation';
const allowed=new Set(['title','summary','details','localizations','startDate','endDate','occurrences','price','pricing','requiresRegistration','participationMode','externalAction','contactURL','moderationStatus']);
export const plain=v=>v?.toDate?v.toDate().toISOString():Array.isArray(v)?v.map(plain):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).sort(([a],[b])=>a.localeCompare(b)).map(([k,x])=>[k,plain(x)])):v;
export const digest=v=>createHash('sha256').update(JSON.stringify(plain(v))).digest('hex');
export function validateAmendment(before,request){
 if(!/^[a-f0-9]{40}$/.test(request.id)||before.authorId!==EXPECTED_OWNER_ID||before.sourceType!=='organization'||before.organizationId!==`uac-${before.federalState}-info`||!['tirol','wien','niederoesterreich','oberoesterreich','salzburg','vorarlberg','steiermark','kaernten','burgenland'].includes(before.federalState)||!['approved','archived'].includes(before.moderationStatus))throw Error('Existing UAC organization event required');
 if(!request.reason||!request.verificationNotes||request.verificationNotes.length<3||!request.evidence?.length||!Object.keys(request.changes??{}).length)throw Error('Reason, evidence and changes required');
 for(const k of Object.keys(request.changes))if(!allowed.has(k))throw Error('Immutable or unsupported field: '+k);
 const next={...before,...request.changes};
 for(const url of [next.contactURL,next.externalAction?.url].filter(Boolean))if(!url.startsWith('https://'))throw Error('HTTPS official/action URL required');
 if(next.moderationStatus!==before.moderationStatus&&!(before.moderationStatus==='approved'&&next.moderationStatus==='archived'))throw Error('Only archive is supported; no approval bypass');
 if(next.moderationStatus==='archived'&&!['postponement','duplicate'].includes(request.kind))throw Error('Archive needs a reviewed postponement or duplicate');
 if(request.kind==='duplicate'&&(!request.keepId||request.keepId===request.id))throw Error('Duplicate needs a distinct retained event');
 for(const l of ['uk','de'])for(const k of ['title','summary','details'])if(typeof next.localizations?.[l]?.[k]!=='string'||!next.localizations[l][k].trim())throw Error('Complete UK/DE copy required');
 for(const k of ['title','summary','details'])if(next[k]!==next.localizations.uk[k])throw Error('Root/UK mismatch: '+k);
 if(!Number.isFinite(next.price)||next.price<0)throw Error('Legacy price must remain a nonnegative number required by the event schema');
 const p=next.pricing;
 if(!p||!['unspecified','free','exact','startingFrom','range'].includes(p.kind)||p.currencyCode!=='EUR')throw Error('Supported pricing required');
 if(['exact','startingFrom','range'].includes(p.kind)&&!(Number.isFinite(p.amount)&&p.amount>=0))throw Error('Price amount required');
 if(p.kind==='range'&&!(p.maximumAmount>=p.amount))throw Error('Invalid price range');
 if(p.kind!=='unspecified'&&next.price!==(p.kind==='free'?0:p.amount))throw Error('Legacy/structured price mismatch');
 if(!['none','inAppRegistration','externalRegistration','externalTickets'].includes(next.participationMode))throw Error('Invalid participation mode');
 for(const o of next.occurrences??[]){if(!o.id||!['scheduled','cancelled'].includes(o.status)||!Number.isFinite(Date.parse(o.startDate))||Date.parse(o.endDate)<Date.parse(o.startDate))throw Error('Invalid occurrence');}
 if(next.participationMode==='none'&&next.requiresRegistration)throw Error('Closed registration cannot invite registration');
 return next;
}
export function sdkChanges(changes){
 const out=structuredClone(changes);
 for(const k of ['startDate','endDate'])if(k in out)out[k]=Timestamp.fromDate(new Date(out[k]));
 if(out.occurrences)out.occurrences=out.occurrences.map(o=>({...o,startDate:Timestamp.fromDate(new Date(o.startDate)),endDate:Timestamp.fromDate(new Date(o.endDate))}));
 out.updatedAt=Timestamp.now();return out;
}
async function ownedLock(config){
 if(!config.runId?.startsWith('events-v4-'))throw Error('Events-owned publication mutex required');
 const lock=JSON.parse(await readFile(base+'/content-publish.lock/owner.json','utf8'));
 if(lock.runId!==config.runId||lock.threadId!==config.threadId||lock.generation!==config.generation||Date.parse(lock.expiresAt)<=Date.now())throw Error('Unexpired owned publication mutex required');
}
export async function amendPublishedEvent(config,{apply=false,db,checkLocks=ownedLock}={}){
 const request=JSON.parse(await readFile(config.requestPath,'utf8'));
 for(const path of request.evidence){const bytes=await readFile(path);if(!bytes.length)throw Error('Empty source evidence');}
 const ref=db.doc('events/'+request.id);const snapshot=await ref.get();if(!snapshot.exists)throw Error('Event missing; amendment never creates');
 const before=plain(snapshot.data());
 if(!config.baselinePath)throw Error('Reviewed exact-ID baseline path required');
 {const baseline=JSON.parse(await readFile(config.baselinePath,'utf8'));if(digest(baseline.data)!==digest(before))throw Error('Reviewed baseline changed');}
 validateAmendment(before,request);
 const evidenceHashes=await Promise.all(request.evidence.map(async path=>({path,sha256:createHash('sha256').update(await readFile(path)).digest('hex')})));
 if(request.kind==='duplicate'){const keep=await db.doc('events/'+request.keepId).get();if(!keep.exists||keep.get('moderationStatus')!=='approved'||keep.get('organizationId')!==before.organizationId||digest(plain(keep.get('occurrences')).map(o=>o.startDate).sort())!==digest(before.occurrences.map(o=>o.startDate).sort()))throw Error('Retained approved event required');}
 const plan={version:1,id:request.id,requestHash:digest(request),beforeHash:digest(before),before,changes:request.changes,evidenceHashes,plannedAt:new Date().toISOString(),reason:request.reason};
 if(!apply){await writeFile(config.planPath,JSON.stringify(plan,null,2),{flag:'wx'});return {dryRun:true,id:request.id,fields:Object.keys(request.changes)};}
 const saved=JSON.parse(await readFile(config.planPath,'utf8'));
 if(saved.requestHash!==plan.requestHash||saved.beforeHash!==plan.beforeHash||digest(saved.evidenceHashes)!==digest(evidenceHashes))throw Error('Plan, baseline or evidence changed; review again');
 if(Date.now()-Date.parse(saved.plannedAt)>600000)throw Error('Dry run older than ten minutes');
 await checkLocks(config);
 const changes=sdkChanges(request.changes);
 // SDK precondition preserves concurrent edits, counters and registrations; no retry/recreate.
 await ref.update(changes,{lastUpdateTime:snapshot.updateTime});
 const after=await ref.get();const actual=plain(after.data());
 for(const [k,v]of Object.entries(request.changes))if(digest(actual[k])!==digest(v))throw Error('Read-back mismatch: '+k);
 for(const k of Object.keys(before))if(!(k in changes)&&digest(actual[k])!==digest(before[k]))throw Error('Concurrent read-back change: '+k);
 const receipt={id:request.id,updated:true,allVerified:true,checkedAt:new Date().toISOString(),beforeHash:saved.beforeHash,afterHash:digest(actual),fields:Object.keys(request.changes),after:actual,evidenceHashes,reason:request.reason};
 await writeFile(config.receiptPath,JSON.stringify(receipt,null,2),{flag:'wx'});return {id:request.id,updated:true,allVerified:true};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const config=JSON.parse(await readFile(process.argv[2],'utf8'));const credential=await contentAutomationCredential();const client=new OAuth2Client();client.setCredentials({access_token:(await credential.getAccessToken()).access_token});const db=new Firestore({projectId:'ukrainiancommunity-dbd5f',authClient:client});
 try{console.log(JSON.stringify(await amendPublishedEvent(config,{apply:process.argv.includes('--apply'),db})));}finally{await db.terminate();}
}
