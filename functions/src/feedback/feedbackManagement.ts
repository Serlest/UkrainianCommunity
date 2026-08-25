import {HttpsError, onCall} from "firebase-functions/v2/https";

import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 4,
  timeoutSeconds: 300,
  invoker: "public" as const,
};

const feedbackBatchSize = 200;
const maximumDeletedFeedback = 10_000;

export const clearMyFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    if (!isEmptyRequest(request.data)) {
      throw new HttpsError("invalid-argument", "Request payload must be empty.");
    }

    const actor = await requireVerifiedActiveUser(request);
    const deletedFeedbackIds: string[] = [];

    while (deletedFeedbackIds.length < maximumDeletedFeedback) {
      const feedbackSnapshot = await db.collection("feedback")
        .where("userId", "==", actor.uid)
        .limit(feedbackBatchSize)
        .get();

      if (feedbackSnapshot.empty) break;

      const writer = db.bulkWriter();
      for (const feedbackDocument of feedbackSnapshot.docs) {
        const messagesSnapshot = await feedbackDocument.ref.collection("messages").get();
        for (const messageDocument of messagesSnapshot.docs) {
          writer.delete(messageDocument.ref);
        }
        writer.delete(feedbackDocument.ref);
        deletedFeedbackIds.push(feedbackDocument.id);
      }
      await writer.close();
    }

    if (deletedFeedbackIds.length >= maximumDeletedFeedback) {
      const remaining = await db.collection("feedback")
        .where("userId", "==", actor.uid)
        .limit(1)
        .get();
      if (!remaining.empty) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many feedback records. Run the operation again to continue."
        );
      }
    }

    await deleteFeedbackNotifications(deletedFeedbackIds);
    return {deletedCount: deletedFeedbackIds.length};
  }
);

export const deleteFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    const feedbackId = requireFeedbackId(request.data);
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);

    const feedbackDocument = db.collection("feedback").doc(feedbackId);
    const snapshot = await feedbackDocument.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Feedback record was not found.");
    }

    await deleteFeedbackDocuments([feedbackDocument]);
    await deleteFeedbackNotifications([feedbackId]);
    await recordOwnerDeletionAudit("feedbackDeleted", actor.uid, {feedbackId});
    return {deletedCount: 1};
  }
);

export const deleteMyFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    const feedbackId = requireFeedbackId(request.data);
    const actor = await requireVerifiedActiveUser(request);
    const feedbackDocument = db.collection("feedback").doc(feedbackId);
    const snapshot = await feedbackDocument.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "Feedback record was not found.");
    }
    if (snapshot.get("userId") !== actor.uid) {
      throw new HttpsError("permission-denied", "You can delete only your own feedback.");
    }

    await deleteFeedbackDocuments([feedbackDocument]);
    await deleteFeedbackNotifications([feedbackId]);
    return {deletedCount: 1};
  }
);

export const clearFeedbackInbox = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    if (!isEmptyRequest(request.data)) {
      throw new HttpsError("invalid-argument", "Request payload must be empty.");
    }

    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    const deletedFeedbackIds: string[] = [];

    while (deletedFeedbackIds.length < maximumDeletedFeedback) {
      const snapshot = await db.collection("feedback").limit(feedbackBatchSize).get();
      if (snapshot.empty) break;
      await deleteFeedbackDocuments(snapshot.docs.map((document) => document.ref));
      deletedFeedbackIds.push(...snapshot.docs.map((document) => document.id));
    }

    if (deletedFeedbackIds.length >= maximumDeletedFeedback) {
      const remaining = await db.collection("feedback").limit(1).get();
      if (!remaining.empty) {
        throw new HttpsError("resource-exhausted", "Too many feedback records. Run the operation again to continue.");
      }
    }

    await deleteFeedbackNotifications(deletedFeedbackIds);
    await recordOwnerDeletionAudit("feedbackInboxCleared", actor.uid, {
      deletedCount: deletedFeedbackIds.length,
    });
    return {deletedCount: deletedFeedbackIds.length};
  }
);

async function deleteFeedbackDocuments(
  feedbackDocuments: FirebaseFirestore.DocumentReference[]
): Promise<void> {
  const writer = db.bulkWriter();
  for (const feedbackDocument of feedbackDocuments) {
    const messagesSnapshot = await feedbackDocument.collection("messages").get();
    for (const messageDocument of messagesSnapshot.docs) {
      writer.delete(messageDocument.ref);
    }
    writer.delete(feedbackDocument);
  }
  await writer.close();
}

async function deleteFeedbackNotifications(feedbackIds: string[]): Promise<void> {
  for (let index = 0; index < feedbackIds.length; index += 10) {
    const idBatch = feedbackIds.slice(index, index + 10);
    const notificationSnapshot = await db.collectionGroup("notificationInbox")
      .where("sourceId", "in", idBatch)
      .get();

    if (notificationSnapshot.empty) continue;
    const writer = db.bulkWriter();
    for (const notificationDocument of notificationSnapshot.docs) {
      if (notificationDocument.get("sourceType") === "feedback") {
        writer.delete(notificationDocument.ref);
      }
    }
    await writer.close();
  }
}

function isEmptyRequest(value: unknown): boolean {
  return value === undefined
    || value === null
    || (typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0);
}

function requireFeedbackId(value: unknown): string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "feedbackId is required.");
  }
  const feedbackId = (value as {feedbackId?: unknown}).feedbackId;
  if (typeof feedbackId !== "string" || feedbackId.trim().length === 0 || feedbackId.length > 200) {
    throw new HttpsError("invalid-argument", "feedbackId is invalid.");
  }
  return feedbackId.trim();
}

async function recordOwnerDeletionAudit(
  actionType: "feedbackDeleted" | "feedbackInboxCleared",
  actorUid: string,
  previousValue: Record<string, unknown>
): Promise<void> {
  try {
    await auditLogRef().set(buildAuditLog({
      actionType,
      targetUserId: actorUid,
      performedBy: actorUid,
      reason: "Owner deleted feedback records.",
      previousValue,
      newValue: {status: "deleted"},
    }));
  } catch (error) {
    // The destructive operation already succeeded; an audit write failure must
    // not make the client retry and report the successful deletion as failed.
    console.error("Failed to write feedback deletion audit.", error);
  }
}
