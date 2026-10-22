import {strict as assert} from "node:assert";
import {before, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {seedVerifiedAuthForIntegration} from "../auth/authIntegrationFixture";
import {manageContentModeration, reviewContentModeration} from "./contentModeration";
import {notifyContentModeration} from "../notifications/workflowNotifications";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
const ids = ["review-owner", "review-admin", "review-author", "review-org-owner", "review-outsider"];
const request = (uid: string, data: unknown) => ({auth: {uid, token: {email_verified: true}}, data}) as never;
const revision = "1792670000:123456000";
const stamp = new Timestamp(1792670000, 123456000);
before(async () => {
  if (!enabled) return;
  assert.match(process.env.FIRESTORE_EMULATOR_HOST!, /^(localhost|127\.0\.0\.1):/);
  await seedVerifiedAuthForIntegration(...ids);
  for (const [index, uid] of ids.entries()) await db.doc(`users/${uid}`).set({globalRole: index === 0 ? "owner" : index === 1 ? "admin" : "user", accountStatus: "active", blockState: "active", displayName: uid});
  await seedCurrentLegalForIntegration(...ids);
  await db.doc("organizations/review-org").set({ownerId: ids[3], adminIds: [], moderatorIds: [ids[2]]});
});
async function seed(id: string, type = "news", author = ids[2]) {
  await db.doc(`${type === "news" ? "news" : "events"}/${id}`).set({title: id, summary: "Summary", body: "Full body", details: "Event details", moderationStatus: "pendingReview", updatedAt: stamp,
    createdAt: stamp, sourceType: "organization", regionScope: "austria", organizationId: "review-org", organizationName: "Test organization", authorId: author, authorName: "Test Author", updatedByUserId: author,
    localizations: {uk: {title: "Український текст", subtitle: "Вступ", body: "Повний текст"}, de: {title: "Deutscher Text", subtitle: "Einleitung", body: "Vollständiger Inhalt"}}});
}

test("queue has stable exact cursors, complete counts, bounded pages, and both translations", {skip: !enabled}, async () => {
  for (let i = 0; i < 35; i++) await seed(`page-${String(i).padStart(2, "0")}`);
  const first = await manageContentModeration.run(request(ids[0], {action: "list", contentType: "news", limit: 30}));
  assert.ok("items" in first); if (!("items" in first) || !first.items || !first.counts) throw new Error("Missing queue");
  assert.equal(first.items.length, 30); assert.equal(first.counts.news, 35);
  assert.equal(first.items[0].revision, revision); assert.equal(first.items[0].translations.de.title, "Deutscher Text"); assert.equal(first.items[0].translations.de.body, "");
  const next = await manageContentModeration.run(request(ids[0], {action: "list", contentType: "news", limit: 30, cursor: first.cursor}));
  assert.ok("items" in next); if (!("items" in next) || !next.items) throw new Error("Missing queue");
  assert.equal(next.items.length, 5); assert.equal(next.cursor, null);
  assert.equal(new Set([...first.items, ...next.items].map(item => item.id)).size, 35);
  await assert.rejects(manageContentModeration.run(request(ids[0], {action: "list", contentType: "news", limit: 1000})), {code: "invalid-argument"});
});
test("reviewer, contributor and outsider permissions protect previews, lists, history and decisions", {skip: !enabled}, async () => {
  await seed("access");
  for (const uid of [ids[0], ids[1], ids[2], ids[3]]) {
    const result = await manageContentModeration.run(request(uid, {action: "preview", contentType: "news", contentId: "access"}));
    assert.ok("item" in result); if ("item" in result) { assert.equal(result.item.canReview, uid === ids[0] || uid === ids[1]); assert.equal(result.item.translations.de.body, "Vollständiger Inhalt"); }
  }
  await assert.rejects(manageContentModeration.run(request(ids[4], {action: "preview", contentType: "news", contentId: "access"})), {code: "permission-denied"});
  for (const action of ["list", "history"]) await assert.rejects(manageContentModeration.run(request(ids[2], {action, contentType: "news"})), {code: "permission-denied"});
  await assert.rejects(reviewContentModeration.run(request(ids[3], {contentType: "news", contentId: "access", decision: "approved", expectedRevision: revision, operationId: "unauthorized"})), {code: "permission-denied"});
});
test("new decisions require a reason, exact reviewed revision and matching principal; legacy payload remains accepted", {skip: !enabled}, async () => {
  await seed("decision");
  const payload = {contentType: "news", contentId: "decision", decision: "rejected", expectedRevision: revision, operationId: "decision", principalId: ids[0]};
  await assert.rejects(reviewContentModeration.run(request(ids[0], payload)), {code: "invalid-argument"});
  await assert.rejects(reviewContentModeration.run(request(ids[1], {...payload, reason: "Reason"})), {code: "permission-denied"});
  await assert.rejects(reviewContentModeration.run(request(ids[0], {...payload, expectedRevision: "1792670000:123456001", reason: "Reason"})), {code: "aborted"});
  await assert.rejects(reviewContentModeration.run(request(ids[0], {...payload, reason: "x".repeat(2001)})), {code: "invalid-argument"});
  const first = await reviewContentModeration.run(request(ids[0], {...payload, reason: "Please verify source / date"}));
  const replay = await reviewContentModeration.run(request(ids[0], {...payload, reason: "Please verify source / date"}));
  assert.equal(first.moderationStatus, "rejected"); assert.equal(replay.replayed, true);
  assert.equal((await db.doc("news/decision").get()).get("moderationReason"), "Please verify source / date");
  await seed("legacy");
  assert.equal((await reviewContentModeration.run(request(ids[0], {contentType: "news", contentId: "legacy", decision: "rejected", expectedRevision: revision, operationId: "legacy"}))).moderationStatus, "rejected");
});
test("return, author edit and resubmit lead back into the queue; old expected revision cannot approve edited text", {skip: !enabled}, async () => {
  for (const contentType of ["news", "event"]) {
    const id = `return-${contentType}`, path = `${contentType === "news" ? "news" : "events"}/${id}`;
    await seed(id, contentType);
    await reviewContentModeration.run(request(ids[0], {contentType, contentId: id, decision: "needsRevision", reason: "Correct source", principalId: ids[0], expectedRevision: revision, operationId: id}));
    const edited = new Timestamp(1792670001, 500000000);
    await db.doc(path).update({title: "Corrected title", updatedAt: edited});
    await assert.rejects(manageContentModeration.run(request(ids[4], {action: "resubmit", contentType, contentId: id, expectedRevision: "1792670001:500000000"})), {code: "permission-denied"});
    await assert.rejects(manageContentModeration.run(request(ids[2], {action: "resubmit", contentType, contentId: id, expectedRevision: revision})), {code: "aborted"});
    await manageContentModeration.run(request(ids[2], {action: "resubmit", contentType, contentId: id, expectedRevision: "1792670001:500000000"}));
    const replay = await manageContentModeration.run(request(ids[2], {action: "resubmit", contentType, contentId: id, expectedRevision: "1792670001:500000000"}));
    assert.ok("item" in replay);
    assert.equal((await db.doc(path).get()).get("moderationStatus"), "pendingReview");
    assert.equal((await db.doc(path).get()).get("moderationReason"), "");
    await assert.rejects(reviewContentModeration.run(request(ids[0], {contentType, contentId: id, decision: "approved", expectedRevision: revision, operationId: id + "-stale"})), {code: "aborted"});
  }
});
test("history retains title, reviewer, reason and separate review cycles with cursor pagination", {skip: !enabled}, async () => {
  const page = await manageContentModeration.run(request(ids[0], {action: "history", limit: 2}));
  assert.ok("history" in page); if (!("history" in page) || !page.history) throw new Error("Missing history");
  assert.equal(page.history.length, 2); assert.ok(page.cursor);
  assert.ok(page.history.every(entry => entry.title && entry.reviewerName));
  const next = await manageContentModeration.run(request(ids[0], {action: "history", limit: 2, cursor: page.cursor}));
  assert.ok("history" in next); if (!("history" in next) || !next.history) throw new Error("Missing history");
  assert.equal(new Set([...page.history, ...next.history].map(entry => entry.id)).size, 4);
});
test("decision notifications identify the moderator and reach both author and staff exactly once", {skip: !enabled}, async () => {
  await seed("notice");
  const before = (await db.doc("news/notice").get()).data()!;
  const after = {...before, moderationStatus: "needsRevision", moderatedByUserId: ids[0], moderationReason: "Fix source"};
  await notifyContentModeration("review-notice", "news", "notice", before, after);
  await notifyContentModeration("review-notice", "news", "notice", before, after);
  for (const recipient of [ids[2], ids[3]]) {
    const docs = await db.collection(`users/${recipient}/notificationInbox`).get();
    assert.equal(docs.size, 1); const n = docs.docs[0].data();
    assert.equal(n.metadata.titleLocKey, "notifications.push.content_moderated.title");
    assert.equal(n.metadata.displayTitleLocKey, "notifications.push.content_moderated.needsRevision.title");
    assert.equal(n.actorUserId, ids[0]); assert.equal(n.sourceId, "news:notice"); assert.ok(n.message.includes("Fix source"));
  }
  assert.equal((await db.collection(`users/${ids[0]}/notificationInbox`).get()).size, 0);
  await seed("self-authored", "news", ids[3]);
  await notifyContentModeration("self-authored", "news", "self-authored", {moderationStatus: "pendingReview"}, {...after, authorId: ids[3], updatedByUserId: ids[3], moderationStatus: "rejected"});
  assert.equal((await db.collection(`users/${ids[3]}/notificationInbox`).get()).size, 2);
});

test("installed Date-based clients retain a safe microsecond revision comparison; new clients remain exact", {skip: !enabled}, async () => {
  await seed("legacy-precision");
  const result = await reviewContentModeration.run(request(ids[0], {contentType: "news", contentId: "legacy-precision", decision: "approved", expectedRevision: "1792670000:123456001", operationId: "legacy-precision"}));
  assert.equal(result.moderationStatus, "approved");
  await seed("legacy-stale");
  await assert.rejects(reviewContentModeration.run(request(ids[0], {contentType: "news", contentId: "legacy-stale", decision: "approved", expectedRevision: "1792670000:123457001", operationId: "legacy-stale"})), {code: "aborted"});
});
