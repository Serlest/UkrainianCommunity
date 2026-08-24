import {
  DocumentReference,
  DocumentData,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  analyticsEventReceiptCollection,
  analyticsRateLimitCollection,
} from "../analytics/analyticsEventGuard";
import {
  analyticsDeletedUserEventCollection,
  analyticsUserActivityCollection,
  analyticsUserRegistrationEventCollection,
} from "../analytics/analyticsUserActivity";
import {deleteEventContent, deleteNewsContent} from "../content/contentDeletion";
import { db } from "../firebase/admin";

const maxContentDocumentsPerRun = 200;
const maxLogDocumentsPerPolicy = 400;
export const analyticsCleanupPageSize = 500;
export const maxAnalyticsCleanupPagesPerRun = 20;
const mutableCleanupConcurrency = 40;

export const contentRetentionMonths = 6;

export const systemLogRetentionDays = {
  technicalError: 90,
  normalAudit: 365,
  security: 730,
  moderationDispute: 1_095,
} as const;

type ContentKind = "news" | "events";

type CleanupSummary = {
  news: number;
  events: number;
  systemLogs: number;
  analyticsEventReceipts: number;
  analyticsRateLimits: number;
  analyticsUserActivity: number;
  analyticsUserRegistrationEvents: number;
  analyticsDeletedUserEvents: number;
};

export const cleanupExpiredData = onSchedule(
  {
    schedule: "every day 04:00",
    timeZone: "Europe/Vienna",
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const now = new Date();
    const contentCutoff = subtractUtcMonths(now, contentRetentionMonths);
    const summary: CleanupSummary = {
      news: await cleanupExpiredContent("news", "publishedAt", contentCutoff),
      events: await cleanupExpiredContent("events", "endDate", contentCutoff),
      systemLogs: await cleanupExpiredSystemLogs(now),
      analyticsEventReceipts: await cleanupExpiredAnalyticsGuards(
        analyticsEventReceiptCollection,
        now,
      ),
      analyticsRateLimits: await cleanupExpiredAnalyticsGuards(
        analyticsRateLimitCollection,
        now,
      ),
      analyticsUserActivity: await cleanupExpiredAnalyticsGuards(
        analyticsUserActivityCollection,
        now,
      ),
      analyticsUserRegistrationEvents: await cleanupExpiredAnalyticsGuards(
        analyticsUserRegistrationEventCollection,
        now,
      ),
      analyticsDeletedUserEvents: await cleanupExpiredAnalyticsGuards(
        analyticsDeletedUserEventCollection,
        now,
      ),
    };

    logger.info("Scheduled data retention cleanup completed.", {
      ...summary,
      contentRetentionMonths,
      contentCutoff: contentCutoff.toISOString(),
    });
  },
);

export function subtractUtcMonths(date: Date, months: number): Date {
  const result = new Date(date.getTime());
  const originalDay = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() - months);
  const lastDayOfTargetMonth = new Date(Date.UTC(
    result.getUTCFullYear(),
    result.getUTCMonth() + 1,
    0,
  )).getUTCDate();
  result.setUTCDate(Math.min(originalDay, lastDayOfTargetMonth));
  return result;
}

export function subtractUtcDays(date: Date, days: number): Date {
  return new Date(date.getTime() - days * 24 * 60 * 60 * 1_000);
}

async function cleanupExpiredContent(
  kind: ContentKind,
  cutoffField: "publishedAt" | "endDate",
  cutoff: Date,
): Promise<number> {
  let deleted = 0;

  const snapshot = await db.collection(kind)
    .where(cutoffField, "<=", Timestamp.fromDate(cutoff))
    .limit(maxContentDocumentsPerRun)
    .get();

  for (const document of snapshot.docs) {
    try {
      if (kind === "news") {
        await deleteNewsContent(document.id, document.data());
      } else {
        await deleteEventContent(document.id, document.data());
      }
      deleted += 1;
    } catch (error) {
      logger.error("Failed to delete an expired content document.", {
        kind,
        contentId: document.id,
        error,
      });
    }
  }

  return deleted;
}

async function cleanupExpiredSystemLogs(now: Date): Promise<number> {
  let deleted = 0;

  for (const [policy, retentionDays] of Object.entries(systemLogRetentionDays)) {
    const cutoff = subtractUtcDays(now, retentionDays);
    const query = db.collection("systemLogs")
      .where("retentionPolicy", "==", policy)
      .where("createdAt", "<=", Timestamp.fromDate(cutoff));
    deleted += await deleteLimitedQuery(query, maxLogDocumentsPerPolicy);
  }

  return deleted;
}

async function cleanupExpiredAnalyticsGuards(
  collection: string,
  now: Date,
): Promise<number> {
  let deleted = 0;

  for (let page = 0; page < maxAnalyticsCleanupPagesPerRun; page += 1) {
    const snapshot = await db.collection(collection)
      .where("expiresAt", "<=", Timestamp.fromDate(now))
      .orderBy("expiresAt")
      .limit(analyticsCleanupPageSize)
      .get();
    if (snapshot.empty) {
      return deleted;
    }

    if (collection === analyticsUserActivityCollection) {
      deleted += await deleteExpiredMutableActivityDocuments(snapshot.docs, now);
    } else {
      deleted += await deleteSnapshots(snapshot.docs);
    }

    if (snapshot.size < analyticsCleanupPageSize) {
      return deleted;
    }
  }

  logger.warn("Analytics retention cleanup reached its per-run page limit.", {
    collection,
    analyticsCleanupPageSize,
    maxAnalyticsCleanupPagesPerRun,
    deleted,
  });
  return deleted;
}

async function deleteExpiredMutableActivityDocuments(
  documents: QueryDocumentSnapshot<DocumentData>[],
  now: Date,
): Promise<number> {
  let deleted = 0;

  for (let offset = 0; offset < documents.length; offset += mutableCleanupConcurrency) {
    const chunk = documents.slice(offset, offset + mutableCleanupConcurrency);
    const results = await Promise.all(chunk.map((document) =>
      deleteExpiredAnalyticsActivityDocument(document.ref, now)
    ));
    deleted += results.filter(Boolean).length;
  }

  return deleted;
}

export async function deleteExpiredAnalyticsActivityDocument(
  reference: DocumentReference<DocumentData>,
  now: Date,
): Promise<boolean> {
  return db.runTransaction(async (transaction) => {
    const current = await transaction.get(reference);
    if (!current.exists || !isExpiredAnalyticsMarker(current.data()?.expiresAt, now)) {
      return false;
    }

    transaction.delete(reference);
    return true;
  });
}

async function deleteSnapshots(
  documents: QueryDocumentSnapshot<DocumentData>[],
): Promise<number> {
  if (documents.length === 0) {
    return 0;
  }

  const writer = db.bulkWriter();
  for (const document of documents) {
    writer.delete(document.ref);
  }
  await writer.close();
  return documents.length;
}

export function isExpiredAnalyticsMarker(value: unknown, now: Date): boolean {
  return value instanceof Timestamp && value.toMillis() <= now.getTime();
}

async function deleteLimitedQuery(
  query: Query<DocumentData>,
  limit: number,
): Promise<number> {
  const snapshot = await query.limit(limit).get();
  if (snapshot.empty) {
    return 0;
  }

  const writer = db.bulkWriter();
  for (const document of snapshot.docs) {
    writer.delete(document.ref);
  }
  await writer.close();
  return snapshot.size;
}
