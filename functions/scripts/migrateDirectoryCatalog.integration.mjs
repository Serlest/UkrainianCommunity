import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {Firestore} from '@google-cloud/firestore';
test('bootstrap preserves edits, seeds history, rejects repeat and stale backup',{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
 const db=new Firestore({projectId:'demo-uac-directory-bootstrap'});
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'directory-bootstrap-'));
 const catalog=JSON.parse(fs.readFileSync(process.env.UAC_TEST_CATALOG,'utf8'));
 const file=path.join(dir,'catalog.json'), backup=path.join(dir,'backup.json');
 fs.writeFileSync(file,JSON.stringify(catalog));
 const health={...catalog.find(c=>c.id==='health'),title:{ukrainian:'Збережений текст',german:'Redaktionell gespeichert'}};
 const original={id:'health',payload:JSON.stringify(health),revision:7};
 const command=(mode,b=backup)=>spawnSync(process.execPath,['scripts/migrateDirectoryCatalog.mjs',mode,file,b],{encoding:'utf8',env:process.env});
 try{
  await db.recursiveDelete(db.collection('directoryCategories'));
  await db.doc('appConfig/directoryCatalog').delete();
  await db.doc('directoryCategories/health').set(original);
  let r=command('--plan');assert.equal(r.status,0,r.stderr);
  await db.doc('directoryCategories/health').update({revision:8});
  assert.notEqual(command('--apply').status,0);
  assert.equal((await db.collection('directoryCategories').get()).size,1);
  await db.doc('directoryCategories/health').set(original);
  const b2=path.join(dir,'backup2.json');r=command('--plan',b2);assert.equal(r.status,0,r.stderr);
  r=command('--apply',b2);assert.equal(r.status,0,r.stderr);
  assert.deepEqual((await db.doc('directoryCategories/health').get()).data(),original);
  r=command('--verify',b2);assert.equal(r.status,0,r.stderr);
  assert.equal((await db.collection('directoryCategories').get()).size,25);
  assert.equal((await db.collection('directoryRecentAdditions').get()).size,0);
  assert.notEqual(command('--apply',b2).status,0);
 }finally{await db.terminate();fs.rmSync(dir,{recursive:true,force:true});}
});
