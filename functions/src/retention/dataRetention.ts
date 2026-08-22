import { DocumentData, Query, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { adminStorage, db } from "../firebase/admin";

const relatedBatchSize = 400;
const maxContentDocumentsPerRun = 200;
const maxLogDocumentsPerPolicy = 400;

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
      await deleteContentDocument(kind, document.id);
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

async function deleteContentDocument(kind: ContentKind, contentId: string): Promise<void> {
  if (kind === "news") {
    await deleteQuery(db.collection("likes").where("newsId", "==", contentId));
    await deleteCollectionGroupDocuments("newsBookmarks", "newsId", contentId);
    await deleteCollectionGroupDocuments("newsViews", "newsId", contentId);
  } else {
    await deleteQuery(db.collection("likes").where("eventId", "==", contentId));
    await deleteQuery(db.collection("registrations").where("eventId", "==", contentId));
    await deleteCollectionGroupDocuments("eventBookmarks", "eventId", contentId);
    await deleteCollectionGroupDocuments("eventViews", "eventId", contentId);
  }

  await deleteStoragePrefix(`${kind}/${contentId}/`);
  await db.recursiveDelete(db.collection(kind).doc(contentId));
}

async function deleteCollectionGroupDocuments(
  collectionId: string,
  field: string,
  value: string,
): Promise<void> {
  await deleteQuery(db.collectionGroup(collectionId).where(field, "==", value));
}

async function deleteQuery(query: Query<DocumentData>): Promise<void> {
  while (true) {
    const snapshot = await query.limit(relatedBatchSize).get();
    if (snapshot.empty) {
      return;
    }

    const writer = db.bulkWriter();
    for (const document of snapshot.docs) {
      writer.delete(document.ref);
    }
    await writer.close();
  }
}

async function deleteStoragePrefix(prefix: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({ prefix, force: true });
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
