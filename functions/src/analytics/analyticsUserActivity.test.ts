import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  analyticsActivityLookupBatchSize,
  analyticsActivityExpirationDate,
  analyticsActivityWindowIndex,
  analyticsActivityWindows,
  analyticsMaterializationPageSize,
  analyticsRegistrationFallbackLimit,
  analyticsUserActivityRetentionDays,
  boundedAnalyticsBatches,
  isAnalyticsLifecycleEventAfterCoverage,
  latestAnalyticsActivityDate,
  nextAnalyticsScanCursor,
  setBoundedAnalyticsRegistrationFallback,
  shouldUseAnalyticsRegistrationFallback,
} from "./analyticsUserActivity";

test("analytics activity uses the Vienna day and trailing windows", () => {
  const now = new Date("2026-08-24T22:30:00.000Z");
  assert.deepEqual(
    analyticsActivityWindows(
      new Date("2026-08-24T22:05:00.000Z"),
      now
    ),
    {today: true, sevenDays: true, thirtyDays: true}
  );
  assert.deepEqual(
    analyticsActivityWindows(
      new Date("2026-07-20T12:00:00.000Z"),
      now
    ),
    {today: false, sevenDays: false, thirtyDays: false}
  );
});

test("activity timestamps move forward but never regress on delayed delivery", () => {
  const current = new Date("2026-08-24T10:00:00.000Z");
  const delayed = new Date("2026-08-23T10:00:00.000Z");
  const newer = new Date("2026-08-24T11:00:00.000Z");

  assert.equal(
    latestAnalyticsActivityDate(current, delayed).toISOString(),
    current.toISOString()
  );
  assert.equal(
    latestAnalyticsActivityDate(current, newer).toISOString(),
    newer.toISOString()
  );
  assert.equal(
    latestAnalyticsActivityDate(undefined, delayed).toISOString(),
    delayed.toISOString()
  );
});

test("analytics activity expires after the aggregate retention window", () => {
  const now = new Date("2026-08-24T12:00:00.000Z");
  assert.equal(analyticsUserActivityRetentionDays, 60);
  assert.equal(
    analyticsActivityExpirationDate(now).toISOString(),
    "2026-10-23T12:00:00.000Z"
  );
});

test("one immutable window index serves every user in a materialization run", () => {
  const now = new Date("2026-08-24T22:30:00.000Z");
  const windowIndex = analyticsActivityWindowIndex(now);

  assert.equal(windowIndex.todayDocumentID, "2026-08-25");
  assert.equal(windowIndex.sevenDayDocumentIDs.length, 7);
  assert.equal(windowIndex.thirtyDayDocumentIDs.length, 30);
  assert.deepEqual(
    analyticsActivityWindows(
      new Date("2026-08-19T12:00:00.000Z"),
      now,
      windowIndex
    ),
    {today: false, sevenDays: true, thirtyDays: true}
  );
  assert.deepEqual(
    analyticsActivityWindows(
      new Date("2026-08-01T12:00:00.000Z"),
      now,
      windowIndex
    ),
    {today: false, sevenDays: false, thirtyDays: true}
  );
});

test("large exact-document lookups stay complete and bounded", () => {
  const userIDs = Array.from({length: 10_003}, (_, index) =>
    `user-${index.toString().padStart(5, "0")}`
  );
  const batches = boundedAnalyticsBatches(
    userIDs,
    analyticsActivityLookupBatchSize
  );

  assert.equal(batches.flat().length, userIDs.length);
  assert.deepEqual(batches.flat(), userIDs);
  assert.ok(batches.every((batch) =>
    batch.length > 0 && batch.length <= analyticsActivityLookupBatchSize
  ));
  assert.equal(batches.at(-1)?.length, 3);
});

test("deterministic scan pagination advances only after full pages", () => {
  const fullPage = Array.from({length: analyticsMaterializationPageSize},
    (_, index) => `document-${index.toString().padStart(4, "0")}`
  );

  assert.equal(
    nextAnalyticsScanCursor(fullPage, analyticsMaterializationPageSize),
    fullPage.at(-1)
  );
  assert.equal(
    nextAnalyticsScanCursor(
      fullPage.slice(0, analyticsMaterializationPageSize - 1),
      analyticsMaterializationPageSize
    ),
    undefined
  );
  assert.throws(() => nextAnalyticsScanCursor(fullPage, 0), RangeError);
  assert.throws(() => nextAnalyticsScanCursor(
    [...fullPage, "overflow"],
    analyticsMaterializationPageSize
  ), RangeError);
});

test("registration fallback accumulation has an explicit memory bound", () => {
  const fallbacks = new Map<string, string>();
  setBoundedAnalyticsRegistrationFallback(fallbacks, "user-a", "2026-08-24", 2);
  setBoundedAnalyticsRegistrationFallback(fallbacks, "user-b", "2026-08-24", 2);
  setBoundedAnalyticsRegistrationFallback(fallbacks, "user-a", "2026-08-25", 2);
  assert.equal(fallbacks.size, 2);
  assert.equal(fallbacks.get("user-a"), "2026-08-25");
  assert.throws(
    () => setBoundedAnalyticsRegistrationFallback(
      fallbacks,
      "user-c",
      "2026-08-24",
      2
    ),
    /limit 2 exceeded/
  );
  assert.equal(analyticsRegistrationFallbackLimit, 100_000);
});

test("lifecycle coverage splits fallback and ledger events at one exact instant", () => {
  const windowIndex = analyticsActivityWindowIndex(
    new Date("2026-08-24T12:00:00.000Z")
  );
  const coverage = new Map([
    ["2026-08-20", new Date("2026-08-20T10:00:00.000Z")],
  ]);
  assert.equal(shouldUseAnalyticsRegistrationFallback(
    "2026-08-20",
    new Date("2026-08-20T10:00:00.000Z"),
    windowIndex,
    coverage
  ), false);
  assert.equal(shouldUseAnalyticsRegistrationFallback(
    "2026-08-20",
    new Date("2026-08-20T10:00:00.001Z"),
    windowIndex,
    coverage
  ), true);
  assert.equal(shouldUseAnalyticsRegistrationFallback(
    "2026-08-19",
    new Date("2026-08-19T10:00:00.000Z"),
    windowIndex,
    coverage
  ), true);
  assert.equal(shouldUseAnalyticsRegistrationFallback(
    "2026-07-01",
    new Date("2026-07-01T10:00:00.000Z"),
    windowIndex,
    coverage
  ), false);

  assert.equal(isAnalyticsLifecycleEventAfterCoverage(
    "2026-08-20",
    new Date("2026-08-20T09:59:59.999Z"),
    coverage
  ), false);
  assert.equal(isAnalyticsLifecycleEventAfterCoverage(
    "2026-08-20",
    new Date("2026-08-20T10:00:00.000Z"),
    coverage
  ), false);
  assert.equal(isAnalyticsLifecycleEventAfterCoverage(
    "2026-08-20",
    new Date("2026-08-20T10:00:00.001Z"),
    coverage
  ), true);
  assert.equal(isAnalyticsLifecycleEventAfterCoverage(
    "2026-08-19",
    new Date("2026-08-19T10:00:00.000Z"),
    coverage
  ), true);
});
