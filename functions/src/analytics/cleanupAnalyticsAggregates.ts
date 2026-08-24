import {
  FieldPath,
  Firestore,
  getFirestore,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  aggregateRetentionCutoffDocumentID,
  planAggregateCleanupPage,
  shouldDeleteAggregateDocument,
} from "./analyticsAggregateRetention";
import {loadAnalyticsSchemaGateState} from "./analyticsSchemaGate";

const retentionDays = 60;
const cleanupPageSize = 50;
const maxCleanupPagesPerCollectionPerRun = 4;
const cleanupCursorCollection = "analyticsAggregateCleanupState";

const aggregateCollectionPaths = [
  "analyticsDailyStats",
  "analyticsTopContent",
  "analyticsRegionStats",
  "analyticsUserStats",
  "analyticsContentStats",
  "analyticsOrganizationStats",
  "analyticsUserLifecycleBaselines",
];

type CollectionCleanupSummary = {
  collectionPath: string;
  scanned: number;
  deleted: number;
  failed: number;
  nextCursor: string | undefined;
};

export const cleanupAnalyticsAggregates = onSchedule(
  {
    schedule: "every day 03:30",
    timeZone: "Europe/Vienna",
    // Keep the production function's original region. Firebase cannot move a
    // deployed function in place, and a region change could leave two cleanup
    // schedules active during the analytics cutover.
    region: "europe-west1",
    maxInstances: 1,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const database = getFirestore();
    const schemaState = await loadAnalyticsSchemaGateState(database);
    if (schemaState?.status !== "complete") {
      logger.warn("Analytics aggregate cleanup paused for schema transition.", {
        schemaVersion: schemaState?.schemaVersion ?? null,
        cutoverStatus: schemaState?.status ?? "missing-or-invalid",
      });
      return;
    }
    const cutoffDocumentID = aggregateRetentionCutoffDocumentID(
      new Date(),
      retentionDays,
    );
    const summaries: CollectionCleanupSummary[] = [];

    // Each collection has an independent cursor and budget. A malformed or
    // undeletable document therefore cannot permanently block later roots, and
    // a busy collection cannot consume the budget of the remaining collections.
    for (const collectionPath of aggregateCollectionPaths) {
      try {
        summaries.push(await cleanupAggregateCollection(
          database,
          collectionPath,
          cutoffDocumentID,
        ));
      } catch (error) {
        logger.error("Analytics aggregate collection cleanup failed.", {
          collectionPath,
          cutoffDocumentID,
          error,
        });
      }
    }

    logger.info("Analytics aggregate cleanup completed.", {
      retentionDays,
      cutoffDocumentID,
      scannedAggregateRoots: summaries.reduce(
        (total, summary) => total + summary.scanned,
        0,
      ),
      deletedAggregateRoots: summaries.reduce(
        (total, summary) => total + summary.deleted,
        0,
      ),
      failedAggregateRoots: summaries.reduce(
        (total, summary) => total + summary.failed,
        0,
      ),
      collections: summaries,
    });
  },
);

async function cleanupAggregateCollection(
  database: Firestore,
  collectionPath: string,
  cutoffDocumentID: string,
): Promise<CollectionCleanupSummary> {
  const cursorReference = database
    .collection(cleanupCursorCollection)
    .doc(collectionPath);
  const cursorSnapshot = await cursorReference.get();
  let cursor = cleanupCursor(cursorSnapshot.data()?.cursor);
  let hasWrappedStaleCursor = false;
  let scanned = 0;
  let deleted = 0;
  let failed = 0;

  for (
    let page = 0;
    page < maxCleanupPagesPerCollectionPerRun;
    page += 1
  ) {
    let query = database
      .collection(collectionPath)
      .orderBy(FieldPath.documentId())
      .select()
      .limit(cleanupPageSize + 1);
    if (cursor !== undefined) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      // A cursor can outlive its referenced root because roots are recursively
      // deleted. Wrap once immediately so a stale cursor cannot waste a run.
      if (cursor !== undefined && !hasWrappedStaleCursor) {
        cursor = undefined;
        hasWrappedStaleCursor = true;
        await cursorReference.delete();
        page -= 1;
        continue;
      }
      break;
    }

    const pagePlan = planAggregateCleanupPage(
      snapshot.docs.map((document) => document.id),
      cleanupPageSize,
    );
    const documentsByID = new Map(
      snapshot.docs.map((document) => [document.id, document]),
    );

    for (const documentID of pagePlan.documentIDsToInspect) {
      const document = documentsByID.get(documentID);
      if (document === undefined) {
        continue;
      }

      scanned += 1;
      if (!shouldDeleteAggregateDocument(documentID, cutoffDocumentID)) {
        continue;
      }

      if (await deleteAggregateRoot(database, document, collectionPath)) {
        deleted += 1;
      } else {
        failed += 1;
      }
    }

    cursor = pagePlan.nextCursor;
    if (cursor === undefined) {
      await cursorReference.delete();
      break;
    }

    await cursorReference.set({cursor});
  }

  return {
    collectionPath,
    scanned,
    deleted,
    failed,
    nextCursor: cursor,
  };
}

async function deleteAggregateRoot(
  database: Firestore,
  document: QueryDocumentSnapshot,
  collectionPath: string,
): Promise<boolean> {
  try {
    await database.recursiveDelete(document.ref);
    return true;
  } catch (error) {
    logger.error("Failed to delete an expired analytics aggregate root.", {
      collectionPath,
      documentID: document.id,
      error,
    });
    return false;
  }
}

function cleanupCursor(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}
