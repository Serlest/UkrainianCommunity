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
  await writeFile(join(root,'scopes/wien.json'),JSON.stringify({lastCandidateBatch:{runId:run,candidates:2},candidateDecisions:{a:{runId:run,outcome:'published',contentId:'published',readbackReceiptPath:receipt},b:{runId:run,outcome:'rejected',reason:'unverified'}}}));
  const result=await auditNewsWave(root,run);
  assert.equal(result.snapshot.expectedSources,1);assert.equal(result.completedReports,1);
  assert.equal(result.scopes.filter(x=>x.reportMissing).length,9);
  assert.equal(result.scopes[0].evidenceLimits.unverifiedCandidates,1);
  assert.equal(result.scopes[0].publications[0].verifiedReceipt,true);
  assert.equal(await readFile(join(root,`snapshots/${run}.json`),'utf8'),snapshot);
 }finally{await rm(root,{recursive:true,force:true});}
});
