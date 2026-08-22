import { getFirestore } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {shouldDeleteAggregateDocument} from "./analyticsAggregateRetention";

const retentionDays = 60;
const maxParentDocsPerRun = 200;

const aggregateCollectionPaths = [
  "analyticsDailyStats",
  "analyticsTopContent",
  "analyticsRegionStats",
  "analyticsUserStats",
  "analyticsContentStats",
  "analyticsOrganizationStats",
];

export const cleanupAnalyticsAggregates = onSchedule(
  {
    schedule: "every day 03:30",
    timeZone: "Europe/Vienna",
    region: "europe-west1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const database = getFirestore();
    const cutoffDate = startOfUtcDay(daysAgo(retentionDays));
    let deletedAggregateRoots = 0;

    for (const collectionPath of aggregateCollectionPaths) {
      const snapshot = await database
        .collection(collectionPath)
        .select()
        .limit(maxParentDocsPerRun)
        .get();

      for (const documentSnapshot of snapshot.docs) {
        if (!shouldDeleteAggregateDocument(documentSnapshot.id, cutoffDate)) {
          continue;
        }

        await database.recursiveDelete(documentSnapshot.ref);
        deletedAggregateRoots += 1;
      }
    }

    logger.info("Analytics aggregate cleanup completed.", {
      retentionDays,
      deletedAggregateRoots,
    });
  },
);

function daysAgo(days: number): Date {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() - days);
  return date;
}

function startOfUtcDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}
