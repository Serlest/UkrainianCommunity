import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {auditNewsWave} from './newsWaveAudit.mjs';
test('wave audit uses archived policy and distinguishes missing reports, evidence limits and historical receipts without mutation',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-'));const run='news-2026-10-17T14';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  const snapshot=JSON.stringify([{sourceId:'one',sourcePolicyVersion:3,links:[{url:'https://example.at/story'}],error:null}]);
  await writeFile(join(root,`snapshots/${run}.json`),snapshot);
  await writeFile(join(root,'source-policies/v3.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  await writeFile(join(root,'source-registry.json'),JSON.stringify({sources:[{sourceId:'new',active:true},{sourceId:'other',active:true}]}));
  await writeFile(join(root,`reports/${run}/wien.json`),JSON.stringify({status:'complete',sourceErrors:[]}));
  const receipt=join(root,'receipt.json');await writeFile(receipt,JSON.stringify({contentId:'published',allVerified:true}));
  await writeFile(join(root,'scopes/wien.json'),JSON.stringify({lastCandidateBatch:{runId:run,candidates:2},candidateDecisions:{a:{runId:run,outcome:'published',contentId:'published',manifestPath:'/manifest.json',editorialReceiptPath:'/editorial.json',readbackReceiptPath:receipt},b:{runId:run,outcome:'rejected',reason:'unverified'}}}));
  const result=await auditNewsWave(root,run);
  assert.equal(result.snapshot.expectedSources,1);assert.equal(result.completedReports,1);
  assert.equal(result.scopes.filter(x=>x.reportMissing).length,9);
  assert.equal(result.scopes[0].evidenceLimits.unverifiedCandidates,1);
  assert.equal(result.scopes[0].publications[0].verifiedReceipt,true);
  assert.equal(result.scopes[0].publications[0].manifestPath,'/manifest.json');
  assert.equal(result.scopes[0].publications[0].editorialReceiptPath,'/editorial.json');
  assert.equal(await readFile(join(root,`snapshots/${run}.json`),'utf8'),snapshot);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit falls back to immutable closed-report counts after scope checkpoint advances',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-history-'));const run='news-2026-10-17T19';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const entries=[
   {url:'a',outcome:'published',contentId:'a'},
   {url:'b',outcome:'published',contentId:'b'},
   {url:'c',outcome:'rejected',reason:'unverified'},
   {url:'d',outcome:'rejected',reason:'unverified'},
  ];
  await writeFile(join(root,`reports/${run}/austria.json`),JSON.stringify({status:'partial',candidateDecisionsComplete:true,decidedCandidates:4,published:2,rejected:2,openedArticles:entries}));
  const receiptA=join(root,'receipt-a.json'),receiptB=join(root,'receipt-b.json');
  await writeFile(receiptA,JSON.stringify({contentId:'a',allVerified:true}));await writeFile(receiptB,JSON.stringify({contentId:'b',allVerified:true}));
  await writeFile(join(root,'scopes/austria.json'),JSON.stringify({lastCandidateBatch:{runId:'news-2026-10-17T22',candidateDecisionsComplete:true,candidates:5,published:0,rejected:5},candidateDecisions:{a:{runId:run,outcome:'published',contentId:'a',readbackReceiptPath:receiptA},b:{runId:run,outcome:'published',contentId:'b',readbackReceiptPath:receiptB},c:{runId:run,outcome:'rejected',reason:'unverified'},d:{runId:'news-2026-10-17T22',outcome:'rejected',reason:'duplicate'}}}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='austria');
  assert.equal(scope.batch.candidates,4);assert.equal(scope.batch.published,2);assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.retainedDecisionsForWave,3);assert.equal(scope.decisionLedger.retainedDecisionCountMatches,false);
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');assert.equal(scope.rejectionReasons.unverified,2);
  assert.equal(scope.publications.length,2);assert.ok(scope.publications.every(x=>x.verifiedReceipt));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit reports a published closed-report entry without a content ID instead of crashing',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-missing-id-'));const run='news-2026-10-18T19';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  await writeFile(join(root,`reports/${run}/niederoesterreich.json`),JSON.stringify({
   status:'partial',candidateDecisionsComplete:true,decidedCandidates:1,published:1,rejected:0,
   openedArticles:[{url:'https://example.at/story',outcome:'published'}],
  }));
  await writeFile(join(root,'scopes/niederoesterreich.json'),JSON.stringify({candidateDecisions:{}}));
  const result=await auditNewsWave(root,run);
  const scope=result.scopes.find(x=>x.scope==='niederoesterreich');
  assert.equal(scope.publications.length,1);
  assert.equal(scope.publications[0].contentId,undefined);
  assert.equal(scope.publications[0].verifiedReceipt,false);
  assert.match(scope.publications[0].error,/path|argument/i);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit derives closure from Salzburg report decisions after emergency replaces the scope checkpoint',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-salzburg-'));const run='news-2026-10-24T09';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const decisions=[
   {url:'wrong-scope',outcome:'rejected',reason:'wrong_scope'},
   {url:'unverified',outcome:'rejected',reason:'unverified'},
   {url:'published-a',outcome:'published',contentId:'a',manifestPath:'/a.json'},
   {url:'unverified-b',outcome:'rejected',reason:'unverified'},
   {url:'published-b',outcome:'published',contentId:'b',manifestPath:'/b.json'},
  ];
  await writeFile(join(root,`reports/${run}/salzburg.json`),JSON.stringify({
   status:'partial',workflowComplete:true,decisions,
   openedArticles:[{url:'published-a',decision:{outcome:'published'}},{url:'published-b',decision:{outcome:'published'}}],
  }));
  const receiptA=join(root,'receipt-a.json'),receiptB=join(root,'receipt-b.json');
  await writeFile(receiptA,JSON.stringify({contentId:'a',allVerified:true}));
  await writeFile(receiptB,JSON.stringify({contentId:'b',allVerified:true}));
  const candidateDecisions=Object.fromEntries(decisions.map((entry)=>[entry.url,{
   ...entry,runId:run,readbackReceiptPath:entry.contentId==='a'?receiptA:entry.contentId==='b'?receiptB:undefined,
  }]));
  await writeFile(join(root,'scopes/salzburg.json'),JSON.stringify({
   lastCandidateBatch:{runId:'emergency-2026-10-24T10-00',candidateDecisionsComplete:true,candidates:1,published:1,rejected:0},
   candidateDecisions,
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='salzburg');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:5,published:2,rejected:3});
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.equal(scope.decisionLedger.retainedDecisionCountMatches,true);
  assert.equal(scope.rejectionReasons.unverified,2);
  assert.equal(scope.publications.length,2);
  assert.ok(scope.publications.every(x=>x.verifiedReceipt));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit prefers closed decisions and follows nested production read-back paths',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-nested-readback-'));const run='news-2026-10-24T18';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const receipt=join(root,'production-readback.json');
  await writeFile(receipt,JSON.stringify({contentId:'published-id',allVerified:true}));
  const decisions=[
   {url:'https://example.at/story',outcome:'published',contentId:'published-id',manifestPath:'/manifest.json',editorialReceiptPath:'/editorial.json',productionReadback:{verified:true,contentId:'published-id',receiptPath:receipt}},
   {url:'https://example.at/limited',outcome:'rejected',reason:'unverified'},
  ];
  await writeFile(join(root,`reports/${run}/steiermark.json`),JSON.stringify({
   status:'partial',workflowComplete:true,decisions,
   openedArticles:[{url:'https://example.at/story',outcome:'published'},{url:'https://example.at/limited',outcome:'rejected',reason:'unverified'}],
  }));
  await writeFile(join(root,'scopes/steiermark.json'),JSON.stringify({
   lastCandidateBatch:{runId:'emergency-2026-10-24T18-00',candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},
   candidateDecisions:{},
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='steiermark');
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.equal(scope.decisionLedger.reportedCandidates,2);
  assert.equal(scope.publications[0].contentId,'published-id');
  assert.equal(scope.publications[0].receiptPath,receipt);
  assert.equal(scope.publications[0].verifiedReceipt,true);
  assert.equal(scope.publications[0].manifestPath,'/manifest.json');
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit recognizes candidateBatchClosed reports with nested opened-article decisions',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-closed-batch-'));const run='news-2026-10-28T15';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const openedArticles=[
   {url:'https://example.at/limited-a',decision:{url:'https://example.at/limited-a',outcome:'rejected',reason:'unverified'}},
   {url:'https://example.at/limited-b',decision:{url:'https://example.at/limited-b',outcome:'rejected',reason:'unverified'}},
  ];
  await writeFile(join(root,`reports/${run}/kaernten.json`),JSON.stringify({
   status:'partial',candidateBatchClosed:true,decidedCandidates:2,published:0,rejected:2,openedArticles,
  }));
  await writeFile(join(root,'scopes/kaernten.json'),JSON.stringify({
   lastCandidateBatch:{runId:'news-2026-10-28T16',candidateDecisionsComplete:true,candidates:1,published:1,rejected:0},
   candidateDecisions:{},
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='kaernten');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.equal(scope.decisionLedger.retainedDecisionCountMatches,false);
  assert.equal(scope.rejectionReasons.unverified,2);
  assert.equal(scope.publications.length,0);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit derives counts from decidedCandidates after the scope checkpoint advances',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-decided-candidates-'));const run='news-2026-10-28T15';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const receipt=join(root,'production-readback.json');
  await writeFile(receipt,JSON.stringify({contentId:'published-id',allVerified:true}));
  const decidedCandidates=[
   {url:'https://example.at/a',outcome:'rejected',reason:'unverified'},
   {url:'https://example.at/b',outcome:'published',contentId:'published-id',productionReadback:{verified:true,contentId:'published-id',receiptPath:receipt}},
   {url:'https://example.at/c',outcome:'rejected',reason:'no_practical_effect'},
  ];
  await writeFile(join(root,`reports/${run}/burgenland.json`),JSON.stringify({status:'partial',decidedCandidates}));
  await writeFile(join(root,'scopes/burgenland.json'),JSON.stringify({
   lastCandidateBatch:{runId:'news-2026-10-28T16',candidateDecisionsComplete:true,candidates:1,published:1,rejected:0},candidateDecisions:{},
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='burgenland');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:3,published:1,rejected:2});
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.equal(scope.rejectionReasons.unverified,1);
  assert.equal(scope.rejectionReasons.no_practical_effect,1);
  assert.equal(scope.publications.length,1);
  assert.equal(scope.publications[0].verifiedReceipt,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit recovers terminal closure from a matching candidate-batch and receipt after a later pass replaces scope state',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-closed-artifact-'));const run='news-2026-11-01T19';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`,`artifacts/${run}/wien`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const productionReceipt=join(root,'production-readback.json');
  await writeFile(productionReceipt,JSON.stringify({contentId:'published-id',allVerified:true}));
  const decisions=[
   {url:'https://example.at/story',outcome:'published',contentId:'published-id'},
   {url:'https://example.at/limited',outcome:'rejected',reason:'unverified'},
  ];
  await writeFile(join(root,`reports/${run}/wien.json`),JSON.stringify({
   status:'partial',runId:run,decidedCandidates:2,published:1,rejected:1,
  }));
  await writeFile(join(root,`artifacts/${run}/wien/candidate-batch.json`),JSON.stringify({
   scope:'wien',runId:run,candidates:decisions.map(({url})=>({url})),decisions,
  }));
  await writeFile(join(root,`artifacts/${run}/wien/decision-receipt.json`),JSON.stringify({
   runId:run,candidateDecisionsComplete:true,candidates:2,published:1,rejected:1,
  }));
  await writeFile(join(root,'scopes/wien.json'),JSON.stringify({
   lastCandidateBatch:{runId:'emergency-2026-11-01T20-00',candidateDecisionsComplete:true,candidates:1,published:1,rejected:0},
   candidateDecisions:{'https://example.at/story':{runId:run,outcome:'published',contentId:'published-id',manifestPath:'/manifest.json',editorialReceiptPath:'/editorial.json',readbackReceiptPath:productionReceipt}},
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='wien');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:1,rejected:1});
  assert.equal(scope.batchSource,'closed_artifact');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_artifact');
  assert.equal(scope.rejectionReasons.unverified,1);
  assert.equal(scope.publications.length,1);
  assert.equal(scope.publications[0].verifiedReceipt,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit reconciles preserved publications even when a later decision is stale',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-tirol-'));const run='news-2026-11-01T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const candidates=[{url:'https://example.at/a#ref=rss'},{url:'https://example.at/b'}];
  const decisions=[
   {url:candidates[0].url,outcome:'rejected',reason:'stale'},
   {url:candidates[1].url,outcome:'rejected',reason:'unverified'},
  ];
  await writeFile(join(root,`reports/${run}/tirol.json`),JSON.stringify({
   scope:'tirol',runId:run,status:'partial',completedAt:'2026-11-01T21:30:00Z',
   candidates,decisions,locksReleased:true,draftsCreated:0,queueCreated:false,
  }));
  await writeFile(join(root,'scopes/tirol.json'),JSON.stringify({
   lastCandidateBatch:{runId:'emergency-2026-11-01T21-30',candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},
   candidateDecisions:{[candidates[0].url]:{runId:'news-2026-11-01T19',outcome:'published',contentId:'historical-publication'},
    [candidates[1].url]:{runId:run,outcome:'rejected',reason:'unverified'}},
  }));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='tirol');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.equal(scope.decisionLedger.retainedDecisionCountMatches,false);
  assert.equal(scope.decisionLedger.preservedEarlierPublishedDecisions,1);
  assert.equal(scope.decisionLedger.retainedDecisionCountReconciled,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit recognizes Salzburg closedAt and releaseArtifact closure evidence',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-salzburg-closed-'));const run='news-2026-11-01T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`,'artifacts/salzburg'])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const batchPath=join(root,'artifacts/salzburg/decisions.json'),releasePath=join(root,'artifacts/salzburg/lock-release.json');
  const decisions=[{url:'https://example.at/old',outcome:'rejected',reason:'duplicate',contentId:'old'},
   {url:'https://example.at/new',outcome:'rejected',reason:'unverified'}];
  await writeFile(batchPath,JSON.stringify({scope:'salzburg',runId:run,candidates:2,decisions}));
  await writeFile(releasePath,JSON.stringify({released:true}));
  await writeFile(join(root,`reports/${run}/salzburg.json`),JSON.stringify({scope:'salzburg',runId:run,status:'partial',closedAt:'2026-11-01T21:40:00Z',decidedCandidates:2,artifacts:join(root,'artifacts/salzburg'),locks:{releaseArtifact:releasePath}}));
  await writeFile(join(root,'scopes/salzburg.json'),JSON.stringify({lastCandidateBatch:{runId:'emergency-2026-11-01T22-00',candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},candidateDecisions:{
   'https://example.at/old':{runId:'news-2026-11-01T19',outcome:'published',contentId:'old'},
   'https://example.at/new':{runId:run,outcome:'rejected',reason:'unverified'},
  }}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='salzburg');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_artifact');
  assert.equal(scope.decisionLedger.preservedEarlierPublishedDecisions,1);
  assert.equal(scope.decisionLedger.retainedDecisionCountReconciled,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit follows an external report artifact directory and its decision receipt',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-external-'));const external=await mkdtemp(join(tmpdir(),'news-wave-artifacts-'));const run='news-2026-11-01T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const entries=[{url:'a',outcome:'rejected',reason:'unverified'},{url:'b',outcome:'rejected',reason:'duplicate'}];
  await writeFile(join(external,'decision-batch.json'),JSON.stringify({scope:'oberoesterreich',runId:run,candidates:2,decisions:entries}));
  await writeFile(join(external,'decision-receipt.json'),JSON.stringify({runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2}));
  await writeFile(join(root,`reports/${run}/oberoesterreich.json`),JSON.stringify({scope:'oberoesterreich',runId:run,status:'partial',reportedAt:'2026-11-01T21:35:00Z',decidedCandidates:2,locksReleased:true,artifacts:external}));
  await writeFile(join(root,'scopes/oberoesterreich.json'),JSON.stringify({lastCandidateBatch:{runId:'emergency-2026-11-02T00-00',candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},candidateDecisions:{}}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='oberoesterreich');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_artifact');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_artifact');
  assert.equal(scope.rejectionReasons.unverified,1);
 }finally{await rm(root,{recursive:true,force:true});await rm(external,{recursive:true,force:true});}
});

test('wave audit recovers a closed report-referenced decisions file after checkpoint advance',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-batch-path-'));const run='news-2026-11-01T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`,'artifacts/wave/salzburg'])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const batchPath=join(root,'artifacts/wave/salzburg/decisions.json'),releasePath=join(root,'artifacts/wave/salzburg/lock-release.json');
  const decisions=[{url:'https://example.at/duplicate',outcome:'rejected',reason:'duplicate',contentId:'old'},
   {url:'https://example.at/new',outcome:'rejected',reason:'unverified'}];
  await writeFile(batchPath,JSON.stringify({scope:'salzburg',runId:run,candidates:2,decisions}));
  await writeFile(releasePath,JSON.stringify({released:true}));
  await writeFile(join(root,`reports/${run}/salzburg.json`),JSON.stringify({scope:'salzburg',runId:run,status:'partial',completedAt:'2026-11-01T21:40:00Z',decidedCandidates:2,batchPath,locks:{releasePath}}));
  await writeFile(join(root,'scopes/salzburg.json'),JSON.stringify({lastCandidateBatch:{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2},candidateDecisions:{
   'https://example.at/duplicate/':{runId:'news-2026-11-01T19',outcome:'published',contentId:'old'},
   'https://example.at/new':{runId:run,outcome:'rejected',reason:'unverified'},
  }}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='salzburg');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_artifact');
  assert.equal(scope.decisionLedger.preservedEarlierPublishedDecisions,1);
  assert.equal(scope.decisionLedger.retainedDecisionCountReconciled,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit reads closed Austria batch after the report points to released lock evidence',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-austria-artifact-'));const run='news-2026-11-01T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`,`artifacts/${run}/austria`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const receipt=join(root,'production-readback.json');await writeFile(receipt,JSON.stringify({contentId:'pub',allVerified:true}));
  const entries=[{url:'https://example.at/published',outcome:'published',contentId:'pub',productionReadback:{verified:true,contentId:'pub',receiptPath:receipt}},
   {url:'https://example.at/a',outcome:'rejected',reason:'unverified'}];
  await writeFile(join(root,`artifacts/${run}/austria/candidate-batch.json`),JSON.stringify({scope:'austria',runId:run,candidates:entries.map(x=>({url:x.url})),decisions:entries}));
  const releasePath=join(root,`artifacts/${run}/austria/lock-release.json`);await writeFile(releasePath,JSON.stringify({released:true}));
  await writeFile(join(root,`reports/${run}/austria.json`),JSON.stringify({scope:'austria',runId:run,status:'partial',completedAt:'2026-11-01T20:21:00Z',locks:{release:releasePath},publications:[{contentId:'pub'}]}));
  await writeFile(join(root,'scopes/austria.json'),JSON.stringify({lastCandidateBatch:{runId:'news-2026-11-01T22',candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},candidateDecisions:{
   'https://example.at/a':{runId:'news-2026-11-01T21',outcome:'rejected',reason:'unverified'},
   'https://example.at/published':{runId:'news-2026-11-01T22',outcome:'rejected',reason:'duplicate',decidedAt:'2026-11-01T21:47:00Z'},
  }}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='austria');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:1,rejected:1});
  assert.equal(scope.batchSource,'closed_artifact');
  assert.equal(scope.publications[0].verifiedReceipt,true);
  assert.equal(scope.decisionLedger.supersededByLaterRun,1);
  assert.equal(scope.decisionLedger.retainedDecisionCountReconciled,true);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit flags no-practical-effect decisions without a matching direct article read',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-relevance-evidence-'));const run='news-2026-11-04T19';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const decisions=[
   {url:'https://www.meinbezirk.at/unread-lead',outcome:'rejected',reason:'no_practical_effect'},
   {url:'https://www.meinbezirk.at/steyr-steyr-land/c-gesundheit/fachkompetente-hoerakustik-wenn-wege-zu-schwer-werden_a8994378',outcome:'rejected',reason:'no_practical_effect',
    routineLowRelevanceTriage:'clear_routine_award_or_event',ongoingPracticalImpactSignal:false},
   {url:'https://orf.at/read-article',outcome:'rejected',reason:'no_practical_effect'},
   {url:'https://orf.at/routine-award',outcome:'rejected',reason:'no_practical_effect',
    routineLowRelevanceTriage:'clear_routine_award_or_event',ongoingPracticalImpactSignal:false},
  ];
  await writeFile(join(root,`reports/${run}/oberoesterreich.json`),JSON.stringify({
   status:'partial',candidateDecisionsComplete:true,decidedCandidates:4,published:0,rejected:4,
   decisions,openedArticles:[{url:'https://orf.at/read-article',evidencePath:'/article-read.json'}],
  }));
  await writeFile(join(root,'scopes/oberoesterreich.json'),JSON.stringify({candidateDecisions:{}}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='oberoesterreich');
  assert.equal(scope.editorialReviewFlags.length,2);
  assert.equal(scope.editorialReviewFlags[0].url,'https://www.meinbezirk.at/unread-lead');
  assert.equal(scope.editorialReviewFlags[0].suggestedClassification,'unverified');
  assert.equal(scope.editorialReviewFlags[1].url,'https://www.meinbezirk.at/steyr-steyr-land/c-gesundheit/fachkompetente-hoerakustik-wenn-wege-zu-schwer-werden_a8994378');
  assert.match(scope.editorialReviewFlags[1].note,/potentially practical topic/);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit follows a decision completion amendment to the corrected terminal batch',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-decision-amendment-'));const run='news-2026-11-05T09';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const url='https://orf.at/fully-read';
  const oldDecision={url,outcome:'rejected',reason:'no_practical_effect'};
  await writeFile(join(root,`reports/${run}/kaernten.json`),JSON.stringify({
   scope:'kaernten',runId:run,status:'partial',closedAt:'2026-11-05T08:41:03Z',
   candidateDecisionsComplete:true,decidedCandidates:1,published:0,rejected:1,decisions:[oldDecision],
  }));
  const batchPath=join(root,'corrected-decision-batch.json');
  const correctedDecision={url,outcome:'rejected',reason:'unverified',primaryOpened:true,primaryFullTextVerified:true};
  await writeFile(batchPath,JSON.stringify({scope:'kaernten',runId:run,candidates:1,decisions:[correctedDecision]}));
  await writeFile(join(root,`reports/${run}/kaernten-decision-completion-amendment.json`),JSON.stringify({
   scope:'kaernten',runId:run,candidateDecisionsComplete:true,candidateCount:1,
   publicationCount:0,rejectionCounts:{unverified:1},decisionBatchPath:batchPath,
  }));
  await writeFile(join(root,'scopes/kaernten.json'),JSON.stringify({lastCandidateBatch:{runId:run,candidateDecisionsComplete:true,candidates:1,published:0,rejected:1},candidateDecisions:{
   [url]:{runId:run,outcome:'rejected',reason:'unverified',primaryOpened:true,primaryFullTextVerified:true},
  }}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='kaernten');
  assert.equal(scope.batchSource,'decision_amendment');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'decision_amendment');
  assert.deepEqual(scope.rejectionReasons,{unverified:1});
  assert.equal(scope.editorialReviewFlags.length,0);
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wave audit recognizes a closed no-lock Kärnten report after an emergency batch replaces scope state',async()=>{
 const root=await mkdtemp(join(tmpdir(),'news-wave-audit-kaernten-no-lock-'));const run='news-2026-11-05T21';
 try{
  for(const p of ['snapshots','source-policies','scopes',`reports/${run}`])await mkdir(join(root,p),{recursive:true});
  await writeFile(join(root,`snapshots/${run}.json`),JSON.stringify([{sourceId:'one',sourcePolicyVersion:4,links:[{url:'https://example.at/story'}]}]));
  await writeFile(join(root,'source-policies/v4.json'),JSON.stringify({sources:[{sourceId:'one',active:true}]}));
  const decisions=[
   {url:'https://orf.at/read',outcome:'rejected',reason:'no_practical_effect',primaryOpened:true,primaryFullTextVerified:true},
   {url:'https://orf.at/routine',outcome:'rejected',reason:'no_practical_effect',routineLowRelevanceTriage:'clear_routine_award_or_event',ongoingPracticalImpactSignal:false},
  ];
  await writeFile(join(root,`reports/${run}/kaernten.json`),JSON.stringify({
   scope:'kaernten',runId:run,status:'partial',closedAt:'2026-11-05T20:53:04.501Z',
   locksAcquired:false,decidedCandidates:2,publicationCount:0,decisions,
  }));
  await writeFile(join(root,'scopes/kaernten.json'),JSON.stringify({lastCandidateBatch:{
   runId:'emergency-2026-11-05T22-30',candidateDecisionsComplete:true,candidates:1,published:1,rejected:0,
  },candidateDecisions:{}}));
  const result=await auditNewsWave(root,run);const scope=result.scopes.find(x=>x.scope==='kaernten');
  assert.deepEqual(scope.batch,{runId:run,candidateDecisionsComplete:true,candidates:2,published:0,rejected:2});
  assert.equal(scope.batchSource,'closed_report');
  assert.equal(scope.decisionLedger.decisionsReadFrom,'closed_report');
  assert.deepEqual(scope.rejectionReasons,{no_practical_effect:2});
  assert.equal(scope.editorialReviewFlags.length,0);
 }finally{await rm(root,{recursive:true,force:true});}
});
