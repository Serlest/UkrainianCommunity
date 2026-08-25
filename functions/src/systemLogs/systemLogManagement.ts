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

export function isEmptyRequest(value: unknown): boolean {
  return value === undefined
    || value === null
    || (typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0);
}
