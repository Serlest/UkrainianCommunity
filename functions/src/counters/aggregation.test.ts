import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  type CounterSourceTransitionState,
  counterEventTimestamp,
  counterLikeTarget,
  counterSourceStateDocumentId,
  counterTargetBaselineDocumentId,
  counterValueAfterTransition,
  decideCounterContribution,
  decideCounterSourceTransition,
  duplicateNeedsContributionRecovery,
  lifetimeViewLegacyBaseline,
} from "./aggregation";

test("like counter routing requires exactly one valid canonical target", () => {
  assert.deepEqual(counterLikeTarget({newsId: " news-1 "}), {
    collection: "news",
    documentId: "news-1",
    field: "likeCount",
  });
  assert.deepEqual(counterLikeTarget({subscribedOrganizationId: "org-1"}), {
    collection: "organizations",
    documentId: "org-1",
    field: "subscriberCount",
  });
  assert.throws(() => counterLikeTarget({}), /exactly one/);
  assert.throws(
    () => counterLikeTarget({newsId: "news-1", eventId: "event-1"}),
    /exactly one/
  );
  assert.throws(() => counterLikeTarget({newsId: "bad/id"}), /document ID/);
});

function transition(
  isActive: boolean,
  eventTimeMilliseconds: number,
  eventId: string
): CounterSourceTransitionState {
  const eventTimeSeconds = Math.floor(eventTimeMilliseconds / 1_000);
  return {
    isActive,
    eventId,
    eventTimeNanoseconds:
      (eventTimeMilliseconds - eventTimeSeconds * 1_000) * 1_000_000,
    eventTimeSeconds,
  };
}

function transitionAt(
  isActive: boolean,
  eventTimeSeconds: number,
  eventTimeNanoseconds: number,
  eventId: string
): CounterSourceTransitionState {
  return {isActive, eventId, eventTimeNanoseconds, eventTimeSeconds};
}

test("duplicate counter events do not apply the transition twice", () => {
  const create = transition(true, 1_000, "create-1");
  const first = decideCounterSourceTransition(undefined, create);
  assert.equal(first.shouldPersistState, true);
  assert.equal(first.counterDelta, 1);

  const duplicate = decideCounterSourceTransition(first.nextState, create);
  assert.equal(duplicate.shouldPersistState, false);
  assert.equal(duplicate.counterDelta, 0);
  assert.equal(duplicate.eventOrder, "duplicate");
  assert.deepEqual(duplicate.nextState, first.nextState);
});

test("delete delivered before its older create leaves the source inactive", () => {
  const deletion = decideCounterSourceTransition(
    undefined,
    transition(false, 2_000, "delete-2")
  );
  assert.equal(deletion.shouldPersistState, true);
  assert.equal(deletion.counterDelta, 0);
  assert.equal(deletion.nextState.isActive, false);

  const olderCreate = decideCounterSourceTransition(
    deletion.nextState,
    transition(true, 1_000, "create-1")
  );
  assert.equal(olderCreate.shouldPersistState, false);
  assert.equal(olderCreate.counterDelta, 0);
  assert.equal(olderCreate.eventOrder, "older");
  assert.equal(olderCreate.nextState.isActive, false);
});

test("atomic registration contribution is removed when delete arrives before create state", () => {
  const deletion = decideCounterSourceTransition(
    undefined,
    transition(false, 2_000, "delete-account-cleanup"),
    true
  );
  assert.equal(deletion.shouldPersistState, true);
  assert.equal(deletion.counterDelta, -1);
  assert.equal(deletion.nextState.isActive, false);
  assert.deepEqual(decideCounterContribution(true, false, true, false), {
    counterDelta: -1,
    nextContributionApplied: false,
    shouldWriteCounter: true,
  });

  const delayedCreate = decideCounterSourceTransition(
    deletion.nextState,
    transition(true, 1_000, "create-callable")
  );
  assert.equal(delayedCreate.shouldPersistState, false);
  assert.equal(delayedCreate.counterDelta, 0);
});

test("new atomic lifecycle overrides an older inactive tombstone contribution", () => {
  const oldInactiveTombstone = transition(false, 500, "old-delete");
  const newDeletion = decideCounterSourceTransition(
    oldInactiveTombstone,
    transition(false, 2_000, "new-delete-before-create"),
    true
  );
  assert.equal(newDeletion.eventOrder, "newer");
  assert.equal(newDeletion.counterDelta, -1);

  const storedContribution = false;
  const initialContributionProof = true;
  const effectiveContribution = storedContribution || initialContributionProof;
  assert.deepEqual(
    decideCounterContribution(effectiveContribution, false, true, false),
    {
      counterDelta: -1,
      nextContributionApplied: false,
      shouldWriteCounter: true,
    }
  );

  const delayedCreate = decideCounterSourceTransition(
    newDeletion.nextState,
    transition(true, 1_000, "new-create-delayed")
  );
  assert.equal(delayedCreate.eventOrder, "older");
  assert.equal(delayedCreate.counterDelta, 0);
});

test("ordered create then delete increments and decrements exactly once", () => {
  const create = decideCounterSourceTransition(
    undefined,
    transition(true, 1_000, "create-1")
  );
  const deletion = decideCounterSourceTransition(
    create.nextState,
    transition(false, 2_000, "delete-2")
  );

  assert.equal(create.counterDelta, 1);
  assert.equal(deletion.counterDelta, -1);
  assert.equal(deletion.shouldPersistState, true);
  assert.equal(deletion.nextState.isActive, false);
});

test("a newer recreation transitions an inactive source back to active", () => {
  const create = decideCounterSourceTransition(
    undefined,
    transition(true, 1_000, "create-1")
  );
  const deletion = decideCounterSourceTransition(
    create.nextState,
    transition(false, 2_000, "delete-2")
  );
  const recreation = decideCounterSourceTransition(
    deletion.nextState,
    transition(true, 3_000, "create-3")
  );

  assert.equal(recreation.shouldPersistState, true);
  assert.equal(recreation.counterDelta, 1);
  assert.equal(recreation.nextState.isActive, true);
  assert.equal(recreation.nextState.eventId, "create-3");
});

test("equal timestamps with different event IDs are quarantinable conflicts", () => {
  const first = transition(true, 1_000, "event-a");
  const conflict = decideCounterSourceTransition(
    first,
    transition(false, 1_000, "event-b")
  );

  assert.equal(conflict.eventOrder, "conflict");
  assert.equal(conflict.shouldPersistState, false);
  assert.equal(conflict.counterDelta, 0);
  assert.deepEqual(conflict.nextState, first);
});

test("the same event ID with a changed timestamp is an identity conflict", () => {
  const first = transition(true, 1_000, "event-1");
  const conflict = decideCounterSourceTransition(
    first,
    transition(true, 2_000, "event-1")
  );

  assert.equal(conflict.eventOrder, "conflict");
  assert.equal(conflict.shouldPersistState, false);
  assert.equal(conflict.counterDelta, 0);
  assert.deepEqual(conflict.nextState, first);
});

test("events within one millisecond retain nanosecond ordering independent of ID", () => {
  const first = transitionAt(true, 1_777_000_000, 123_000_100, "event-z");
  const later = transitionAt(false, 1_777_000_000, 123_000_900, "event-a");
  const accepted = decideCounterSourceTransition(first, later);

  assert.equal(accepted.eventOrder, "newer");
  assert.equal(accepted.shouldPersistState, true);
  assert.equal(accepted.counterDelta, -1);
  assert.deepEqual(accepted.nextState, later);
});

test("RFC3339 CloudEvent times preserve all nine fractional digits", () => {
  const earlier = counterEventTimestamp("2026-08-24T10:00:00.123000100Z");
  const later = counterEventTimestamp("2026-08-24T10:00:00.123000900Z");
  const sameInstantWithOffset = counterEventTimestamp(
    "2026-08-24T12:00:00.123000100+02:00"
  );

  assert.equal(earlier.seconds, later.seconds);
  assert.equal(earlier.nanoseconds, 123_000_100);
  assert.equal(later.nanoseconds, 123_000_900);
  assert.deepEqual(sameInstantWithOffset, earlier);
  assert.throws(
    () => counterEventTimestamp("2026-08-24T10:00:00.1234567890Z"),
    /RFC3339/
  );
  assert.throws(
    () => counterEventTimestamp("2026-02-30T10:00:00Z"),
    /invalid/
  );
});

test("source-state document IDs are normalized deterministic SHA-256 hashes", () => {
  const canonical = counterSourceStateDocumentId("likes/like-1");
  assert.equal(
    canonical,
    "6307fad27fb296e0a8bdd1f8bb846384caaaad0ee50fb69006ccef536a4fb846"
  );
  assert.equal(counterSourceStateDocumentId("/likes/like-1/"), canonical);
  assert.match(canonical, /^[a-f0-9]{64}$/);
  assert.notEqual(counterSourceStateDocumentId("likes/like-2"), canonical);
});

test("lifetime view baseline IDs are deterministic per target counter", () => {
  const canonical = counterTargetBaselineDocumentId("news", "news-1", "viewCount");
  assert.equal(
    canonical,
    "a0e4ef12316811ab2e8dad505a3ef029d32e6ff4c83f6ce36bd04992db4ab83f"
  );
  assert.match(canonical, /^[a-f0-9]{64}$/);
  assert.equal(
    counterTargetBaselineDocumentId("news", "news-1", "viewCount"),
    canonical
  );
  assert.notEqual(
    counterTargetBaselineDocumentId("events", "news-1", "viewCount"),
    canonical
  );
});

test("lifetime view baseline preserves deleted historical markers without a reset", () => {
  assert.equal(lifetimeViewLegacyBaseline(120, 85), 35);
  assert.equal(lifetimeViewLegacyBaseline(0, 0), 0);
  assert.throws(
    () => lifetimeViewLegacyBaseline(84, 85),
    /markers exceed/
  );
  assert.throws(
    () => lifetimeViewLegacyBaseline(1.5, 1),
    /non-negative integers/
  );
});

test("missing targets record no contribution and atomic transitions never write twice", () => {
  assert.deepEqual(decideCounterContribution(false, true, false, false), {
    counterDelta: 0,
    nextContributionApplied: false,
    shouldWriteCounter: false,
  });
  assert.deepEqual(decideCounterContribution(false, true, true, false), {
    counterDelta: 1,
    nextContributionApplied: true,
    shouldWriteCounter: true,
  });
  assert.deepEqual(decideCounterContribution(true, false, false, true), {
    counterDelta: -1,
    nextContributionApplied: false,
    shouldWriteCounter: false,
  });
});

test("an exact duplicate can recover an active missing-target contribution", () => {
  const activeWithoutContribution = transition(true, 1_000, "create-1");
  const duplicate = decideCounterSourceTransition(
    activeWithoutContribution,
    activeWithoutContribution
  );
  assert.equal(duplicateNeedsContributionRecovery(duplicate, false), true);
  assert.deepEqual(decideCounterContribution(false, true, true, false), {
    counterDelta: 1,
    nextContributionApplied: true,
    shouldWriteCounter: true,
  });
  assert.equal(duplicateNeedsContributionRecovery(duplicate, true), false);
});

test("counter transitions clamp invalid and negative values at zero", () => {
  assert.equal(counterValueAfterTransition(0, -1), 0);
  assert.equal(counterValueAfterTransition(-10, -1), 0);
  assert.equal(counterValueAfterTransition(Number.NaN, -1), 0);
  assert.equal(counterValueAfterTransition(4, -1), 3);
  assert.equal(counterValueAfterTransition(4, 1), 5);
});
