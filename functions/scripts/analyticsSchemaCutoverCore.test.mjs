import assert from "node:assert/strict";
import test from "node:test";

import {
  analyticsCutoverDayID,
  analyticsCutoverWindowDayIDs,
  analyticsCutoverDigest,
  analyticsDailyDeltasFromCumulative,
  assertDeployedCommit,
  assertSafeAnalyticsCutoverGeneration,
  datedLegacySnapshotData,
  isDrainWindowSatisfied,
  isValidAnalyticsDetailCoverage,
  normalizedAnalyticsSchemaState,
} from "./analyticsSchemaCutoverCore.mjs";

test("Vienna cutover day follows local midnight and DST", () => {
  assert.equal(analyticsCutoverDayID(new Date("2026-03-28T23:30:00Z")), "2026-03-29");
  assert.equal(analyticsCutoverDayID(new Date("2026-10-24T22:30:00Z")), "2026-10-25");
  assert.deepEqual(
    analyticsCutoverWindowDayIDs(4, new Date("2026-03-30T00:30:00Z")),
    ["2026-03-30", "2026-03-29", "2026-03-28", "2026-03-27"]
  );
});

test("cutover identifiers are bounded and explicit", () => {
  assert.equal(
    assertSafeAnalyticsCutoverGeneration("analytics-v2-20260824"),
    "analytics-v2-20260824"
  );
  assert.equal(
    assertDeployedCommit("ABCDEF1234567890ABCDEF1234567890ABCDEF12"),
    "abcdef1234567890abcdef1234567890abcdef12"
  );
  assert.throws(() => assertDeployedCommit("abcdef1234567"));
  assert.throws(() => assertSafeAnalyticsCutoverGeneration("../bad"));
  assert.throws(() => assertDeployedCommit("main"));
});

test("legacy live snapshot becomes one authoritative dated snapshot", () => {
  const result = datedLegacySnapshotData({
    dateDocumentID: "2026-08-24",
    itemsByKey: {news_a: {viewCount: 5}},
    sourceDocumentIDs: ["wrong"],
    updatedAt: "old",
  }, "2026-08-24", "analytics-v2-20260824", "server-now");
  assert.deepEqual(result, {
    dateDocumentID: "2026-08-24",
    itemsByKey: {news_a: {viewCount: 5}},
    updatedAt: "server-now",
    sourceDocumentID: "today",
    snapshotDocumentID: "2026-08-24",
    schemaVersion: 2,
    cutoverGeneration: "analytics-v2-20260824",
  });
});

test("digest is stable across record and object key order", () => {
  const left = analyticsCutoverDigest([
    {path: "b", data: {z: 2, a: 1}},
    {path: "a", data: {value: true}},
  ]);
  const right = analyticsCutoverDigest([
    {path: "a", data: {value: true}},
    {path: "b", data: {a: 1, z: 2}},
  ]);
  assert.equal(left, right);
  assert.match(left, /^[a-f0-9]{64}$/);
});

test("gate state and drain window fail closed", () => {
  assert.equal(normalizedAnalyticsSchemaState(undefined), undefined);
  assert.equal(normalizedAnalyticsSchemaState({
    schemaVersion: 2,
    status: "prepared",
    generation: "analytics-v2-20260824",
    cutoverDay: "2026-08-24",
  })?.status, "prepared");
  assert.equal(normalizedAnalyticsSchemaState({
    schemaVersion: 2,
    status: "finalizing",
    generation: "analytics-v2-20260824",
    cutoverDay: "2026-08-24",
  })?.status, "finalizing");
  assert.equal(normalizedAnalyticsSchemaState({
    schemaVersion: 2,
    status: "aborted",
    generation: "analytics-v2-20260824",
    cutoverDay: "2026-08-24",
  })?.status, "aborted");
  assert.equal(normalizedAnalyticsSchemaState({
    schemaVersion: 2,
    status: "bypassed",
    generation: "analytics-v2-20260824",
    cutoverDay: "2026-08-24",
  }), undefined);
  const deployedAt = new Date("2026-08-24T10:00:00Z");
  assert.equal(
    isDrainWindowSatisfied(new Date("2026-08-24T10:09:59Z"), deployedAt, 600),
    false
  );
  assert.equal(
    isDrainWindowSatisfied(new Date("2026-08-24T10:10:00Z"), deployedAt, 600),
    true
  );
});

test("detail coverage proves the exact contiguous v2 source window", () => {
  const valid = {
    periodId: "seven_days",
    sourceDocumentIDs: [
      "2026-08-24",
      "2026-08-23",
      "2026-08-22",
      "2026-08-21",
      "2026-08-20",
      "2026-08-19",
      "2026-08-18",
    ],
    coverageStartDay: "2026-08-22",
    coveredSourceDocumentIDs: ["2026-08-24", "2026-08-23", "2026-08-22"],
    isPartialCoverage: true,
  };
  assert.equal(
    isValidAnalyticsDetailCoverage(valid, "seven_days", 7, "2026-08-22"),
    true
  );
  assert.equal(
    isValidAnalyticsDetailCoverage({
      ...valid,
      sourceDocumentIDs: [
        "2026-08-24",
        "2026-08-22",
        "2026-08-23",
        "2026-08-21",
        "2026-08-20",
        "2026-08-19",
        "2026-08-18",
      ],
    }, "seven_days", 7, "2026-08-22"),
    false
  );
  assert.equal(
    isValidAnalyticsDetailCoverage({
      ...valid,
      isPartialCoverage: false,
    }, "seven_days", 7, "2026-08-22"),
    false
  );
});

test("legacy cumulative deletions become exact daily increments", () => {
  assert.deepEqual(
    analyticsDailyDeltasFromCumulative([2, 2, 3, 3, 6]),
    [0, 1, 0, 3]
  );
  assert.throws(
    () => analyticsDailyDeltasFromCumulative([2, 1]),
    /decreased/
  );
  assert.throws(
    () => analyticsDailyDeltasFromCumulative([0, Number.NaN]),
    /safe integers/
  );
});
