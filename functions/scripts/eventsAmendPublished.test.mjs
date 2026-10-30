import test from 'node:test';import assert from 'node:assert/strict';import {validateAmendment,sdkChanges,digest} from './eventsAmendPublished.mjs';import {EXPECTED_OWNER_ID} from './verifiedContentPublisherCore.mjs';
const copy={title:'Тест',summary:'Зміст',details:'Перевірений опис'};
const before={authorId:EXPECTED_OWNER_ID,sourceType:'organization',organizationId:'uac-tirol-info',federalState:'tirol',moderationStatus:'approved',...copy,localizations:{uk:copy,de:{title:'Test',summary:'Inhalt',details:'Beschreibung'}},price:0,pricing:{kind:'unspecified',currencyCode:'EUR'},participationMode:'none',requiresRegistration:false,occurrences:[]};
const req=()=>({id:'a'.repeat(40),reason:'Official correction',evidence:['source.html'],verificationNotes:['source facts','bilingual check','readback'],changes:{price:25,pricing:{kind:'exact',amount:25,currencyCode:'EUR'}}});
test('known structured price and legacy price agree',()=>{assert.equal(validateAmendment(before,req()).price,25);let r=req();r.changes.price=0;assert.throws(()=>validateAmendment(before,r),/mismatch/)});
test('identity, counters, region and media cannot change',()=>{for(const k of ['authorId','organizationId','imageURL','federalState','viewCount','id']){let r=req();r.changes[k]='changed';assert.throws(()=>validateAmendment(before,r),/Immutable/)}});
test('archive never silently approves, cancels or recreates',()=>{let r=req();r.changes={moderationStatus:'archived'};assert.throws(()=>validateAmendment(before,r),/reviewed/);r.kind='postponement';assert.equal(validateAmendment(before,r).moderationStatus,'archived');r.kind='duplicate';assert.throws(()=>validateAmendment(before,r),/retained/);r.keepId='b'.repeat(40);assert.equal(validateAmendment(before,r).moderationStatus,'archived')});
test('timestamp roundtrip, root bilingual equivalence and no mutable shared objects',()=>{let x={occurrences:[{id:'x',startDate:'2026-10-25T09:00:00.000Z',endDate:'2026-10-25T09:00:00.000Z',status:'scheduled'}]};let y=sdkChanges(x);assert.equal(digest(x.occurrences),digest(y.occurrences));assert.equal(typeof x.occurrences[0].startDate,'string');let r=req();r.changes.title='different';assert.throws(()=>validateAmendment(before,r),/Root/)});
test('matching root and UK fields cannot introduce an untranslated event body',()=>{
 const english='KLANGherbst presents Philipp Hochmair reciting Joseph von Eichendorff, accompanied by the Sonare Linz string quartet.';
 for(const field of ['summary','details']){
  const r=req();r.changes[field]=english;
  r.changes.localizations={...before.localizations,uk:{...copy,[field]:english}};
  assert.throws(()=>validateAmendment(before,r),new RegExp('Ukrainian '+field+' contains no Cyrillic'));
 }
 const r=req();r.changes.details='На концерті KLANGherbst Філіп Гохмайр декламує твір Йозефа фон Айхендорфа в супроводі струнного квартету Sonare Linz.';
 r.changes.localizations={...before.localizations,uk:{...copy,details:r.changes.details}};
 assert.equal(validateAmendment(before,r).details,r.changes.details);
});
test('language guard does not prevent archiving unchanged legacy English copy',()=>{
 const details='A legacy event description in English that must still be removable without inventing a new translation or changing its original evidence.';
 const legacy={...before,details,localizations:{...before.localizations,uk:{...copy,details}}};
 const r=req();r.kind='postponement';r.changes={moderationStatus:'archived'};
 assert.equal(validateAmendment(legacy,r).moderationStatus,'archived');
});
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {amendPublishedEvent,plain} from './eventsAmendPublished.mjs';
test('dry-run never writes; apply is conditional and verifies same ID; changed baseline stops reuse',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'uac-event-amend-'));let data=structuredClone(before),writes=0,revision={revision:1};
 const ref={get:async()=>({exists:true,data:()=>data,updateTime:revision}),update:async(changes,condition)=>{assert.equal(condition.lastUpdateTime,revision);writes++;data={...data,...changes};}};
 const db={doc:path=>{assert.equal(path,'events/'+'a'.repeat(40));return ref;}};
 try{const request=req();request.evidence=[join(dir,'official.txt')];await writeFile(request.evidence[0],'Reviewed official facts');const c={requestPath:join(dir,'request.json'),baselinePath:join(dir,'before.json'),planPath:join(dir,'plan.json'),receiptPath:join(dir,'receipt.json')};await writeFile(c.requestPath,JSON.stringify(request));await writeFile(c.baselinePath,JSON.stringify({data}));await amendPublishedEvent(c,{db});assert.equal(writes,0);await amendPublishedEvent(c,{db,apply:true,checkLocks:async()=>{}});assert.equal(writes,1);assert.equal(JSON.parse(await readFile(c.receiptPath)).allVerified,true);assert.equal(plain(data).price,25);await assert.rejects(amendPublishedEvent(c,{db,apply:true,checkLocks:async()=>{}}),/baseline changed/);assert.equal(writes,1);
 }finally{await rm(dir,{recursive:true,force:true})}
});
test('missing document never creates and SDK timestamp codec retains cancelled status',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'uac-event-missing-'));
 try{const request=req();request.evidence=[join(dir,'official.txt')];await writeFile(request.evidence[0],'Official evidence');const requestPath=join(dir,'request.json');await writeFile(requestPath,JSON.stringify(request));await assert.rejects(amendPublishedEvent({requestPath,baselinePath:'unused'},{db:{doc:()=>({get:async()=>({exists:false}),update:()=>assert.fail('Missing document must never be written')})}}),/Event missing/);
 const result=sdkChanges({occurrences:[{id:'cancelled-slot',startDate:'2026-10-16T14:00:00.000Z',endDate:'2026-10-16T14:45:00.000Z',status:'cancelled'}]});assert.equal(result.occurrences[0].status,'cancelled');assert.equal(result.occurrences[0].startDate.toDate().toISOString(),'2026-10-16T14:00:00.000Z');
 }finally{await rm(dir,{recursive:true,force:true})}
});

import {retainedSeriesCoversDuplicate} from './eventsAmendPublished.mjs';
test('duplicate archive retains a broader series and refuses unique or partial-overlap sessions',()=>{
 const occurrence=startDate=>({startDate,status:'scheduled'});const common={moderationStatus:'approved',organizationId:'uac-burgenland-info',federalState:'burgenland'};
 const before={...common,occurrences:[occurrence('2026-10-28T09:00:00.000Z')]};const kept={...common,occurrences:[occurrence('2026-10-11T12:00:00.000Z'),...before.occurrences]};
 assert.equal(retainedSeriesCoversDuplicate(before,kept),true);
 assert.equal(retainedSeriesCoversDuplicate({...before,occurrences:[...before.occurrences,occurrence('2026-10-29T09:00:00.000Z')]},kept),false);
 assert.equal(retainedSeriesCoversDuplicate(before,{...kept,moderationStatus:'archived'}),false);
 assert.equal(retainedSeriesCoversDuplicate(before,{...kept,organizationId:'other'}),false);
});
