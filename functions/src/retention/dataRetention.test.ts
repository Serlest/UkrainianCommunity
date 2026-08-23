import { strict as assert } from "node:assert";
import { test } from "node:test";

import {
  analyticsRateLimitRetentionHours,
  analyticsReceiptRetentionHours,
} from "../analytics/analyticsEventGuard";
import {
  contentRetentionMonths,
  subtractUtcDays,
  subtractUtcMonths,
  systemLogRetentionDays,
} from "./dataRetention";

test("content retention is six calendar months", () => {
  assert.equal(contentRetentionMonths, 6);
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
  assert.equal(analyticsReceiptRetentionHours, 48);
  assert.equal(analyticsRateLimitRetentionHours, 2);
});

test("system log retention matrix remains explicit", () => {
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
