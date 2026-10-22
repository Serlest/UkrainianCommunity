import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {buildJournalGrams, journalIndexField, journalIndexState, journalCursorCollection, queryJournal, reconcileJournalIndex} from "./journalQuery";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {writeClientDiagnostic} from "./clientDiagnostics";
const skip = !process.env.FIRESTORE_EMULATOR_HOST, prefix = "journal-query-test-";
const base = Timestamp.fromDate(new Date("2040-01-01T00:00:00Z"));
before(async () => {
  if (skip) return;
  const batch = db.batch();
  for (let i = 0; i < 360; i++) batch.set(db.doc(`systemLogs/${prefix}${String(i).padStart(3, "0")}`), {
    createdAt: new Timestamp(base.seconds + i, i * 1000), severity: "warning", severityRank: 3,
    category: "diagnostics", eventType: "technicalError", actorRole: "user", targetType: "none",
    operationName: "fetchUnreadCount", summary: i === 0 ? "Älteste Verbindung Київ" : "ordinary diagnostic", isReviewed: false,
    isAppAdminReadable: i % 2 === 0, metadata: {failureStage: "fetchResponse"},
  });
  await batch.commit();
});
after(async () => {
  if (skip) return;
  for (const collection of ["systemLogs", journalCursorCollection]) {
    const docs = await db.collection(collection).get(), batch = db.batch();
    for (const doc of docs.docs) if (collection !== "systemLogs" || doc.id.startsWith(prefix)) batch.delete(doc.ref);
    await batch.commit();
  }
  await db.doc(journalIndexState).delete();
});
test("bounded scan reaches old matches beyond empty first page", {skip}, async () => {
  const filter = {searchText: "alteste киів"};
  const a = await queryJournal("owner-a", "owner", {filter});
  assert.equal(a.items.length, 0); assert.equal(a.scanned, 250); assert.ok(a.cursor);
  const b = await queryJournal("owner-a", "owner", {filter, cursor: a.cursor});
  assert.equal(b.items.length, 1); assert.equal(b.items[0].id, prefix + "000"); assert.equal(b.cursor, null);
});
test("query cursor binds account, role, filters, limit, sort and expiration", {skip}, async () => {
  const p = await queryJournal("owner-a", "owner", {limit: 2}); assert.ok(p.cursor);
  for (const [id, role, q] of [["owner-b", "owner", {limit: 2}], ["owner-a", "admin", {limit: 2}], ["owner-a", "owner", {limit: 3}], ["owner-a", "owner", {limit: 2, sort: "oldestFirst"}], ["owner-a", "owner", {limit: 2, filter: {isReviewed: true}}]] as const)
    await assert.rejects(queryJournal(id, role, {...q, cursor: p.cursor}), {code: "aborted"});
  await assert.rejects(queryJournal("owner-a", "owner", {limit: 2, cursor: p.cursor}, db, new Date(Date.now() + 3700000)), {code: "aborted"});
});
test("admin cannot read owner records; pages preserve all nanosecond cursor positions", {skip}, async () => {
  let cursor: string | undefined; const rows: string[] = [];
  do {
    const p = await queryJournal("admin-a", "admin", {limit: 37, cursor, filter: {startDate: base.toMillis()}});
    assert.ok(p.items.every(d => d.isAppAdminReadable === true)); rows.push(...p.items.map(d => d.id)); cursor = p.cursor ?? undefined;
  } while (cursor);
  assert.equal(rows.length, 180); assert.equal(new Set(rows).size, 180);
  assert.equal((await queryJournal("admin-a", "admin", {filter: {isAppAdminReadable: false}})).items.length, 0);
  await assert.rejects(queryJournal("user-a", "user", {}), {code: "permission-denied"});
});
test("source-derived text index handles accents, current updates and repeat reconciliation", {skip}, async () => {
  const id = prefix + "000";
  assert.equal(await reconcileJournalIndex(db, id), true); assert.equal(await reconcileJournalIndex(db, id), false);
  await db.doc(journalIndexState).set({ready: true});
  const p = await queryJournal("owner-a", "owner", {filter: {searchText: "ALTESTE Київ"}});
  assert.equal(p.items.length, 1); assert.equal(p.items[0][journalIndexField], undefined);
  await db.doc(`systemLogs/${id}`).update({summary: "new current text"}); await reconcileJournalIndex(db, id);
  assert.equal((await queryJournal("owner-a", "owner", {filter: {searchText: "ALTESTE Київ"}})).items.length, 0);
  await db.doc(journalIndexState).set({ready: false});
});
test("localized operation aliases cover older records", {skip}, async () => {
  const p = await queryJournal("owner-a", "owner", {filter: {searchText: "Лічильник"}, operationAliases: ["fetchUnreadCount"]});
  assert.equal(p.items.length, 100); assert.ok(p.cursor);
  assert.equal((await queryJournal("owner-a", "owner", {filter: {searchText: "Лічильник"}, operationAliases: ["fetchUnreadCount"], cursor: p.cursor})).items.length, 100);
});
test("malformed query and untrusted cursor are rejected", {skip}, async () => {
  for (const q of [{limit: 10000}, {filter: {isReviewed: "yes"}}, {cursor: "unsafe"}, {filter: {injected: true}}, {sort: "random"}])
    await assert.rejects(queryJournal("owner-a", "owner", q), {code: "invalid-argument"});
});
test("diagnostic retry has one ID and quota write; deleted logs never resurrect", {skip}, async () => {
  const uid = "journal-delivery-test-user", clientEventId = "12b76590-4141-4f9a-879c-0dc3e50ba46e";
  await db.doc(`users/${uid}`).set({globalRole: "user", accountStatus: "active"}); await seedCurrentLegalForIntegration(uid);
  const data = {principalId: uid, clientEventId, occurredAtMilliseconds: Date.now() - 120000, eventType: "technicalError", severity: "warning", targetType: "none", summary: "Read failed", metadata: {failureStage: "fetchResponse"}};
  const request = (payload: unknown) => ({data: payload, auth: {uid, token: {email_verified: true}}}) as any;
  try {
    const first = await writeClientDiagnostic.run(request(data));
    assert.deepEqual(await writeClientDiagnostic.run(request(data)), first); assert.equal(Date.parse(first.createdAt), data.occurredAtMilliseconds);
    assert.equal((await db.doc(`systemLogDiagnosticRateLimits/${uid}`).get()).get("count"), 1);
    await assert.rejects(writeClientDiagnostic.run(request({...data, summary: "changed"})), {code: "invalid-argument"});
    await db.doc(`systemLogs/${first.id}`).delete(); assert.deepEqual(await writeClientDiagnostic.run(request(data)), first);
    assert.equal((await db.doc(`systemLogs/${first.id}`).get()).exists, false);
    await assert.rejects(writeClientDiagnostic.run(request({...data, clientEventId: "22b76590-4141-4f9a-879c-0dc3e50ba46e", occurredAtMilliseconds: Date.now() - 49 * 3600000})), {code: "out-of-range"});
  } finally {
    await db.doc(`users/${uid}`).delete(); await db.doc(`systemLogDiagnosticRateLimits/${uid}`).delete();
    await Promise.all((await db.collection("systemLogDiagnosticReceipts").get()).docs.map(d => d.ref.delete()));
  }
});

test("long diagnostic text uses overflow rather than exceeding Firestore index fan-out", () => {
  const text = Array.from({length: 1000}, (_, i) => String.fromCodePoint(0x4e00 + i)).join("");
  assert.deepEqual(buildJournalGrams("large", {technicalMessage: text}), ["!overflow-v1"]);
});
