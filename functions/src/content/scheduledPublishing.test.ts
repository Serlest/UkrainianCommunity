import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  completedPlanningUpdate,
  isActivePlanningPublication,
  isCurrentScheduledPlanningLink,
  isScheduledCandidateClaimable,
  processScheduledCandidateIds,
} from "./scheduledPublishing";

test("completed planning receipts receive media cleanup and six-month retention", () => {
  const now = Timestamp.fromDate(new Date("2026-08-31T10:00:00.000Z"));
  const update = completedPlanningUpdate({
    now,
    outcome: "approved",
    contentId: "news-1",
    kind: "news",
    organizationId: "organization-1",
    organizationName: "Organization",
  });

  assert.equal(update.draftMediaCleanupStatus, "pending");
  assert.equal(update.draftMediaCleanupRequestedAt, now);
  assert.equal(update.retentionPolicy, "contentPlanningReceipt6Months");
  assert.equal(
    (update.retentionExpiresAt as Timestamp).toDate().toISOString(),
    "2027-02-28T10:00:00.000Z"
  );
});

test("claims only due drafts without an active lease", () => {
  const now = Timestamp.fromMillis(10_000);
  const due = {moderationStatus: "draft", scheduledAt: Timestamp.fromMillis(9_000)};
  assert.equal(isScheduledCandidateClaimable(due, undefined, now), true);
  assert.equal(
    isScheduledCandidateClaimable(due, Timestamp.fromMillis(11_000), now),
    false
  );
  assert.equal(
    isScheduledCandidateClaimable(
      {moderationStatus: "draft", scheduledAt: Timestamp.fromMillis(12_000)},
      undefined,
      now
    ),
    false
  );
  assert.equal(
    isScheduledCandidateClaimable(
      {moderationStatus: "approved", scheduledAt: Timestamp.fromMillis(9_000)},
      undefined,
      now
    ),
    false
  );
});

test("accepts only the exact scheduled planning link", () => {
  const scheduledAt = Timestamp.fromMillis(9_000);
  const link = {
    state: "scheduled",
    publishedContentId: "event-1",
    publishedContentKind: "event",
    scheduledAt,
  };
  assert.equal(isCurrentScheduledPlanningLink(link, "events", "event-1", scheduledAt), true);
  assert.equal(
    isCurrentScheduledPlanningLink({...link, state: "completed"}, "events", "event-1", scheduledAt),
    false
  );
  assert.equal(isCurrentScheduledPlanningLink(link, "events", "event-2", scheduledAt), false);
  assert.equal(isCurrentScheduledPlanningLink(link, "news", "event-1", scheduledAt), false);
  assert.equal(
    isCurrentScheduledPlanningLink(
      {...link, scheduledAt: Timestamp.fromMillis(10_001)},
      "events",
      "event-1",
      scheduledAt
    ),
    false
  );
});

test("recognizes only an unexpired owner publication lease as active", () => {
  const now = Timestamp.fromMillis(10_000);
  const publishing = {
    state: "publishing",
    publicationLeaseId: "lease-1",
    publicationLeaseExpiresAt: Timestamp.fromMillis(11_000),
  };
  assert.equal(isActivePlanningPublication(publishing, now), true);
  assert.equal(
    isActivePlanningPublication(
      {...publishing, publicationLeaseExpiresAt: Timestamp.fromMillis(10_000)},
      now
    ),
    false
  );
  assert.equal(isActivePlanningPublication({...publishing, state: "scheduled"}, now), false);
  assert.equal(isActivePlanningPublication({...publishing, publicationLeaseId: ""}, now), false);
});

test("a failed candidate does not block the rest of the batch", async () => {
  const calls: string[] = [];
  const result = await processScheduledCandidateIds(
    "news",
    ["broken", "approved", "review", "skipped"],
    Timestamp.fromMillis(10_000),
    async (_collection, documentId) => {
      calls.push(documentId);
      if (documentId === "broken") throw new Error("simulated candidate failure");
      if (documentId === "approved") return "approved";
      if (documentId === "review") return "pendingReview";
      return "skipped";
    }
  );

  assert.deepEqual(calls, ["broken", "approved", "review", "skipped"]);
  assert.deepEqual(result, {published: 1, review: 1, skipped: 1, failed: 1});
});
