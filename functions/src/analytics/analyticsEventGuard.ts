import {createHash} from "node:crypto";

import {HttpsError} from "firebase-functions/v2/https";

export const analyticsRateLimitMaximum = 120;
export const analyticsRateLimitWindowMinutes = 5;
// Must exceed the 48-hour accepted delivery horizon. The additional day keeps
// the deterministic receipt present through daily cleanup timing and prevents
// a same-day event from being replayed after its first receipt expires.
export const analyticsReceiptRetentionHours = 72;
export const analyticsRateLimitRetentionHours = 2;
export const analyticsEventReceiptCollection = "analyticsEventReceipts";
export const analyticsRateLimitCollection = "analyticsRateLimits";

export function analyticsDeletionEventID(eventID: string): string {
  return digest(["deleted-user", eventID]);
}

export function analyticsRegistrationEventID(eventID: string): string {
  return digest(["registered-user", eventID]);
}

export function analyticsRegistrationUserKey(uid: string): string {
  return digest(["registered-user-key", uid]);
}

export function analyticsReceiptID(
  uid: string,
  analyticsDay: string,
  eventName: string,
  contentType: string,
  contentID: string
): string {
  return digest(["receipt", uid, analyticsDay, eventName, contentType, contentID]);
}

export function analyticsRateLimitID(uid: string, now: Date): string {
  return digest(["rate", uid, rateLimitBucketStart(now).toISOString()]);
}

export function rateLimitBucketStart(now: Date): Date {
  const bucketMilliseconds = analyticsRateLimitWindowMinutes * 60 * 1_000;
  return new Date(Math.floor(now.getTime() / bucketMilliseconds) * bucketMilliseconds);
}

export function nextAnalyticsRateLimitCount(currentValue: unknown): number {
  const currentCount = typeof currentValue === "number"
    && Number.isSafeInteger(currentValue)
    && currentValue >= 0
    ? currentValue
    : 0;

  if (currentCount >= analyticsRateLimitMaximum) {
    throw new HttpsError(
      "resource-exhausted",
      "Analytics event rate limit exceeded."
    );
  }

  return currentCount + 1;
}

export interface AnalyticsRateLimitState {
  count: number;
  bucketStartedAt: Date;
  updatedAt: Date;
  expiresAt: Date;
}

export function nextAnalyticsRateLimitState(
  currentValue: unknown,
  now: Date
): AnalyticsRateLimitState {
  return {
    count: nextAnalyticsRateLimitCount(currentValue),
    bucketStartedAt: rateLimitBucketStart(now),
    updatedAt: now,
    expiresAt: expirationDate(now, analyticsRateLimitRetentionHours),
  };
}

export function expirationDate(now: Date, retentionHours: number): Date {
  return new Date(now.getTime() + retentionHours * 60 * 60 * 1_000);
}

function digest(parts: string[]): string {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex");
}
