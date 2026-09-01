import {strict as assert} from "node:assert";
import {after, beforeEach, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {
  beginOwnerContentDraftPublicationForUser,
  failOwnerContentDraftPublicationForUser,
  finalizeOwnerContentDraftPublicationForUser,
} from "./ownerContentDrafts";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const ownerUserId = "content-planning-state-machine-owner";
const draftId = "a".repeat(40);
const contentId = `planning-${draftId}`;
const draftReference = db.collection("users").doc(ownerUserId)
  .collection("contentPlanningDrafts").doc(draftId);
const contentReference = db.collection("news").doc(contentId);

beforeEach(async () => {
  if (!live) return;
  await cleanup();
  await draftReference.set({
    id: draftId,
    ownerUserId,
    schemaVersion: 3,
    kind: "news",
    state: "readyForReview",
    title: "Planning state machine",
    createdAt: Timestamp.fromMillis(1_000),
    updatedAt: Timestamp.fromMillis(1_000),
  });
});

after(async () => {
  if (live) await cleanup();
});

test("only one concurrent publication attempt owns the draft lease", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(10_000);
  const results = await Promise.allSettled([
    beginOwnerContentDraftPublicationForUser(ownerUserId, {
      draftId,
      attemptId: "attempt_concurrent_0001",
    }, now),
    beginOwnerContentDraftPublicationForUser(ownerUserId, {
      draftId,
      attemptId: "attempt_concurrent_0002",
    }, now),
  ]);

  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  const snapshot = await draftReference.get();
  assert.equal(snapshot.get("state"), "publishing");
  assert.equal(typeof snapshot.get("publicationLeaseId"), "string");
});

test("finalize writes one durable receipt and is idempotent", {skip: !live}, async () => {
  const lease = await beginOwnerContentDraftPublicationForUser(ownerUserId, {
    draftId,
    attemptId: "attempt_finalize_0001",
  }, Timestamp.fromMillis(10_000));
  await contentReference.set({
    id: contentId,
    authorId: ownerUserId,
    organizationId: "organization-1",
    organizationName: "Test Organization",
    moderationStatus: "approved",
  });

  const input = {
    draftId,
    leaseId: lease.leaseId,
    contentId,
    kind: "news" as const,
  };
  const first = await finalizeOwnerContentDraftPublicationForUser(
    ownerUserId,
    input,
    Timestamp.fromMillis(20_000)
  );
  const second = await finalizeOwnerContentDraftPublicationForUser(
    ownerUserId,
    {...input, leaseId: "retry-after-ambiguous-response"},
    Timestamp.fromMillis(30_000)
  );

  assert.deepEqual(first, {finalized: true, state: "completed"});
  assert.deepEqual(second, {finalized: true, state: "completed"});
  const receipt = await draftReference.get();
  assert.equal(receipt.get("state"), "completed");
  assert.equal(receipt.get("publishedContentId"), contentId);
  assert.equal(receipt.get("publishedContentKind"), "news");
  assert.equal(receipt.get("publishedOrganizationId"), "organization-1");
  assert.equal(receipt.get("publicationOutcome"), "approved");
  assert.equal(receipt.get("publicationLeaseId"), undefined);
});

test("a failed attempt releases its lease without inventing content", {skip: !live}, async () => {
  const first = await beginOwnerContentDraftPublicationForUser(ownerUserId, {
    draftId,
    attemptId: "attempt_failure_0001",
  }, Timestamp.fromMillis(10_000));
  await failOwnerContentDraftPublicationForUser(ownerUserId, {
    draftId,
    leaseId: first.leaseId,
    message: "Upload failed",
  }, Timestamp.fromMillis(11_000));

  const retry = await beginOwnerContentDraftPublicationForUser(ownerUserId, {
    draftId,
    attemptId: "attempt_failure_0002",
  }, Timestamp.fromMillis(12_000));

  assert.equal(retry.contentAlreadyExists, false);
  assert.equal(retry.existingModerationStatus, null);
  assert.notEqual(retry.leaseId, first.leaseId);
});

async function cleanup(): Promise<void> {
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(ownerUserId)),
    contentReference.delete(),
  ]);
}
