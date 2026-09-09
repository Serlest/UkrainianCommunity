import {FieldPath} from "firebase-admin/firestore";
import {CheckedBulkWriter} from "../firebase/checkedBulkWriter";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {requireLegacyCallableUser as requireVerifiedActiveUser} from "../auth/legacyCallableContext";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 4,
  timeoutSeconds: 300,
  invoker: "public" as const,
  enforceAppCheck: false,
};

const feedbackBatchSize = 200;
const maximumDeletedFeedback = 10_000;

export const clearMyFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    await requireVerifiedActiveUser(request);
    if (!isEmptyRequest(request.data)) {
      throw new HttpsError("invalid-argument", "Request payload must be empty.");
    }
    throw new HttpsError(
      "permission-denied",
      "Users cannot delete their own feedback records."
    );
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
      await deleteFeedbackRecords([feedbackDocument]);
      return {deletedCount: 0};
    }

    const deletion = await deleteFeedbackRecords([feedbackDocument]);
    if (deletion.protectedCount > 0) {
      throw new HttpsError(
        "failed-precondition",
        "DSA records cannot be deleted before their regulatory retention expires."
      );
    }
    await recordOwnerDeletionAudit("feedbackDeleted", actor.uid, {feedbackId});
    return {deletedCount: deletion.deletedCount};
  }
);

export const deleteMyFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    await requireVerifiedActiveUser(request);
    requireFeedbackId(request.data);
    throw new HttpsError(
      "permission-denied",
      "Users cannot delete their own feedback records."
    );
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
    let deletedCount = 0;
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    while (deletedCount < maximumDeletedFeedback) {
      const pageLimit = Math.min(feedbackBatchSize, maximumDeletedFeedback - deletedCount);
      let query = db.collection("feedback")
        .orderBy(FieldPath.documentId())
        .limit(pageLimit);
      if (cursor) query = query.startAfter(cursor);
      const snapshot = await query.get();
      if (snapshot.empty) break;
      const deletion = await deleteFeedbackRecords(snapshot.docs.map((document) => document.ref));
      deletedCount += deletion.deletedCount;
      cursor = snapshot.docs[snapshot.docs.length - 1];
      if (snapshot.size < pageLimit) break;
    }

    if (deletedCount >= maximumDeletedFeedback) {
      let remainingQuery = db.collection("feedback")
        .orderBy(FieldPath.documentId())
        .limit(1);
      if (cursor) remainingQuery = remainingQuery.startAfter(cursor);
      const remaining = await remainingQuery.get();
      if (!remaining.empty) {
        throw new HttpsError("resource-exhausted", "Too many feedback records. Run the operation again to continue.");
      }
    }

    await recordOwnerDeletionAudit("feedbackInboxCleared", actor.uid, {
      deletedCount,
    });
    return {deletedCount};
  }
);

async function deleteFeedbackDocuments(
  feedbackDocuments: FirebaseFirestore.DocumentReference[]
): Promise<void> {
  const children: FirebaseFirestore.DocumentReference[] = [];
  for (const feedbackDocument of feedbackDocuments) {
    const messages = await feedbackDocument.collection("messages").get();
    children.push(...messages.docs.map(document => document.ref));
  }
  const childWriter = new CheckedBulkWriter();
  children.forEach(reference => childWriter.delete(reference));
  await childWriter.close();
  // Keep the root available for retry until every dependent deletion succeeds.
  const parentWriter = new CheckedBulkWriter();
  feedbackDocuments.forEach(reference => parentWriter.delete(reference));
  await parentWriter.close();
}

export interface DeleteFeedbackRecordsResult {
  deletedCount: number;
  protectedCount: number;
}

export async function deleteFeedbackRecords(
  feedbackDocuments: FirebaseFirestore.DocumentReference[],
  options: {allowDsaDeletion?: boolean} = {}
): Promise<DeleteFeedbackRecordsResult> {
  if (feedbackDocuments.length === 0) return {deletedCount: 0, protectedCount: 0};

  const snapshots = await Promise.all(feedbackDocuments.map(document => document.get()));
  const existing = snapshots.filter(snapshot => snapshot.exists);
  const canonicalDsaCases = options.allowDsaDeletion || existing.length === 0 ? [] :
    await db.getAll(...existing.map(snapshot => db.collection("dsaCases").doc(snapshot.id)));
  const protectedDocuments = options.allowDsaDeletion ? [] : existing.filter((snapshot, index) => {
    const dsaCase = snapshot.get("dsaCase");
    return (typeof dsaCase === "object" && dsaCase !== null)
      || canonicalDsaCases[index]?.exists === true;
  });
  const protectedPaths = new Set(protectedDocuments.map(snapshot => snapshot.ref.path));
  const deletable = existing
    .filter(snapshot => !protectedPaths.has(snapshot.ref.path))
    .map(snapshot => snapshot.ref);

  if (deletable.length > 0) {
    await deleteFeedbackNotifications(deletable.map(document => document.id));
    await deleteFeedbackDocuments(deletable);
  }

  return {
    deletedCount: deletable.length,
    protectedCount: protectedDocuments.length,
  };
}

async function deleteFeedbackNotifications(feedbackIds: string[]): Promise<void> {
  for (let index = 0; index < feedbackIds.length; index += 10) {
    const idBatch = feedbackIds.slice(index, index + 10);
    const notificationSnapshot = await db.collectionGroup("notificationInbox")
      .where("sourceId", "in", idBatch)
      .get();

    if (notificationSnapshot.empty) continue;
    const writer = new CheckedBulkWriter();
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
