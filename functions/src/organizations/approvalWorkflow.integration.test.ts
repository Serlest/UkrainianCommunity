import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";

import {db} from "../firebase/admin";
import {discardUnpublishedOrganizationRequest} from "../content/contentDeletion";
import {
  approveOrganizationWorkflow,
  commitOrganizationReview,
  rejectOrganizationWorkflow,
  requestOrganizationRevisionWorkflow,
} from "./approvalWorkflow";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const actorUserId = "organization-reviewer-integration";
const submitterUserId = "organization-submitter-integration";
const organizationIds = [
  "org-approve-integration",
  "org-revision-integration",
  "org-reject-integration",
  "org-discard-integration",
];

before(async () => {
  if (!shouldRun) return;
  await cleanup();
  await db.collection("users").doc(actorUserId).set({globalRole: "owner", accountStatus: "active", blockState: "active", displayName: "Audit reviewer"});
  await db.collection("users").doc(submitterUserId).set({
    accountStatus: "active",
    blockState: "active",
  });
  await Promise.all(organizationIds.map((organizationId) => db.collection("organizations")
    .doc(organizationId)
    .set({
      name: `Organization ${organizationId}`,
      submittedByUserId: submitterUserId,
      moderationStatus: "pendingReview",
    })));
});

after(async () => {
  if (shouldRun) await cleanup();
});

test("complete organization moderation workflow commits state, audit, and inbox together", {
  skip: !shouldRun,
}, async () => {
  const cases = [
    {
      organizationId: organizationIds[0],
      workflow: approveOrganizationWorkflow,
      text: undefined,
      expectedStatus: "approved",
      expectedType: "organizationRequestApproved",
    },
    {
      organizationId: organizationIds[1],
      workflow: requestOrganizationRevisionWorkflow,
      text: "Add opening hours",
      expectedStatus: "needsRevision",
      expectedType: "organizationRequestNeedsRevision",
    },
    {
      organizationId: organizationIds[2],
      workflow: rejectOrganizationWorkflow,
      text: "Duplicate request",
      expectedStatus: "rejected",
      expectedType: "organizationRequestRejected",
    },
  ] as const;

  for (const item of cases) {
    const result = await commitOrganizationReview(
      actorUserId,
      {organizationId: item.organizationId},
      item.workflow,
      item.text
    );
    const [organization, notification, audit] = await Promise.all([
      db.collection("organizations").doc(item.organizationId).get(),
      db.collection("users").doc(submitterUserId)
        .collection("notificationInbox").doc(result.notificationId).get(),
      db.collection("auditLogs")
        .where("targetUserId", "==", submitterUserId)
        .where("actionType", "==", item.workflow.auditActionType)
        .get(),
    ]);

    assert.equal(organization.data()?.moderationStatus, item.expectedStatus);
    assert.equal(organization.data()?.reviewedByUserId, actorUserId);
    assert.equal(notification.exists, true);
    assert.equal(notification.data()?.type, item.expectedType);
    assert.equal(notification.data()?.sourceId, item.organizationId);
    assert.equal(audit.size, 1);
    assert.equal(audit.docs[0].data().performedBy, actorUserId);
  }
});

test("a non-reviewable request does not create another audit or notification", {
  skip: !shouldRun,
}, async () => {
  const organizationId = organizationIds[0];
  const beforeAudit = await db.collection("auditLogs")
    .where("targetUserId", "==", submitterUserId)
    .get();
  const beforeInbox = await db.collection("users").doc(submitterUserId)
    .collection("notificationInbox").get();

  await assert.rejects(() => commitOrganizationReview(
    actorUserId,
    {organizationId},
    approveOrganizationWorkflow
  ));

  const afterAudit = await db.collection("auditLogs")
    .where("targetUserId", "==", submitterUserId)
    .get();
  const afterInbox = await db.collection("users").doc(submitterUserId)
    .collection("notificationInbox").get();
  assert.equal(afterAudit.size, beforeAudit.size);
  assert.equal(afterInbox.size, beforeInbox.size);
});

test("submitter cleanup deletes a pending request but fails closed after approval", {
  skip: !shouldRun,
}, async () => {
  const organizationId = organizationIds[3];
  await db.collection("organizationCreationProofs").doc(organizationId).set({
    userId: submitterUserId,
  });
  assert.equal(await discardUnpublishedOrganizationRequest(
    organizationId,
    submitterUserId
  ), true);
  assert.equal((await db.collection("organizations").doc(organizationId).get()).exists, false);
  assert.equal((await db.collection("organizationCreationProofs").doc(organizationId).get()).exists, false);
  const discardAudit = await db.collection("auditLogs")
    .where("targetUserId", "==", submitterUserId)
    .where("actionType", "==", "organizationRequestDiscarded")
    .get();
  assert.equal(discardAudit.size, 1);
  assert.equal(discardAudit.docs[0].data().performedBy, submitterUserId);

  await db.collection("organizations").doc(organizationId).set({
    name: "Approved organization",
    submittedByUserId: submitterUserId,
    moderationStatus: "approved",
  });
  await assert.rejects(() => discardUnpublishedOrganizationRequest(
    organizationId,
    submitterUserId
  ));
  assert.equal((await db.collection("organizations").doc(organizationId).get()).exists, true);
});

async function cleanup(): Promise<void> {
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(submitterUserId)),
    ...organizationIds.map((organizationId) => db.recursiveDelete(
      db.collection("organizations").doc(organizationId)
    )),
    ...organizationIds.map((organizationId) => db.collection("organizationCreationProofs")
      .doc(organizationId).delete()),
  ]);
  const audit = await db.collection("auditLogs")
    .where("targetUserId", "==", submitterUserId)
    .get();
  await Promise.all(audit.docs.map((document) => document.ref.delete()));
}


test("repeated revision cycles create fresh inbox records instead of overwriting old alerts", {skip: !shouldRun}, async () => {
  const orgId = organizationIds[1];
  await db.collection("organizations").doc(orgId).update({moderationStatus: "pendingReview"});
  const first = await commitOrganizationReview(actorUserId, {organizationId: orgId}, requestOrganizationRevisionWorkflow, "First revision");
  await db.collection("organizations").doc(orgId).update({moderationStatus: "pendingReview"});
  const second = await commitOrganizationReview(actorUserId, {organizationId: orgId}, requestOrganizationRevisionWorkflow, "Second revision");
  assert.notEqual(first.notificationId, second.notificationId);
  for (const id of [first.notificationId, second.notificationId]) {
    assert.equal((await db.collection("users").doc(submitterUserId).collection("notificationInbox").doc(id).get()).exists, true);
  }
});

test("deleted applicants cannot become owners", {skip: !shouldRun}, async () => {
  const ref = db.collection("organizations").doc("org-deleted-applicant-audit");
  await ref.set({name: "Orphan request", submittedByUserId: "missing-applicant-audit", moderationStatus: "pendingReview"});
  await assert.rejects(() => commitOrganizationReview(actorUserId, {organizationId: ref.id}, approveOrganizationWorkflow),
    (e: unknown) => (e as {code?: string}).code === "failed-precondition");
  assert.equal((await ref.get()).get("moderationStatus"), "pendingReview");
  assert.equal((await ref.get()).get("ownerId"), undefined);
  await ref.delete();
});

test("exact revisions reject stale decisions and concurrent retries write only once", {skip: !shouldRun}, async () => {
  const {Timestamp} = await import("firebase-admin/firestore");
  const ref = db.collection("organizations").doc("org-concurrent-review-audit");
  await ref.set({name: "Concurrent request", submittedByUserId: submitterUserId, moderationStatus: "pendingReview", updatedAt: new Timestamp(1790000000, 123456000)});
  await assert.rejects(() => commitOrganizationReview(actorUserId, {organizationId: ref.id, expectedRevision: "1790000000:123456700"}, approveOrganizationWorkflow),
    (e: unknown) => (e as {code?: string}).code === "aborted");
  const request = {organizationId: ref.id, expectedRevision: "1790000000:123456000", operationId: "review-idempotent-audit"};
  const results = await Promise.all([commitOrganizationReview(actorUserId, request, approveOrganizationWorkflow), commitOrganizationReview(actorUserId, request, approveOrganizationWorkflow)]);
  assert.equal(results[0].notificationId, results[1].notificationId);
  assert.equal((await commitOrganizationReview(actorUserId, request, approveOrganizationWorkflow)).notificationId, results[0].notificationId);
  await assert.rejects(() => commitOrganizationReview(actorUserId, {...request, operationId: "other-decision"}, rejectOrganizationWorkflow, "Conflict"));
  assert.equal((await db.collection("auditLogs").where("newValue.organizationId", "==", ref.id).get()).size, 1);
  await ref.delete();
});

test("review transaction rechecks revoked privileges", {skip: !shouldRun}, async () => {
  const ref = db.collection("organizations").doc("org-revoked-reviewer-audit");
  await ref.set({name: "Protected request", submittedByUserId: submitterUserId, moderationStatus: "pendingReview"});
  await db.collection("users").doc("revoked-reviewer-audit").set({globalRole: "user", accountStatus: "active", blockState: "active"});
  await assert.rejects(() => commitOrganizationReview("revoked-reviewer-audit", {organizationId: ref.id}, approveOrganizationWorkflow),
    (e: unknown) => (e as {code?: string}).code === "permission-denied");
  assert.equal((await ref.get()).get("moderationStatus"), "pendingReview");
  await ref.delete();
});

test("history preserves repeated decisions and pages equal timestamps", {skip: !shouldRun}, async () => {
  const {Timestamp} = await import("firebase-admin/firestore");
  const {organizationReviewHistoryPage} = await import("./approvalWorkflow");
  const ids = ["history-audit-a", "history-audit-b", "history-audit-c"];
  for (const id of ids) await db.collection("auditLogs").doc(id).set({actionType: "organizationRequestNeedsRevision", createdAt: new Timestamp(2900000000, 123456000), reason: id, newValue: {organizationId: "same-org", organizationName: "Historical name", moderationStatus: "needsRevision"}});
  try {
    const first = await organizationReviewHistoryPage(2);
    assert.deepEqual(first.items.map((v) => v.id), ["history-audit-c", "history-audit-b"]);
    assert.ok(first.nextCursor);
    const second = await organizationReviewHistoryPage(2, first.nextCursor!);
    assert.equal(second.items[0].id, "history-audit-a");
    assert.equal(first.items[0].organizationName, "Historical name");
    assert.equal(first.nextCursor?.nanoseconds, 123456000);
  } finally { await Promise.all(ids.map((id) => db.collection("auditLogs").doc(id).delete())); }
});
