import { getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

const retentionDays = 60;
const maxParentDocsPerRun = 200;
const maxSubcollectionDocsPerParent = 200;
const preservedDocumentIds = new Set(["today", "seven_days", "thirty_days"]);

type AggregateCollection = {
  collectionPath: string;
  nestedCollectionNames?: string[];
};

const aggregateCollections: AggregateCollection[] = [
  { collectionPath: "analyticsDailyStats" },
  { collectionPath: "analyticsTopContent" },
  { collectionPath: "analyticsRegionStats" },
  { collectionPath: "analyticsUserStats" },
  { collectionPath: "analyticsContentStats", nestedCollectionNames: ["items"] },
  { collectionPath: "analyticsOrganizationStats", nestedCollectionNames: ["organizations"] },
];

export const cleanupAnalyticsAggregates = onSchedule(
  {
    schedule: "every day 03:30",
    timeZone: "Europe/Vienna",
    region: "europe-west1",
  },
  async () => {
    const database = getFirestore();
    const cutoffDate = startOfUtcDay(daysAgo(retentionDays));
    const writer = database.bulkWriter();
    let deletedDocuments = 0;

    for (const aggregateCollection of aggregateCollections) {
      const snapshot = await database
        .collection(aggregateCollection.collectionPath)
        .select()
        .limit(maxParentDocsPerRun)
        .get();

      for (const documentSnapshot of snapshot.docs) {
        if (!shouldDeleteAggregateDocument(documentSnapshot.id, cutoffDate)) {
          continue;
        }

        for (const nestedCollectionName of aggregateCollection.nestedCollectionNames ?? []) {
          const nestedSnapshot = await documentSnapshot.ref
            .collection(nestedCollectionName)
            .select()
            .limit(maxSubcollectionDocsPerParent)
            .get();

          for (const nestedDocumentSnapshot of nestedSnapshot.docs) {
            writer.delete(nestedDocumentSnapshot.ref);
            deletedDocuments += 1;
          }
        }

        writer.delete(documentSnapshot.ref);
        deletedDocuments += 1;
      }
    }

    await writer.close();

    logger.info("Analytics aggregate cleanup completed.", {
      retentionDays,
      deletedDocuments,
    });
  },
);

function shouldDeleteAggregateDocument(documentId: string, cutoffDate: Date): boolean {
  if (preservedDocumentIds.has(documentId)) {
    return false;
  }

  const documentDate = dateFromDocumentId(documentId);
  if (!documentDate) {
    return false;
  }

  return documentDate < cutoffDate;
}

function dateFromDocumentId(documentId: string): Date | undefined {
  const match = /^(\\d{4})-(\\d{2})-(\\d{2})$/.exec(documentId);
  if (!match) {
    return undefined;
  }

  const [, year, month, day] = match;
  return new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
}

function daysAgo(days: number): Date {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() - days);
  return date;
}

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}
