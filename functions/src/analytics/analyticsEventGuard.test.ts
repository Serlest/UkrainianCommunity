import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  analyticsDeletionEventID,
  analyticsRegistrationEventID,
  analyticsRegistrationUserKey,
  analyticsRateLimitID,
  analyticsRateLimitMaximum,
  analyticsReceiptID,
  analyticsReceiptRetentionHours,
  expirationDate,
  nextAnalyticsRateLimitCount,
  nextAnalyticsRateLimitState,
  rateLimitBucketStart,
} from "./analyticsEventGuard";

test("deleted-user event IDs are stable and opaque", () => {
  const first = analyticsDeletionEventID("cloud-event-123");
  assert.equal(first, analyticsDeletionEventID("cloud-event-123"));
  assert.notEqual(first, analyticsDeletionEventID("cloud-event-456"));
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(first.includes("cloud-event"), false);
});

test("registered-user lifecycle identifiers are stable and opaque", () => {
  const eventID = analyticsRegistrationEventID("cloud-event-123");
  const userKey = analyticsRegistrationUserKey("user-secret");

  assert.equal(eventID, analyticsRegistrationEventID("cloud-event-123"));
  assert.equal(userKey, analyticsRegistrationUserKey("user-secret"));
  assert.notEqual(eventID, userKey);
  assert.match(eventID, /^[a-f0-9]{64}$/);
  assert.match(userKey, /^[a-f0-9]{64}$/);
  assert.equal(eventID.includes("cloud-event"), false);
  assert.equal(userKey.includes("user-secret"), false);
});

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

test("builds one deterministic rate-limit update for preflight consumption", () => {
  const now = new Date("2026-08-23T20:03:59.000Z");
  const state = nextAnalyticsRateLimitState(7, now);

  assert.equal(state.count, 8);
  assert.equal(state.bucketStartedAt.toISOString(), "2026-08-23T20:00:00.000Z");
  assert.equal(state.updatedAt.toISOString(), now.toISOString());
  assert.equal(state.expiresAt.toISOString(), "2026-08-23T22:03:59.000Z");
});

test("computes explicit retention expirations", () => {
  assert.ok(analyticsReceiptRetentionHours > 48);
  assert.equal(
    expirationDate(
      new Date("2026-08-23T20:00:00Z"),
      analyticsReceiptRetentionHours
    ).toISOString(),
    "2026-08-26T20:00:00.000Z"
  );
  assert.equal(
    expirationDate(new Date("2026-08-23T20:00:00Z"), 2).toISOString(),
    "2026-08-23T22:00:00.000Z"
  );
});
