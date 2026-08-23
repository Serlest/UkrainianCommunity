import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  analyticsRateLimitID,
  analyticsRateLimitMaximum,
  analyticsReceiptID,
  expirationDate,
  nextAnalyticsRateLimitCount,
  rateLimitBucketStart,
} from "./analyticsEventGuard";

test("builds stable opaque receipt and rate-limit identifiers", () => {
  const receipt = analyticsReceiptID(
    "user-secret",
    "2026-08-23",
    "news_view",
    "news",
    "news-1"
  );
  const rate = analyticsRateLimitID("user-secret", new Date("2026-08-23T20:03:00Z"));

  assert.match(receipt, /^[a-f0-9]{64}$/);
  assert.match(rate, /^[a-f0-9]{64}$/);
  assert.equal(receipt.includes("user-secret"), false);
  assert.equal(rate.includes("user-secret"), false);
  assert.equal(
    receipt,
    analyticsReceiptID("user-secret", "2026-08-23", "news_view", "news", "news-1")
  );
});

test("uses deterministic five-minute rate-limit buckets", () => {
  assert.equal(
    rateLimitBucketStart(new Date("2026-08-23T20:03:59Z")).toISOString(),
    "2026-08-23T20:00:00.000Z"
  );
  assert.equal(
    rateLimitBucketStart(new Date("2026-08-23T20:05:00Z")).toISOString(),
    "2026-08-23T20:05:00.000Z"
  );
});

test("increments valid counters and rejects exhausted buckets", () => {
  assert.equal(nextAnalyticsRateLimitCount(undefined), 1);
  assert.equal(nextAnalyticsRateLimitCount(7), 8);
  assert.throws(
    () => nextAnalyticsRateLimitCount(analyticsRateLimitMaximum),
    (error) => error instanceof HttpsError && error.code === "resource-exhausted"
  );
});

test("computes explicit retention expirations", () => {
  assert.equal(
    expirationDate(new Date("2026-08-23T20:00:00Z"), 2).toISOString(),
    "2026-08-23T22:00:00.000Z"
  );
});
