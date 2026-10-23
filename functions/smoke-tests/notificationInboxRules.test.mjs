import assert from 'node:assert/strict';
import {after, before, test} from 'node:test';
import {readFileSync} from 'node:fs';
import {initializeTestEnvironment, assertSucceeds, assertFails} from '@firebase/rules-unit-testing';
import {collection, doc, getDocs, getDoc, query, where, orderBy, documentId, limit, startAfter, Timestamp, serverTimestamp, updateDoc, writeBatch} from 'firebase/firestore';
import {seedCurrentLegalVersions} from './legalRuleFixtures.mjs';
let env, db;
const uid = 'inbox-owner';
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-uac-inbox-pages', firestore: {
    rules: readFileSync(new URL('../../Firebase/firestore.rules', import.meta.url), 'utf8'),
  }});
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const admin = context.firestore(), batch = writeBatch(admin);
    batch.set(doc(admin, 'users', uid), {id: uid, accountStatus: 'active', blockState: 'active'});
    for (let i = 0; i < 52; i++) batch.set(doc(admin, 'users', uid, 'notificationInbox', `n${String(i).padStart(3, '0')}`), {
      createdAt: new Timestamp(1000 - i, 123456000), isRead: i < 50,
      archivedAt: null, deletedAt: i < 50 ? new Timestamp(1100, 0) : null,
      title: 'Immutable notification', recipientUserId: uid,
    });
    await batch.commit();
  });
  await seedCurrentLegalVersions(env);
  db = env.authenticatedContext(uid, {email_verified: true}).firestore();
});
after(async () => { await env?.cleanup(); });
const inbox = () => collection(db, 'users', uid, 'notificationInbox');
test('raw cursor crosses deleted head and unread query independently finds older messages', async () => {
  const base = query(inbox(), orderBy('createdAt', 'desc'), orderBy(documentId(), 'desc'));
  const head = await assertSucceeds(getDocs(query(base, limit(51))));
  assert.equal(head.size, 51);
  assert.ok(head.docs.slice(0, 50).every(row => row.get('deletedAt') != null));
  const cursor = head.docs[49];
  const older = await assertSucceeds(getDocs(query(base, startAfter(cursor.get('createdAt'), cursor.id), limit(51))));
  assert.deepEqual(older.docs.map(row => row.id), ['n050', 'n051']);
  const unread = await assertSucceeds(getDocs(query(inbox(), where('isRead', '==', false), orderBy('createdAt', 'desc'), orderBy(documentId(), 'desc'), limit(51))));
  assert.deepEqual(unread.docs.map(row => row.id), ['n050', 'n051']);
  assert.equal(unread.docs[0].get('createdAt').nanoseconds, 123456000);
});
test('recipient can archive restore mark unread and delete while content and another inbox remain protected', async () => {
  const own = doc(inbox(), 'n050');
  await assertSucceeds(updateDoc(own, {archivedAt: serverTimestamp(), isRead: true, readAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(own, {archivedAt: null, isRead: true, readAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(own, {archivedAt: null, isRead: false, readAt: null}));
  assert.equal((await getDoc(own)).get('archivedAt'), null);
  await assertFails(updateDoc(own, {title: 'Forged'}));
  const other = env.authenticatedContext('other-user', {email_verified: true}).firestore();
  await assertFails(getDocs(collection(other, 'users', uid, 'notificationInbox')));
  await assertFails(updateDoc(doc(other, 'users', uid, 'notificationInbox', 'n050'), {isRead: true}));
  await assertSucceeds(updateDoc(own, {deletedAt: serverTimestamp(), isRead: true, readAt: serverTimestamp()}));
});
