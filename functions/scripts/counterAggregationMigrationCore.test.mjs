import assert from "node:assert/strict";
import test from "node:test";

import {
  assertCounterCutoverNotFuture,
  boundedChunks,
  classifyCounterBackfillState,
  classifyCounterBaseline,
  classifyCounterDeadLetter,
  counterMigrationBaselineID,
  counterMigrationSourceDescriptor,
  counterMigrationSourceStateID,
  counterTargetFromKey,
  counterTargetKey,
  incrementCounterTargetCount,
  lifetimeViewBaselinePlan,
  parseRfc3339TimestampParts,
  stableReportEnvelope,
} from "./counterAggregationMigrationCore.mjs";

const cutover = {seconds: 2_000, nanoseconds: 123_456_789};

test("migration source mapping covers every production counter source", () => {
  const cases = [
    ["likes/news-like", {newsId: "news-1"}, ["news", "news-1", "likeCount"]],
    ["likes/event-like", {eventId: "event-1"}, ["events", "event-1", "likeCount"]],
    ["likes/org-like", {organizationId: "org-1"}, ["organizations", "org-1", "likeCount"]],
    ["likes/follow", {subscribedOrganizationId: "org-1"}, ["organizations", "org-1", "subscriberCount"]],
    ["registrations/reg-1", {eventId: "event-1", counterManagedAtomically: true}, ["events", "event-1", "registeredCount"]],
    ["news/news-1/comments/comment-1", {parentType: "news", parentId: "news-1"}, ["news", "news-1", "commentCount"]],
    ["events/event-1/comments/comment-1", {parentType: "event", parentId: "event-1"}, ["events", "event-1", "commentCount"]],
    ["users/user-1/newsViews/news-1", {newsId: "news-1", userId: "user-1"}, ["news", "news-1", "viewCount"]],
    ["users/user-1/eventViews/event-1", {eventId: "event-1", userId: "user-1"}, ["events", "event-1", "viewCount"]],
  ];

  for (const [path, data, tuple] of cases) {
    const result = counterMigrationSourceDescriptor(path, data);
    assert.deepEqual(
      [result.target.collection, result.target.documentId, result.target.field],
      tuple
    );
  }
});

test("migration rejects malformed polymorphic and mismatched sources", () => {
  assert.throws(
    () => counterMigrationSourceDescriptor("likes/bad", {
      newsId: "news-1",
      eventId: "event-1",
    }),
    /exactly one/
  );
  assert.throws(
    () => counterMigrationSourceDescriptor(
      "events/event-1/comments/comment-1",
      {parentType: "event", parentId: "event-2"}
    ),
    /canonical path/
  );
  assert.throws(
    () => counterMigrationSourceDescriptor(
      "users/user-1/newsViews/news-1",
      {newsId: "news-2", userId: "user-1"}
    ),
    /canonical path/
  );
});

test("target aggregation is deterministic and explicitly bounded", () => {
  const counts = new Map();
  const key = incrementCounterTargetCount(counts, {
    collection: "news",
    documentId: "news-1",
    field: "likeCount",
  }, 1);
  incrementCounterTargetCount(counts, {
    collection: "news",
    documentId: "news-1",
    field: "likeCount",
  }, 1);
  assert.equal(counts.get(key), 2);
  assert.deepEqual(counterTargetFromKey(key), {
    collection: "news",
    documentId: "news-1",
    field: "likeCount",
  });
  assert.deepEqual(
    counterTargetFromKey('["news"," news-1 ","likeCount"]'),
    {collection: "news", documentId: "news-1", field: "likeCount"}
  );
  assert.throws(
    () => incrementCounterTargetCount(counts, {
      collection: "events",
      documentId: "event-1",
      field: "likeCount",
    }, 1),
    /limit/
  );
});

test("backfill state never overwrites a newer or conflicting generation", () => {
  const desired = {
    schemaVersion: 2,
    sourcePathHash: "hash",
    targetCollection: "events",
    targetDocumentId: "event-1",
    counterField: "registeredCount",
    isActive: true,
    lastEventId: "backfill-v1",
    counterContributionApplied: true,
    counterManagedAtomically: true,
    migrationGeneration: "backfill-v1",
    lastEventTime: cutover,
    lastEventTimeSeconds: cutover.seconds,
    lastEventTimeNanoseconds: cutover.nanoseconds,
  };
  assert.deepEqual(
    classifyCounterBackfillState(undefined, desired, cutover),
    {kind: "create"}
  );
  assert.deepEqual(
    classifyCounterBackfillState({
      ...desired,
      lastEventTimeSeconds: 1_999,
      lastEventTimeNanoseconds: 999_999_999,
    }, desired, cutover),
    {kind: "replace-older"}
  );
  assert.equal(classifyCounterBackfillState({
    ...desired,
    lastEventTimeSeconds: 2_001,
    lastEventTimeNanoseconds: 0,
  }, desired, cutover).reason, "state-newer-than-cutover");
  assert.equal(classifyCounterBackfillState({
    ...desired,
    lastEventId: "other-event",
    lastEventTimeSeconds: cutover.seconds,
    lastEventTimeNanoseconds: cutover.nanoseconds,
  }, desired, cutover).reason, "cutover-event-conflict");
  assert.equal(classifyCounterBackfillState({
    ...desired,
    lastEventTime: undefined,
  }, desired, cutover).reason, "malformed-state-time");
  assert.deepEqual(classifyCounterBackfillState({
    ...desired,
  }, desired, cutover), {kind: "verified"});
});

test("lifetime baseline preserves history and is immutable by identity", () => {
  assert.deepEqual(lifetimeViewBaselinePlan(120, 85), {
    activeMarkerCount: 85,
    legacyCount: 35,
    sourceViewCount: 120,
  });
  assert.throws(() => lifetimeViewBaselinePlan(84, 85), /exceed/);

  const desired = {
    schemaVersion: 2,
    targetCollection: "news",
    targetDocumentId: "news-1",
    counterField: "viewCount",
    legacyCount: 35,
    sourceViewCountAtCutover: 120,
    activeMarkerCountAtCutover: 85,
    migrationGeneration: "backfill-v1",
    cutoverAt: cutover,
    cutoverTimeSeconds: cutover.seconds,
    cutoverTimeNanoseconds: cutover.nanoseconds,
  };
  assert.deepEqual(classifyCounterBaseline(undefined, desired), {kind: "create"});
  assert.deepEqual(classifyCounterBaseline(desired, desired), {kind: "verified"});
  assert.equal(classifyCounterBaseline({...desired, legacyCount: 36}, desired).kind, "conflict");
});

test("report digest and page chunks are stable", () => {
  const first = stableReportEnvelope({b: 2, a: {z: 3, y: 4}});
  const second = stableReportEnvelope({a: {y: 4, z: 3}, b: 2});
  assert.equal(first.reportDigestSha256, second.reportDigestSha256);
  assert.equal(
    stableReportEnvelope({a: 1, omitted: undefined}).reportDigestSha256,
    stableReportEnvelope({a: 1}).reportDigestSha256
  );
  assert.equal("omitted" in stableReportEnvelope({a: 1, omitted: undefined}), false);
  assert.match(first.reportDigestSha256, /^[a-f0-9]{64}$/);
  assert.deepEqual(boundedChunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
  assert.equal(
    counterMigrationSourceStateID("/likes/like-1/"),
    "6307fad27fb296e0a8bdd1f8bb846384caaaad0ee50fb69006ccef536a4fb846"
  );
  assert.equal(
    counterMigrationBaselineID("news", "news-1", "viewCount"),
    "a0e4ef12316811ab2e8dad505a3ef029d32e6ff4c83f6ce36bd04992db4ab83f"
  );
  assert.equal(
    counterMigrationBaselineID("news", " news-1 ", "viewCount"),
    counterMigrationBaselineID("news", "news-1", "viewCount")
  );
  assert.deepEqual(
    parseRfc3339TimestampParts("2026-08-24T12:00:00.123456789+02:00"),
    {
      seconds: Math.floor(Date.parse("2026-08-24T10:00:00Z") / 1_000),
      nanoseconds: 123_456_789,
    }
  );
});

test("cutover and dead-letter release gates require current, complete evidence", () => {
  assert.doesNotThrow(() => assertCounterCutoverNotFuture(
    {seconds: 2_000, nanoseconds: 123_456_789},
    2_001_000
  ));
  assert.throws(() => assertCounterCutoverNotFuture(
    {seconds: 2_001, nanoseconds: 1},
    2_001_000
  ), /future/);

  assert.deepEqual(classifyCounterDeadLetter({resolutionStatus: "unresolved"}), {
    kind: "unresolved",
  });
  assert.deepEqual(classifyCounterDeadLetter({
    resolutionStatus: "resolved",
    resolvedAt: {seconds: 2_000, nanoseconds: 0},
    resolvedBy: "operator-1",
    resolutionReason: "reconciled against authoritative source",
    resolutionTicket: "INC-1",
  }), {kind: "resolved"});
  assert.equal(classifyCounterDeadLetter({
    resolutionStatus: "resolved",
    resolvedAt: {seconds: 2_000, nanoseconds: 0},
    resolvedBy: "operator-1",
  }).kind, "invalid");
});
