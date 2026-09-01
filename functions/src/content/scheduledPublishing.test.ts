import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  isCurrentScheduledPlanningLink,
  isScheduledCandidateClaimable,
} from "./scheduledPublishing";

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
  const link = {
    state: "scheduled",
    publishedContentId: "event-1",
    publishedContentKind: "event",
  };
  assert.equal(isCurrentScheduledPlanningLink(link, "events", "event-1"), true);
  assert.equal(isCurrentScheduledPlanningLink({...link, state: "completed"}, "events", "event-1"), false);
  assert.equal(isCurrentScheduledPlanningLink(link, "events", "event-2"), false);
  assert.equal(isCurrentScheduledPlanningLink(link, "news", "event-1"), false);
});
