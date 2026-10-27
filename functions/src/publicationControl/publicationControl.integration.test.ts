import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {test} from 'node:test';
import {Timestamp} from 'firebase-admin/firestore';
import {db} from '../firebase/admin';
import {seedCurrentLegalForIntegration} from '../auth/legalIntegrationFixture';
import {dailyDocumentIDFor} from '../analytics/analyticsDate';
import {getPublicationControl,publicationProjection,updatePublicationIndex,rebuildPublicationDay,validPublicationDay} from './publicationControl';
const enabled=Boolean(process.env.FIRESTORE_EMULATOR_HOST),prefix=`control-${randomUUID()}`;
const req=(action:string,data:object={},role='owner')=>({auth:{uid:`${prefix}-${role}`,token:{email_verified:true}},data:{action,principalId:`${prefix}-${role}`,...data}} as never);
test('publication index is first-publication only, replay safe and canonical after deletion', {skip:!enabled},async()=>{
 const id=prefix+'-post',ref=db.doc(`news/${id}`),index=db.doc(`publicationControlItems/news_${id}`),created=Timestamp.now();
 try {
  const draft={title:'Draft',moderationStatus:'draft',createdAt:created,federalState:'wien'};
  await ref.set(draft);await updatePublicationIndex('news',id,draft,undefined,created);assert.equal((await index.get()).exists,false);
  const approved={...draft,title:'Published',moderationStatus:'approved',localizations:{de:{title:'Nachricht'}}};const publishedAt=Timestamp.fromMillis(created.toMillis()+1000);
  await ref.set(approved);await Promise.all([updatePublicationIndex('news',id,approved,draft,publishedAt),updatePublicationIndex('news',id,approved,draft,publishedAt)]);
  assert.equal((await index.get()).get('firstPublicAt').toMillis(),publishedAt.toMillis());assert.equal((await index.get()).get('titleDE'),'Nachricht');
  await ref.update({title:'Updated'});await updatePublicationIndex('news',id,{...approved,title:'Updated'},approved,Timestamp.now());assert.equal((await index.get()).get('firstPublicAt').toMillis(),publishedAt.toMillis());
  await ref.delete();await updatePublicationIndex('news',id,undefined,approved,Timestamp.now());await updatePublicationIndex('news',id,approved,draft,publishedAt);
  assert.equal((await index.get()).get('sourceState'),'removed');assert.equal((await index.get()).get('title'),'Updated');
  // Expired old records cannot turn an ordinary title edit into a new publication.
  await index.delete();await ref.set(approved);await updatePublicationIndex('news',id,approved,approved,Timestamp.now());assert.equal((await index.get()).exists,false);
 } finally {await ref.delete();await index.delete();}
});
test('owner overview counts Austria once, filters pages, rejects other roles and exposes only compact data', {skip:!enabled},async()=>{
 const ids=Array.from({length:36},(_,i)=>`${prefix}-${i}`),now=Timestamp.now(),day=dailyDocumentIDFor(now.toDate());
 try {
  for(const role of ['owner','admin','user'])await db.doc(`users/${prefix}-${role}`).set({globalRole:role,accountStatus:'active',blockState:'active'});await seedCurrentLegalForIntegration(...['owner','admin','user'].map(role=>`${prefix}-${role}`));
  const batch=db.batch();for(const [i,id]of ids.entries())batch.set(db.doc(`publicationControlItems/news_${id}`),publicationProjection('news',id,{title:'Title',moderationStatus:'approved',regionScope:i===0?'austria':'federalState',federalState:'wien'},now,'creation'));await batch.commit();
  await assert.rejects(getPublicationControl.run(req('overview',{},'admin')),{code:'permission-denied'});await assert.rejects(getPublicationControl.run(req('overview',{},'user')),{code:'permission-denied'});await assert.rejects(getPublicationControl.run(req('overview',{principalId:'other'})),{code:'permission-denied'});
  await rebuildPublicationDay(day);
  const overview=await getPublicationControl.run(req('overview',{day})) as any;assert.equal(overview.news,36);assert.equal(overview.regions.find((r:any)=>r.region==='austria').news,1);
  const page=await getPublicationControl.run(req('items',{day,region:'wien'})) as any;assert.equal(page.items.length,30);assert.equal(page.total,35);assert.ok(!('payload'in page.items[0]));
  const more=await getPublicationControl.run(req('items',{day,region:'wien',cursor:page.cursor})) as any;assert.equal(more.items.length,5);assert.equal(more.cursor,null);
  await assert.rejects(getPublicationControl.run(req('items',{day:'2020-01-01'})),{code:'invalid-argument'});await assert.rejects(getPublicationControl.run(req('items',{region:'invalid'})),{code:'invalid-argument'});
 } finally {await Promise.all(ids.map(id=>db.doc(`publicationControlItems/news_${id}`).delete()));await Promise.all(['owner','admin','user'].map(role=>db.doc(`users/${prefix}-${role}`).delete()));}
});
test('Vienna first-publication day handles midnight and DST',()=>{
 const item=publicationProjection('event','id',{regionScope:'austria'},Timestamp.fromDate(new Date('2026-10-24T22:30:00Z')),'creation');assert.equal(item.day,'2026-10-25');assert.equal(item.region,'austria');
});

test('dates reject impossible/future days and respect the compatibility window',()=>{
 assert.equal(validPublicationDay('2026-02-30','2026-03-01'),false);
 assert.equal(validPublicationDay('2026-10-28','2026-10-27'),false);
 assert.equal(validPublicationDay('2026-09-27','2026-10-27'),true);
 assert.equal(validPublicationDay('2026-09-26','2026-10-27'),false);
});

test('regional history is paged on the server and foreign or vanished cursors cannot cross its scope',{skip:!enabled},async()=>{
 const ids=Array.from({length:84},()=>randomUUID().replaceAll('-','').padEnd(40,'0'));
 const actor=`${prefix}-owner`,day=dailyDocumentIDFor(new Date());
 try {
  await db.doc(`users/${actor}`).set({globalRole:'owner',accountStatus:'active',blockState:'active'});await seedCurrentLegalForIntegration(actor);
  const batch=db.batch();ids.forEach((id,i)=>batch.set(db.doc(`publicationControlRuns/${id}`),{kind:'news',region:i<82?'tirol':'wien',endedAt:Timestamp.fromMillis(Date.now()+i),runId:`test-${i}`,status:'partial',scheduledAt:Timestamp.fromMillis(1000)}));await batch.commit();
  const page=await getPublicationControl.run(req('runs',{day,region:'tirol'})) as any;
  assert.equal(page.runs.length,80);assert.ok(page.runs.every((r:any)=>r.region==='tirol'));assert.equal(page.runs[0].scheduledAt,1000);
  const more=await getPublicationControl.run(req('runs',{day,region:'tirol',cursor:page.cursor})) as any;
  assert.equal(more.runs.length,2);assert.equal(more.cursor,null);assert.equal(new Set([...page.runs,...more.runs].map(r=>r.id)).size,82);
  await assert.rejects(getPublicationControl.run(req('runs',{day,region:'tirol',cursor:ids[83]})),{code:'aborted'});
  await db.doc(`publicationControlRuns/${page.cursor}`).delete();await assert.rejects(getPublicationControl.run(req('runs',{day,region:'tirol',cursor:page.cursor})),{code:'aborted'});
 }finally{await Promise.all(ids.map(id=>db.doc(`publicationControlRuns/${id}`).delete()));await db.doc(`users/${actor}`).delete();}
});
