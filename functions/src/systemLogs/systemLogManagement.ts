import {HttpsError, onCall} from "firebase-functions/v2/https";

import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 1,
  timeoutSeconds: 300,
  invoker: "public" as const,
  enforceAppCheck: false,
};

const deleteBatchSize = 400;
const maximumDeletedLogs = 100_000;

export const clearSystemLogs = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    if (!isEmptyRequest(request.data)) {
      throw new HttpsError("invalid-argument", "Request payload must be empty.");
    }

    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);

    await auditLogRef().set(buildAuditLog({
      actionType: "systemLogsClearRequested",
      targetUserId: actor.uid,
      performedBy: actor.uid,
      reason: "Owner requested clearing the system journal.",
      previousValue: {status: "available"},
      newValue: {status: "clearRequested"},
    }));

    let deletedCount = 0;
    while (deletedCount < maximumDeletedLogs) {
      const snapshot = await db.collection("systemLogs").limit(deleteBatchSize).get();
      if (snapshot.empty) break;

      const writer = db.bulkWriter();
      for (const document of snapshot.docs) {
        writer.delete(document.ref);
      }
      await writer.close();
      deletedCount += snapshot.size;
    }

    if (deletedCount >= maximumDeletedLogs) {
      const remaining = await db.collection("systemLogs").limit(1).get();
      if (!remaining.empty) {
        throw new HttpsError(
          "resource-exhausted",
          "The journal exceeded the safe limit. Run the operation again to continue."
        );
      }
    }

    try {
      await auditLogRef().set(buildAuditLog({
        actionType: "systemLogsCleared",
        targetUserId: actor.uid,
        performedBy: actor.uid,
        reason: "Owner cleared the system journal.",
        previousValue: {systemLogCount: deletedCount},
        newValue: {systemLogCount: 0},
      }));
    } catch (error) {
      // The clear request is already audited. Do not report the destructive
      // operation as failed after the system logs were successfully removed.
      console.error("Failed to write systemLogsCleared completion audit.", error);
    }

    return {deletedCount};
  }
);

export const deleteSystemLog = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    const logId = requireLogId(request.data);
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return deleteSystemLogRecord(logId, actor.uid);
  }
);

export async function deleteSystemLogRecord(
  logId: string,
  actorUserId: string
): Promise<{deletedCount: number}> {
  const logReference = db.collection("systemLogs").doc(logId);
  const completionAuditReference = auditLogRef();

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(logReference);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "System log record was not found.");
    }

    transaction.delete(logReference);
    transaction.set(completionAuditReference, buildAuditLog({
      actionType: "systemLogDeleted",
      targetUserId: actorUserId,
      performedBy: actorUserId,
      reason: "Owner deleted one system journal record.",
      previousValue: {systemLogId: logId},
      newValue: {status: "deleted"},
    }));
  });

  return {deletedCount: 1};
}

export function isEmptyRequest(value: unknown): boolean {
  return value === undefined
    || value === null
    || (typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0);
}

function requireLogId(value: unknown): string {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "logId is required.");
  }
  const logId = (value as {logId?: unknown}).logId;
  if (typeof logId !== "string" || logId.trim().length === 0 || logId.length > 200) {
    throw new HttpsError("invalid-argument", "logId is invalid.");
  }
  return logId.trim();
}
