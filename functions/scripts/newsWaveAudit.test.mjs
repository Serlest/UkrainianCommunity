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
