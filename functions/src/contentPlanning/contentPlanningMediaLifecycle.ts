import {FieldValue, type DocumentData, type DocumentReference} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onDocumentDeleted, onDocumentUpdated} from "firebase-functions/v2/firestore";

import {storageObjectPathFromDownloadURL} from "../content/contentDeletionPolicy";
import {adminStorage, db} from "../firebase/admin";
import {
  contentPlanningDraftImagePrefix,
  contentPlanningDraftMediaCleanupDecision,
  isContentPlanningPublishedKind,
  isContentPlanningTerminalState,
  type ContentPlanningDraftMediaCleanupDecision,
} from "./contentPlanningRetentionPolicy";

const region = "europe-west3";
const pendingCleanupStatus = "pending";

export const cleanupContentPlanningDraftMediaOnTerminalState = onDocumentUpdated(
  {
    document: "users/{userId}/contentPlanningDrafts/{draftId}",
    region,
    retry: true,
  },
  async (event) => {
    const after = event.data?.after.data();
    if (!after || !isContentPlanningTerminalState(after.state) ||
        after.draftMediaCleanupStatus !== pendingCleanupStatus) {
      return;
    }
    await cleanupTerminalDraftMedia(event.params.userId, event.params.draftId);
  }
);

export const cleanupContentPlanningDraftMediaOnDelete = onDocumentDeleted(
  {
    document: "users/{userId}/contentPlanningDrafts/{draftId}",
    region,
    retry: true,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const draftPath = generatedImageStoragePath(data);
    if (!draftPath) return;

    const expectedPrefix = contentPlanningDraftImagePrefix(
      event.params.userId,
      event.params.draftId
    );
    if (!draftPath.startsWith(expectedPrefix)) {
      logger.error("Refused to delete a planning image outside its exact draft prefix.", {
        userId: event.params.userId,
        draftId: event.params.draftId,
        draftPath,
      });
      return;
    }
    if (await draftMediaHasLiveReference(data, draftPath)) {
      logger.warn("Retained planning image because live content still references it.", {
        userId: event.params.userId,
        draftId: event.params.draftId,
        draftPath,
      });
      return;
    }
    await adminStorage.bucket().deleteFiles({prefix: expectedPrefix, force: true});
  }
);

async function cleanupTerminalDraftMedia(ownerUserId: string, draftId: string): Promise<void> {
  const reference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(draftId);
  const snapshot = await reference.get();
  if (!snapshot.exists) return;
  const data = snapshot.data() ?? {};
  if (!isContentPlanningTerminalState(data.state) ||
      data.draftMediaCleanupStatus !== pendingCleanupStatus) {
    return;
  }

  const draftPath = generatedImageStoragePath(data);
  const expectedDraftPrefix = contentPlanningDraftImagePrefix(ownerUserId, draftId);
  const live = await liveContentState(data);
  const generatedImageURL = generatedImageDownloadURL(data);
  const decision = contentPlanningDraftMediaCleanupDecision({
    state: data.state,
    draftStoragePath: draftPath,
    expectedDraftPrefix,
    publishedContentId: stringValue(data.publishedContentId),
    publishedContentKind: stringValue(data.publishedContentKind),
    liveContentExists: live.exists,
    liveImagePath: live.imagePath,
    liveImageExists: live.imageExists,
    hasOtherLiveReference: generatedImageURL
      ? await hasLiveReferenceToImageURL(generatedImageURL)
      : false,
  });

  if (decision === "noMedia") {
    await finishMediaCleanup(reference, undefined, "noMedia", 0);
    return;
  }
  if (decision !== "deleteArchivedCopy" && decision !== "deleteRedundantCopy") {
    await markRetainedMedia(reference, decision);
    return;
  }
  if (!draftPath) {
    await finishMediaCleanup(reference, undefined, "noMedia", 0);
    return;
  }

  const currentSnapshot = await reference.get();
  const currentData = currentSnapshot.data() ?? {};
  if (!currentSnapshot.exists || currentData.draftMediaCleanupStatus !== pendingCleanupStatus ||
      generatedImageStoragePath(currentData) !== draftPath ||
      !isContentPlanningTerminalState(currentData.state)) {
    return;
  }
  const currentLive = await liveContentState(currentData);
  const currentGeneratedURL = generatedImageDownloadURL(currentData);
  const currentDecision = contentPlanningDraftMediaCleanupDecision({
    state: currentData.state,
    draftStoragePath: draftPath,
    expectedDraftPrefix,
    publishedContentId: stringValue(currentData.publishedContentId),
    publishedContentKind: stringValue(currentData.publishedContentKind),
    liveContentExists: currentLive.exists,
    liveImagePath: currentLive.imagePath,
    liveImageExists: currentLive.imageExists,
    hasOtherLiveReference: currentGeneratedURL
      ? await hasLiveReferenceToImageURL(currentGeneratedURL)
      : false,
  });
  if (currentDecision !== "deleteArchivedCopy" &&
      currentDecision !== "deleteRedundantCopy") {
    if (currentDecision === "noMedia") {
      await markRetainedMedia(reference, "retainInvalidPath");
    } else {
      await markRetainedMedia(reference, currentDecision);
    }
    return;
  }

  const metadata = await storageObjectMetadata(draftPath);
  if (!metadata.exists) {
    await finishMediaCleanup(reference, draftPath, "alreadyMissing", 0);
    return;
  }
  const generation = Number(metadata.generation);
  if (!Number.isSafeInteger(generation) || generation <= 0) {
    await markRetainedMedia(reference, "retainInvalidPath");
    return;
  }

  await adminStorage.bucket().file(draftPath, {generation}).delete({ignoreNotFound: true});
  await finishMediaCleanup(
    reference,
    draftPath,
    currentDecision === "deleteArchivedCopy" ?
      "deletedArchivedCopy" : "deletedRedundantCopy",
    metadata.size
  );
}

async function finishMediaCleanup(
  reference: DocumentReference,
  expectedStoragePath: string | undefined,
  status: "alreadyMissing" | "deletedArchivedCopy" | "deletedRedundantCopy" | "noMedia",
  bytes: number
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) return;
    const data = snapshot.data() ?? {};
    if (data.draftMediaCleanupStatus !== pendingCleanupStatus ||
        !isContentPlanningTerminalState(data.state)) {
      return;
    }
    if (expectedStoragePath && generatedImageStoragePath(data) !== expectedStoragePath) {
      return;
    }
    transaction.update(reference, {
      generatedImage: FieldValue.delete(),
      "payload.generatedImageURL": FieldValue.delete(),
      draftMediaCleanupStatus: status,
      draftMediaCleanedAt: FieldValue.serverTimestamp(),
      draftMediaCleanupBytes: bytes,
    });
  });
}

async function markRetainedMedia(
  reference: DocumentReference,
  decision: Exclude<
    ContentPlanningDraftMediaCleanupDecision,
    "deleteArchivedCopy" | "deleteRedundantCopy" | "noMedia"
  >
): Promise<void> {
  await reference.update({
    draftMediaCleanupStatus: decision,
    draftMediaCleanupCheckedAt: FieldValue.serverTimestamp(),
  });
  const context = {path: reference.path, decision};
  if (decision === "retainLiveReference" || decision === "retainUnresolved") {
    logger.warn("Retained terminal planning media by policy.", context);
  } else {
    logger.error("Planning media cleanup requires attention.", context);
  }
}

async function liveContentState(data: DocumentData): Promise<{
  exists: boolean;
  imagePath: string | undefined;
  imageExists: boolean;
}> {
  const kind = data.publishedContentKind;
  const contentId = stringValue(data.publishedContentId);
  if (!isContentPlanningPublishedKind(kind) || !contentId) {
    return {exists: false, imagePath: undefined, imageExists: false};
  }
  const collection = kind === "news" ? "news" : "events";
  const snapshot = await db.collection(collection).doc(contentId).get();
  if (!snapshot.exists) return {exists: false, imagePath: undefined, imageExists: false};
  const imageURL = stringValue(snapshot.get("imageURL"));
  const imagePath = imageURL ? storageObjectPathFromDownloadURL(imageURL) : undefined;
  const imageMetadata = imagePath ? await storageObjectMetadata(imagePath) : {exists: false};
  return {exists: true, imagePath, imageExists: imageMetadata.exists};
}

async function draftMediaHasLiveReference(
  data: DocumentData,
  draftPath: string
): Promise<boolean> {
  const generatedURL = generatedImageDownloadURL(data);
  if (generatedURL && await hasLiveReferenceToImageURL(generatedURL)) return true;
  const live = await liveContentState(data);
  return live.exists && live.imagePath === draftPath;
}

async function hasLiveReferenceToImageURL(imageURL: string): Promise<boolean> {
  const [news, events] = await Promise.all([
    db.collection("news").where("imageURL", "==", imageURL).limit(1).get(),
    db.collection("events").where("imageURL", "==", imageURL).limit(1).get(),
  ]);
  return !news.empty || !events.empty;
}

async function storageObjectMetadata(objectPath: string): Promise<{
  exists: boolean;
  generation?: string;
  size: number;
}> {
  try {
    const [metadata] = await adminStorage.bucket().file(objectPath).getMetadata();
    return {
      exists: true,
      generation: metadata.generation === undefined
        ? undefined
        : String(metadata.generation),
      size: Number(metadata.size ?? 0),
    };
  } catch (error) {
    if (isNotFound(error)) return {exists: false, size: 0};
    throw error;
  }
}

function generatedImageStoragePath(data: DocumentData): string | undefined {
  return stringValue(recordValue(data.generatedImage)?.storagePath);
}

function generatedImageDownloadURL(data: DocumentData): string | undefined {
  return stringValue(recordValue(data.generatedImage)?.url);
}

function recordValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function isNotFound(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "code" in error &&
    (error as {code?: number}).code === 404);
}
