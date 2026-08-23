import {randomUUID} from "node:crypto";

import {FieldPath, FieldValue, type DocumentData} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {adminStorage, db} from "../firebase/admin";
import {
  type ContentKind,
  canonicalContentStoragePath,
  firebaseStorageDownloadURL,
  legacyDraftStoragePath,
  storageObjectPathFromDownloadURL,
} from "./contentDeletionPolicy";

type MigrationResult = "migrated" | "cleaned" | "skipped" | "failed";

interface MigrationState {
  newsCursor?: string;
  newsCompleted?: boolean;
  eventsCursor?: string;
  eventsCompleted?: boolean;
}

interface MigrationSummary {
  migrated: number;
  cleaned: number;
  skipped: number;
  failed: number;
}

const migrationPageSize = 100;
const migrationStateReference = db
  .collection("appRuntimeConfig")
  .doc("legacyContentMediaMigration");

export const migrateLegacyContentMedia = onSchedule(
  {
    schedule: "every day 03:30",
    timeZone: "Europe/Vienna",
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const stateSnapshot = await migrationStateReference.get();
    const state = (stateSnapshot.data() ?? {}) as MigrationState;
    const summary: MigrationSummary = {migrated: 0, cleaned: 0, skipped: 0, failed: 0};

    if (state.newsCompleted !== true) {
      mergeSummary(summary, await migrateContentPage("news", state.newsCursor));
    }
    if (state.eventsCompleted !== true) {
      mergeSummary(summary, await migrateContentPage("events", state.eventsCursor));
    }

    logger.info("Legacy content media migration pass completed.", summary);
  }
);

async function migrateContentPage(
  kind: ContentKind,
  cursor?: string
): Promise<MigrationSummary> {
  let query = db.collection(kind)
    .orderBy(FieldPath.documentId())
    .limit(migrationPageSize);
  if (cursor) {
    query = query.startAfter(cursor);
  }

  const snapshot = await query.get();
  const summary: MigrationSummary = {migrated: 0, cleaned: 0, skipped: 0, failed: 0};
  for (const document of snapshot.docs) {
    const result = await migrateContentDocument(kind, document.id, document.data());
    summary[result] += 1;
  }

  const isComplete = snapshot.size < migrationPageSize;
  const lastDocumentId = snapshot.docs.at(-1)?.id;
  const cursorField = kind === "news" ? "newsCursor" : "eventsCursor";
  const completedField = kind === "news" ? "newsCompleted" : "eventsCompleted";
  await migrationStateReference.set({
    [cursorField]: isComplete ? FieldValue.delete() : lastDocumentId,
    [completedField]: isComplete,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});

  return summary;
}

async function migrateContentDocument(
  kind: ContentKind,
  contentId: string,
  data: DocumentData
): Promise<MigrationResult> {
  const organizationId = stringField(data, "organizationId");
  if (!organizationId) {
    return "skipped";
  }

  const sourcePath = legacyDraftStoragePath(kind, organizationId, contentId);
  const source = adminStorage.bucket().file(sourcePath);
  const [sourceExists] = await source.exists();
  if (!sourceExists) {
    return "skipped";
  }

  const imageURL = stringField(data, "imageURL");
  if (imageURL && storageObjectPathFromDownloadURL(imageURL) === sourcePath) {
    try {
      const destinationPath = canonicalContentStoragePath(kind, contentId);
      const destination = adminStorage.bucket().file(destinationPath);
      await source.copy(destination);
      const [metadata] = await destination.getMetadata();
      const rawDownloadTokens = metadata.metadata?.firebaseStorageDownloadTokens;
      const existingToken = typeof rawDownloadTokens === "string"
        ? rawDownloadTokens.split(",").map((token) => token.trim()).find(Boolean)
        : undefined;
      const downloadToken = existingToken ?? randomUUID();
      if (!existingToken) {
        await destination.setMetadata({
          metadata: {
            ...metadata.metadata,
            firebaseStorageDownloadTokens: downloadToken,
          },
        });
      }

      const canonicalURL = firebaseStorageDownloadURL(
        adminStorage.bucket().name,
        destinationPath,
        downloadToken
      );
      await db.collection(kind).doc(contentId).update({
        imageURL: canonicalURL,
        updatedAt: FieldValue.serverTimestamp(),
      });
      await source.delete({ignoreNotFound: true});
      return "migrated";
    } catch (error) {
      logger.error("Failed to migrate legacy content media.", {
        kind,
        contentId,
        organizationId,
        sourcePath,
        error,
      });
      return "failed";
    }
  }

  await source.delete({ignoreNotFound: true});
  return "cleaned";
}

function stringField(data: DocumentData, field: string): string | undefined {
  const value = data[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function mergeSummary(target: MigrationSummary, page: MigrationSummary): void {
  target.migrated += page.migrated;
  target.cleaned += page.cleaned;
  target.skipped += page.skipped;
  target.failed += page.failed;
}
