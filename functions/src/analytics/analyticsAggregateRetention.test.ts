import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  aggregateRetentionCutoffDocumentID,
  dateFromDocumentID,
  planAggregateCleanupPage,
  shouldDeleteAggregateDocument,
} from "./analyticsAggregateRetention";

test("dated aggregate IDs use the YYYY-MM-DD contract", () => {
  assert.equal(
    dateFromDocumentID("2026-06-01")?.toISOString(),
    "2026-06-01T00:00:00.000Z",
  );
  assert.equal(dateFromDocumentID("2026-02-31"), undefined);
  assert.equal(dateFromDocumentID("today"), undefined);
});

test("aggregate cleanup deletes only dated documents older than the cutoff", () => {
  const cutoff = "2026-06-01";

  assert.equal(shouldDeleteAggregateDocument("2026-05-31", cutoff), true);
  assert.equal(shouldDeleteAggregateDocument("2026-06-01", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("2026-06-02", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("today", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("unexpected", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("2026-05-31", "invalid"), false);
});

test("aggregate retention uses Vienna calendar days across DST boundaries", () => {
  assert.equal(
    aggregateRetentionCutoffDocumentID(
      new Date("2026-03-29T22:30:00.000Z"),
      2,
    ),
    "2026-03-29",
  );
  assert.equal(
    aggregateRetentionCutoffDocumentID(
      new Date("2026-10-25T23:30:00.000Z"),
      2,
    ),
    "2026-10-25",
  );
});

test("aggregate retention rejects ambiguous retention values", () => {
  assert.throws(
    () => aggregateRetentionCutoffDocumentID(new Date(), 0),
    RangeError,
  );
  assert.throws(
    () => aggregateRetentionCutoffDocumentID(new Date(), -1),
    RangeError,
  );
  assert.throws(
    () => aggregateRetentionCutoffDocumentID(new Date(), 1.5),
    RangeError,
  );
});

test("aggregate cleanup page uses bounded look-ahead pagination", () => {
  assert.deepEqual(
    planAggregateCleanupPage(["a", "b", "c"], 2),
    {
      documentIDsToInspect: ["a", "b"],
      nextCursor: "b",
    },
  );
  assert.deepEqual(
    planAggregateCleanupPage(["c", "d"], 2),
    {
      documentIDsToInspect: ["c", "d"],
      nextCursor: undefined,
    },
  );
  assert.deepEqual(
    planAggregateCleanupPage([], 2),
    {
      documentIDsToInspect: [],
      nextCursor: undefined,
    },
  );
  assert.throws(() => planAggregateCleanupPage(["a"], 0), RangeError);
});

test("persistent page cursors advance past an entire run of preserved roots", () => {
  const orderedDocumentIDs = [
    ...Array.from(
      {length: 260},
      (_, index) => `000-invalid-${index.toString().padStart(3, "0")}`,
    ),
    "2026-01-01",
    "today",
  ];
  const inspected = new Set<string>();
  let cursor: string | undefined;

  for (let run = 0; run < 2; run += 1) {
    for (let page = 0; page < 4; page += 1) {
      const remaining = orderedDocumentIDs.filter(
        (documentID) => cursor === undefined || documentID > cursor,
      );
      const plan = planAggregateCleanupPage(remaining.slice(0, 51), 50);
      plan.documentIDsToInspect.forEach((documentID) => inspected.add(documentID));
      cursor = plan.nextCursor;
      if (cursor === undefined) {
        break;
      }
    }
  }

  assert.equal(inspected.has("2026-01-01"), true);
  assert.equal(
    shouldDeleteAggregateDocument("2026-01-01", "2026-06-26"),
    true,
  );
});
