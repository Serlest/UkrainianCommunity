import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  dailyDocumentIDFor,
  datedAnalyticsDocumentIDs,
} from "./analyticsDate";

test("analytics document IDs use the Europe/Vienna calendar day", () => {
  assert.equal(
    dailyDocumentIDFor(new Date("2026-08-24T22:30:00.000Z")),
    "2026-08-25"
  );
  assert.equal(
    dailyDocumentIDFor(new Date("2026-01-01T00:30:00.000Z")),
    "2026-01-01"
  );
});

test("dated analytics windows stay contiguous across daylight saving changes", () => {
  assert.deepEqual(
    datedAnalyticsDocumentIDs(4, new Date("2026-03-30T00:30:00.000Z")),
    ["2026-03-30", "2026-03-29", "2026-03-28", "2026-03-27"]
  );
  assert.deepEqual(
    datedAnalyticsDocumentIDs(4, new Date("2026-10-26T00:30:00.000Z")),
    ["2026-10-26", "2026-10-25", "2026-10-24", "2026-10-23"]
  );
});
