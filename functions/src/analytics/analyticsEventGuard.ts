import {createHash} from "node:crypto";

import {HttpsError} from "firebase-functions/v2/https";

export const analyticsRateLimitMaximum = 120;
export const analyticsRateLimitWindowMinutes = 5;
export const analyticsReceiptRetentionHours = 48;
export const analyticsRateLimitRetentionHours = 2;
export const analyticsEventReceiptCollection = "analyticsEventReceipts";
export const analyticsRateLimitCollection = "analyticsRateLimits";

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

export function expirationDate(now: Date, retentionHours: number): Date {
  return new Date(now.getTime() + retentionHours * 60 * 60 * 1_000);
}

function digest(parts: string[]): string {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex");
}
