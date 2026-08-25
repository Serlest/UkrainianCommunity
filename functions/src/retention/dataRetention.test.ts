import { strict as assert } from "node:assert";
import { test } from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  analyticsUserActivityRetentionDays,
} from "../analytics/analyticsUserActivity";
import {
  analyticsRateLimitRetentionHours,
  analyticsReceiptRetentionHours,
} from "../analytics/analyticsEventGuard";
import {
  analyticsCleanupPageSize,
  auditLogRetentionDays,
  closedFeedbackRetentionMonths,
  contentRetentionMonths,
  isExpiredAnalyticsMarker,
  maxAnalyticsCleanupPagesPerRun,
  subtractUtcDays,
  subtractUtcMonths,
  systemLogRetentionDays,
} from "./dataRetention";

test("content retention is six calendar months", () => {
  assert.equal(contentRetentionMonths, 6);
  assert.equal(closedFeedbackRetentionMonths, 6);
  assert.equal(
    subtractUtcMonths(new Date("2026-08-31T12:30:00.000Z"), 6).toISOString(),
    "2026-02-28T12:30:00.000Z",
  );
  assert.equal(
    subtractUtcMonths(new Date("2024-08-31T12:30:00.000Z"), 6).toISOString(),
    "2024-02-29T12:30:00.000Z",
  );
});

test("analytics guard retention remains short-lived", () => {
  // Receipts must outlive the accepted 48-hour delivery horizon so a delayed
  // retry cannot be replayed after the first receipt has already expired.
  assert.equal(analyticsReceiptRetentionHours, 72);
  assert.equal(analyticsRateLimitRetentionHours, 2);
  assert.equal(analyticsUserActivityRetentionDays, 60);
  assert.equal(analyticsCleanupPageSize, 500);
  assert.equal(maxAnalyticsCleanupPagesPerRun, 20);
  assert.equal(
    isExpiredAnalyticsMarker(
      Timestamp.fromDate(new Date("2026-08-23T03:59:59.000Z")),
      new Date("2026-08-23T04:00:00.000Z")
    ),
    true
  );
  assert.equal(
    isExpiredAnalyticsMarker(
      Timestamp.fromDate(new Date("2026-08-23T04:00:01.000Z")),
      new Date("2026-08-23T04:00:00.000Z")
    ),
    false
  );
});

test("system log retention matrix remains explicit", () => {
  assert.equal(auditLogRetentionDays, 1_095);
  assert.deepEqual(systemLogRetentionDays, {
    technicalError: 90,
    normalAudit: 365,
    security: 730,
    moderationDispute: 1_095,
  });
  assert.equal(
    subtractUtcDays(new Date("2026-08-22T04:00:00.000Z"), 90).toISOString(),
    "2026-05-24T04:00:00.000Z",
  );
});
