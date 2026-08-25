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
  assert.equal(await discardUnpublishedOrganizationRequest(
    organizationId,
    submitterUserId
  ), true);
  assert.equal((await db.collection("organizations").doc(organizationId).get()).exists, false);

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
  ]);
  const audit = await db.collection("auditLogs")
    .where("targetUserId", "==", submitterUserId)
    .get();
  await Promise.all(audit.docs.map((document) => document.ref.delete()));
}
