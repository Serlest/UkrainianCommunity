import {test} from 'node:test';
import {strict as assert} from 'node:assert';
import {createControlWriter,normalizeControlReport,encode,decode,semanticDigest,readControlSchedules,synchronize} from './publicationControlSync.mjs';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const now=new Date('2026-10-27T06:00:00Z');
const report=(published=0)=>normalizeControlReport({runId:'events-v4-wien-test',region:'wien',status:'partial',completedAt:now.toISOString(),published},{kind:'event',region:'wien',mtime:now,now});
async function fixture(){
 const docs=new Map();let sequence=0,conflicts=0,commits=0;
 const root='projects/demo/databases/(default)/documents';
 const fetchImpl=async(url,options)=>{
  const path=url.split('/documents')[1];
  if(path!==':commit'){const doc=docs.get(path.slice(1));return {status:doc?200:404,ok:!!doc,json:async()=>structuredClone(doc)};}
  if(conflicts-- >0)return {status:409,ok:false};
  const writes=JSON.parse(options.body).writes;
  for(const row of writes){const key=row.update.name.slice(root.length+1),old=docs.get(key),pre=row.currentDocument;
   if(pre.exists===false&&old||pre.updateTime&&pre.updateTime!==old?.updateTime)return {status:412,ok:false};
  }
  for(const row of writes){const key=row.update.name.slice(root.length+1);docs.set(key,{...row.update,updateTime:'v'+(++sequence)});}
  commits++;return {ok:true,status:200,json:async()=>({})};
 };
 const writer=await createControlWriter({project:'demo',fetchImpl,credential:{getAccessToken:async()=>({access_token:'test'})}});
 return {writer,docs,data:path=>decode({mapValue:{fields:docs.get(path)?.fields??{}}}),seed:(path,data)=>docs.set(path,{fields:encode(data).mapValue.fields,updateTime:'v'+(++sequence)}),conflict:()=>{conflicts=1},commits:()=>commits};
}
test('legacy correction archives both versions, retries CAS, stays idempotent and never rolls back',async()=>{
 const f=await fixture(),old=report(),corrected=report(1),path='publicationControlRuns/'+old.id;
 f.seed(path,{...old,digest:'old',syncedAt:now});f.seed('publicationControlSources/event_wien',{...old,lastCompleteAt:null});f.conflict();
 assert.equal(await f.writer.write(corrected,'corrected'),true);
 assert.equal(f.data(path).published,1);assert.equal(f.data(path).revisionNumber,2);
 assert.equal(f.data(path+'/revisions/'+semanticDigest(old)).published,0);
 assert.equal(f.data(path+'/revisions/'+semanticDigest(corrected)).published,1);
 const commits=f.commits();assert.equal(await f.writer.write(corrected,'same'),false);assert.equal(f.commits(),commits);
 assert.equal(await f.writer.write(old,'old'),false);assert.equal(f.data(path).published,1);
});
test('format-only legacy upgrade preserves sync time; schedule update does not invent a new result',async()=>{
 const f=await fixture(),row=report(),path='publicationControlRuns/'+row.id;
 f.seed(path,{...row,digest:'legacy',syncedAt:now});
 assert.equal(await f.writer.write(row,'format'),false);assert.deepEqual(f.data(path).syncedAt,now);
 const changed={...row,schedule:{hours:[9,14,19],minutes:[0],timeZone:'Europe/Vienna',graceMinutes:90}};
 assert.equal(await f.writer.write(changed,'format'),false);assert.deepEqual(f.data(path).schedule,changed.schedule);assert.equal(f.data(path).revisionNumber,1);
});
test('failed attempts preserve last successful synchronization and expose the current errors',async()=>{
 const f=await fixture();await f.writer.heartbeat(2,0);const successful=f.data('publicationControlMeta/importer');
 await f.writer.heartbeat(0,3,[{detail:'failure'}]);const failed=f.data('publicationControlMeta/importer');
 assert.deepEqual(failed.lastSuccessfulCheckAt,successful.lastSuccessfulCheckAt);assert.deepEqual(failed.lastImportedAt,successful.lastImportedAt);assert.equal(failed.errors,3);assert.equal(failed.issues[0].detail,'failure');
});
test('QA artifacts are excluded; schedule changes refresh cached report metadata exactly once',async()=>{
 const base=await mkdtemp(join(tmpdir(),'uac-control-'));try{
  const real=join(base,'progress-v3/news-scopes/reports/news-test'),qa=join(base,'progress-v3/news-scopes/reports/qa-test');
  await mkdir(real,{recursive:true});await mkdir(qa,{recursive:true});
  const raw={runId:'news-test',region:'wien',status:'complete',completedAt:now.toISOString(),published:0};
  await writeFile(join(real,'wien.json'),JSON.stringify(raw));await writeFile(join(qa,'wien.json'),JSON.stringify({runId:'unsupported'}));
  let calls=0;const cache={},writer={write:async()=>{calls++;return false},heartbeat:async()=>{}};
  await synchronize({base,writer,cache,now});await synchronize({base,writer,cache,now});assert.equal(calls,1);
  const schedules={news_wien:{hours:[9],minutes:[0]}};await synchronize({base,writer,cache,now,schedules});await synchronize({base,writer,cache,now,schedules});assert.equal(calls,2);
  const automation=join(base,'uac-news-wien');await mkdir(automation);await writeFile(join(automation,'automation.toml'),'status = "ACTIVE"\nrrule = "FREQ=DAILY;BYHOUR=9,14,19;BYMINUTE=0"');
  assert.deepEqual((await readControlSchedules(base)).news_wien.hours,[9,14,19]);
 }finally{await rm(base,{recursive:true,force:true});}
});
