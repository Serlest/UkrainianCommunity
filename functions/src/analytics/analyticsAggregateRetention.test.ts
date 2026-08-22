import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  dateFromDocumentID,
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
  const cutoff = new Date("2026-06-01T00:00:00.000Z");

  assert.equal(shouldDeleteAggregateDocument("2026-05-31", cutoff), true);
  assert.equal(shouldDeleteAggregateDocument("2026-06-01", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("today", cutoff), false);
  assert.equal(shouldDeleteAggregateDocument("unexpected", cutoff), false);
});
