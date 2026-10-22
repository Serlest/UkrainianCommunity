import {strict as assert} from 'node:assert';
import {test} from 'node:test';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {normalizeControlReport,synchronize,encode,decode} from './publicationControlSync.mjs';
const now=new Date('2026-10-22T14:00:00Z');
test('normalization preserves unknown counts, partial coverage, timestamp evidence and no local paths',()=>{
 const report=normalizeControlReport({runId:'news-2026-10-22T14',scope:'wien',status:'complete',coverageErrors:[{explanation:'HTTP 403 /Users/test/private/evidence.json Bearer SECRET'}]},{kind:'news',region:'wien',mtime:now,now});
 assert.equal(report.status,'partial');assert.equal(report.published,null);assert.equal(report.timestampBasis,'reportFileModifiedAt');assert.ok(!report.issues[0].detail.includes('SECRET'));assert.ok(!report.issues[0].detail.includes('/Users/'));assert.equal(report.issues[0].code,'restrictedSource');
 assert.throws(()=>normalizeControlReport({runId:'news-x',scope:'tirol'},{kind:'news',region:'wien',mtime:now,now}));
});
test('events report counts and continuations remain distinct, missing status is unknown',()=>{
 const report={runId:'events-v4-wien-2026-10-22-scan',region:'wien',completedAt:now.toISOString(),sourceMetrics:{publishedCount:3,sourcesAttempted:2},newPublications:[{contentId:'a'},{contentId:'b'},{contentId:'c'}]};
 const first=normalizeControlReport(report,{kind:'event',region:'wien',mtime:now,now});
 assert.equal(first.status,'unknown');assert.equal(first.published,3);assert.equal(first.sourcesChecked,2);assert.equal(first.timestampBasis,'reportCompletedAt');
 const next=normalizeControlReport({...report,runId:report.runId+'-publish-continuation-1',publicationOnly:true},{kind:'event',region:'wien',mtime:now,now});assert.notEqual(first.id,next.id);assert.equal(next.publicationOnly,true);
 assert.deepEqual(decode(encode({date:now,values:[1,null,true]})),{date:now,values:[1,null,true]});
});
test('sync discovers both real report paths, persists only successes and retries failed writes',async()=>{
 const base=await mkdtemp(join(tmpdir(),'publication-control-'));const cache={};let writes=0,fail=true;
 try {
  const news=join(base,'progress-v3/news-scopes/reports/news-2026-10-22T14');const events=join(base,'artifacts/events-wien/runs/events-v4-wien-2026-10-22-scan');
  await mkdir(news,{recursive:true});await mkdir(events,{recursive:true});
  await writeFile(join(news,'wien.json'),JSON.stringify({runId:'news-2026-10-22T14',scope:'wien',status:'partial',completedAt:now.toISOString(),published:0}));
  await writeFile(join(events,'report.json'),JSON.stringify({runId:'events-v4-wien-2026-10-22-scan',region:'wien',status:'complete',completedAt:now.toISOString(),newPublications:[]}));
  const writer={write:async row=>{if(fail&&row.kind==='news')throw Error('network');writes++;return true;},heartbeat:async()=>{}};
  const first=await synchronize({base,writer,cache,now});assert.equal(first.errors,1);assert.equal(first.imported,1);
  fail=false;const next=await synchronize({base,writer,cache,now});assert.equal(next.imported,1);assert.equal(next.errors,0);assert.equal(writes,2);
  assert.equal((await synchronize({base,writer,cache,now})).imported,0);
 } finally {await rm(base,{recursive:true,force:true});}
});

test('malformed historical report time is explicitly flagged without changing its source',()=>{
 const raw={runId:'events-v4-wien-2026-10-22-scan',region:'wien',status:'complete',completedAt:'2026-10-18T09:44:38 UTC:00Z'};
 const result=normalizeControlReport(raw,{kind:'event',region:'wien',mtime:now,now});assert.equal(result.timestampBasis,'reportFileModifiedAt');assert.equal(result.status,'partial');assert.equal(result.issues[0].code,'invalidReportTime');assert.equal(raw.completedAt,'2026-10-18T09:44:38 UTC:00Z');
});
