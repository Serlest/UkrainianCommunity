import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {reviewContentModeration} from "./contentModeration";
import {setUserBlocked, userBlockDocumentPath} from "./userBlocks";
import {deleteFeedback, clearFeedbackInbox} from "../feedback/feedbackManagement";
import {submitContentReport} from "./contentReports";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
function request(uid: string, data: unknown) {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):/);
  return {auth: {uid, token: {email_verified: true, email: `${uid}@example.org`}}, data} as never;
}
async function actor(uid: string, globalRole = "owner") {
  await db.doc(`users/${uid}`).set({globalRole, accountStatus: "active", blockState: "active", displayName: uid});
}

test("Build80 moderation commits one concurrent decision, replays the receipt, and rejects stale or unauthorized changes", {skip: !enabled}, async () => {
  const id = `fix80-moderation-${Date.now()}`;
  await actor(id);
  await actor(`${id}-outsider`, "user");
  const stamp = Timestamp.fromMillis(Date.now() - 1000);
  await db.doc(`news/${id}`).set({moderationStatus: "pendingReview", updatedAt: stamp});
  const base = {contentType: "news", contentId: id, expectedRevision: `${stamp.seconds}:${stamp.nanoseconds}`};
  await assert.rejects(reviewContentModeration.run(request(`${id}-outsider`, {...base, operationId: "outsider", decision: "approved"})), {code: "permission-denied"});
  const inputs = [{...base, operationId: "approve", decision: "approved"}, {...base, operationId: "reject", decision: "rejected"}];
  const results = await Promise.allSettled(inputs.map(input => reviewContentModeration.run(request(id, input))));
  assert.equal(results.filter(result => result.status === "fulfilled").length, 1);
  const winner = results.findIndex(result => result.status === "fulfilled");
  const stored = await db.doc(`news/${id}`).get();
  assert.equal(stored.get("moderationStatus"), inputs[winner].decision);
  const replay = await reviewContentModeration.run(request(id, inputs[winner]));
  assert.equal(replay.replayed, true);
  await assert.rejects(reviewContentModeration.run(request(id, {...inputs[winner], decision: inputs[1 - winner].decision})), {code: "already-exists"});
  await assert.rejects(reviewContentModeration.run(request(id, {...inputs[winner], operationId: "stale"})), {code: "aborted"});
});

test("Build80 unblock removes deleted and deactivated targets and safely repeats", {skip: !enabled}, async () => {
  const id = `fix80-unblock-${Date.now()}`;
  await actor(id, "user");
  for (const state of ["deleted", "deactivated"]) {
    const target = `${id}-${state}`;
    if (state === "deactivated") await db.doc(`users/${target}`).set({accountStatus: state});
    const reference = db.doc(userBlockDocumentPath(id, target));
    await reference.set({displayName: "Former user"});
    for (let attempt = 0; attempt < 2; attempt++) {
      const result = await setUserBlocked.run(request(id, {targetUserId: target, isBlocked: false}));
      assert.equal(result.isBlocked, false);
      assert.equal((await reference.get()).exists, false);
    }
  }
});

test("Build80 feedback clear preserves embedded and canonical DSA records and deletes ordinary message trees", {skip: !enabled}, async () => {
  const id = `fix80-feedback-${Date.now()}`;
  await actor(id);
  for (const kind of ["embedded", "canonical", "ordinary"]) {
    const reference = db.doc(`feedback/${id}-${kind}`);
    await reference.set(kind === "embedded" ? {dsaCase: {status: "submitted"}} : {status: "open"});
    await reference.collection("messages").doc("message").set({body: "Evidence"});
    if (kind === "canonical") await db.doc(`dsaCases/${reference.id}`).set({status: "submitted"});
  }
  for (const kind of ["embedded", "canonical"]) {
    await assert.rejects(deleteFeedback.run(request(id, {feedbackId: `${id}-${kind}`})), {code: "failed-precondition"});
  }
  await clearFeedbackInbox.run(request(id, {}));
  for (const kind of ["embedded", "canonical", "ordinary"]) {
    assert.equal((await db.doc(`feedback/${id}-${kind}`).get()).exists, kind !== "ordinary");
    assert.equal((await db.doc(`feedback/${id}-${kind}/messages/message`).get()).exists, kind !== "ordinary");
  }
});

test("Build80 reports deduplicate only identical active notices", {skip: !enabled}, async () => {
  const id = `fix80-report-${Date.now()}`;
  await actor(id, "user");
  await db.doc(`news/${id}`).set({moderationStatus: "approved", title: "Reported content", authorId: "another-user"});
  const data = {targetType: "news", targetId: id, reason: "other", illegalExplanation: "Specific unlawful statement in this content", goodFaithConfirmed: true, evidence: "First evidence"};
  const first = await submitContentReport.run(request(id, data));
  const duplicate = await submitContentReport.run(request(id, data));
  assert.equal(duplicate.reportId, first.reportId);
  assert.equal(duplicate.wasDuplicate, true);
  const changed = await submitContentReport.run(request(id, {...data, evidence: "Different evidence"}));
  assert.notEqual(changed.reportId, first.reportId);
  await db.doc(`dsaCases/${first.reportId}`).update({status: "decided"});
  const reopened = await submitContentReport.run(request(id, data));
  assert.notEqual(reopened.reportId, first.reportId);
  assert.equal(reopened.wasDuplicate, false);
});
