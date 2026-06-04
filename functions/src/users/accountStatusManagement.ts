import { FieldValue, Timestamp, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { type AuditActionType, auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import {
  type NotificationSeverity,
  writeUserNotification,
} from "../notifications/notificationPayloads";
import {
  assertOwner,
  type AccountStatus,
  type BlockState,
  type GlobalRole,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";

type ActiveGlobalRole = "owner" | "admin" | "moderator" | "user";

interface AccountStatusChangeRequest {
  targetUserId: string;
  until?: string;
  reason?: string;
}

interface AccountStatusChangeResponse {
  targetUserId: string;
  previousAccountStatus: AccountStatus;
  newAccountStatus: AccountStatus;
  previousBlockState: BlockState;
  newBlockState: BlockState;
  warningCount: number;
  banExpiresAt: string | null;
  updatedAt: string;
}

interface AccountStatusSnapshot extends UserPermissionSnapshot {
  accountStatus: AccountStatus;
  blockState: BlockState;
  globalRole: ActiveGlobalRole;
  warningCount: number;
  banExpiresAt: Timestamp | null;
}

interface AccountStatusUpdate {
  accountStatus: AccountStatus;
  blockState: BlockState;
  warningCount?: FieldValue;
  banExpiresAt: Timestamp | FieldValue | null;
}

interface AccountStatusMutation {
  actionType: AuditActionType;
  defaultReason: string;
  statusMessage(reason: string): string;
  apply(current: AccountStatusSnapshot, request: AccountStatusChangeRequest): AccountStatusUpdate;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const schedulerOptions = {
  schedule: "every 1 hours",
  timeZone: "Europe/Vienna",
  region: "europe-west3",
  maxInstances: 1,
};

const expiredSuspensionBatchSize = 100;
const systemActor = "system";
const temporarySuspensionExpiredReason = "Temporary suspension expired";

function parseAccountStatusChangeRequest(data: unknown): AccountStatusChangeRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    targetUserId: normalizedRequiredString(data.targetUserId, "targetUserId"),
    until: optionalTrimmedString(data.until, "until"),
    reason: optionalTrimmedString(data.reason, "reason"),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedRequiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return trimmedValue;
}

function optionalTrimmedString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : undefined;
}

function normalizeGlobalRole(value: unknown): ActiveGlobalRole {
  switch (value as GlobalRole | undefined) {
    case "owner":
      return "owner";
    case "admin":
      return "admin";
    case "moderator":
      return "moderator";
    case "user":
    case "topAdmin":
    case "appModerator":
    default:
      return "user";
  }
}

function normalizeAccountStatus(value: unknown): AccountStatus {
  switch (value as string | undefined) {
    case "warned":
      return "warned";
    case "suspendedUntil":
    case "temporarilyBanned":
      return "suspendedUntil";
    case "bannedPermanent":
    case "permanentlyBanned":
      return "bannedPermanent";
    case "deactivated":
      return "deactivated";
    case "active":
    default:
      return "active";
  }
}

function normalizeBlockState(value: unknown, isBlocked: unknown): BlockState {
  switch (value as string | undefined) {
    case "warned":
      return "warned";
    case "suspendedUntil":
    case "blocked":
      return "suspendedUntil";
    case "bannedPermanent":
      return "bannedPermanent";
    case "deactivated":
      return "deactivated";
    case "active":
      return "active";
    default:
      return isBlocked === true ? "suspendedUntil" : "active";
  }
}

function accountStatusSnapshotFromData(
  uid: string,
  data: DocumentData | undefined
): AccountStatusSnapshot {
  const blockState = normalizeBlockState(data?.blockState, data?.isBlocked);

  return {
    uid,
    accountStatus: normalizeAccountStatus(data?.accountStatus ?? blockState),
    blockState,
    globalRole: normalizeGlobalRole(data?.globalRole),
    warningCount: typeof data?.warningCount === "number" ? data.warningCount : 0,
    banExpiresAt: data?.banExpiresAt instanceof Timestamp ? data.banExpiresAt : null,
  };
}

function parseFutureTimestamp(value: string | undefined): Timestamp {
  if (!value) {
    throw new HttpsError("invalid-argument", "until is required for suspension.");
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", "until must be a valid date.");
  }

  if (date <= new Date()) {
    throw new HttpsError("invalid-argument", "until must be in the future.");
  }

  return Timestamp.fromDate(date);
}

function assertMutableTarget(target: AccountStatusSnapshot): void {
  if (target.globalRole === "owner") {
    throw new HttpsError("permission-denied", "App Owner accounts cannot be changed here.");
  }
}

function isBlockedStatus(status: AccountStatus): boolean {
  return status === "suspendedUntil"
    || status === "bannedPermanent"
    || status === "deactivated";
}

function timestampToISO(timestamp: Timestamp | null): string | null {
  return timestamp?.toDate().toISOString() ?? null;
}

function accountStatusNotificationTitle(status: AccountStatus): string {
  switch (status) {
    case "active":
      return "Account access restored";
    case "warned":
      return "Account warning issued";
    case "suspendedUntil":
      return "Account temporarily suspended";
    case "bannedPermanent":
      return "Account permanently blocked";
    case "deactivated":
      return "Account deactivated";
  }
}

function accountStatusNotificationSeverity(status: AccountStatus): NotificationSeverity {
  return status === "active" ? "success" : "warning";
}

function createAccountStatusCallable(mutation: AccountStatusMutation) {
  return onCall(callableOptions, async (request): Promise<AccountStatusChangeResponse> => {
    const auth = requireAuth(request);
    const statusRequest = parseAccountStatusChangeRequest(request.data);

    if (statusRequest.targetUserId === auth.uid) {
      throw new HttpsError("failed-precondition", "Self account status changes are not allowed.");
    }

    const actorSnapshot = await db.collection("users").doc(auth.uid).get();
    if (!actorSnapshot.exists) {
      throw new HttpsError("permission-denied", "User profile does not exist.");
    }

    const actorPermissions = accountStatusSnapshotFromData(auth.uid, actorSnapshot.data());
    assertOwner(actorPermissions);

    const targetReference = db.collection("users").doc(statusRequest.targetUserId);
    const committedAt = new Date().toISOString();
    let previousAccountStatus: AccountStatus = "active";
    let newAccountStatus: AccountStatus = "active";
    let previousBlockState: BlockState = "active";
    let newBlockState: BlockState = "active";
    let warningCount = 0;
    let banExpiresAt: string | null = null;
    const notificationReason = statusRequest.reason ?? mutation.defaultReason;

    await db.runTransaction(async (transaction) => {
      const targetSnapshot = await transaction.get(targetReference);

      if (!targetSnapshot.exists) {
        throw new HttpsError("not-found", "Target user does not exist.");
      }

      const target = accountStatusSnapshotFromData(
        statusRequest.targetUserId,
        targetSnapshot.data()
      );
      assertMutableTarget(target);

      const reason = notificationReason;
      const next = mutation.apply(target, statusRequest);
      const nextWarningCount = next.warningCount ? target.warningCount + 1 : target.warningCount;
      const nextBanTimestamp = next.banExpiresAt instanceof Timestamp ? next.banExpiresAt : null;

      previousAccountStatus = target.accountStatus;
      previousBlockState = target.blockState;
      newAccountStatus = next.accountStatus;
      newBlockState = next.blockState;
      warningCount = nextWarningCount;
      banExpiresAt = timestampToISO(nextBanTimestamp);

      transaction.update(targetReference, {
        accountStatus: next.accountStatus,
        blockState: next.blockState,
        banExpiresAt: next.banExpiresAt,
        warningCount: next.warningCount ?? target.warningCount,
        isBlocked: isBlockedStatus(next.accountStatus),
        statusReason: reason,
        statusMessage: mutation.statusMessage(reason),
        statusUpdatedAt: FieldValue.serverTimestamp(),
        statusUpdatedBy: auth.uid,
        statusAcknowledgedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(auditLogRef(), buildAuditLog({
        actionType: mutation.actionType,
        targetUserId: statusRequest.targetUserId,
        performedBy: auth.uid,
        reason,
        previousValue: {
          accountStatus: target.accountStatus,
          blockState: target.blockState,
          warningCount: target.warningCount,
          banExpiresAt: timestampToISO(target.banExpiresAt),
        },
        newValue: {
          accountStatus: next.accountStatus,
          blockState: next.blockState,
          warningCount: nextWarningCount,
          banExpiresAt,
          statusUpdatedAt: committedAt,
          statusUpdatedBy: auth.uid,
        },
      }));
    });

    await writeUserNotification({
      targetUserId: statusRequest.targetUserId,
      type: "accountStatusChanged",
      title: accountStatusNotificationTitle(newAccountStatus),
      message: mutation.statusMessage(notificationReason),
      severity: accountStatusNotificationSeverity(newAccountStatus),
      actionType: "openProfile",
      actionTargetId: statusRequest.targetUserId,
      requiresPopup: false,
      actorUserId: auth.uid,
      sourceType: "account",
      sourceId: statusRequest.targetUserId,
      metadata: {
        previousAccountStatus,
        newAccountStatus,
        previousBlockState,
        newBlockState,
        warningCount,
        banExpiresAt,
        reason: notificationReason,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "accountStatus",
        statusRequest.targetUserId,
        newAccountStatus,
        String(warningCount),
        banExpiresAt ?? "none",
      ].join(":"),
    });

    return {
      targetUserId: statusRequest.targetUserId,
      previousAccountStatus,
      newAccountStatus,
      previousBlockState,
      newBlockState,
      warningCount,
      banExpiresAt,
      updatedAt: committedAt,
    };
  });
}

export const warnUser = createAccountStatusCallable({
  actionType: "userWarned",
  defaultReason: "Account warning issued",
  statusMessage: (reason) => `Your account received a warning. Reason: ${reason}`,
  apply() {
    return {
      accountStatus: "warned",
      blockState: "warned",
      warningCount: FieldValue.increment(1),
      banExpiresAt: null,
    };
  },
});

export const suspendUser = createAccountStatusCallable({
  actionType: "userSuspended",
  defaultReason: "Account temporarily suspended",
  statusMessage: (reason) => `Your account is temporarily suspended. Reason: ${reason}`,
  apply(_current, request) {
    return {
      accountStatus: "suspendedUntil",
      blockState: "suspendedUntil",
      banExpiresAt: parseFutureTimestamp(request.until),
    };
  },
});

export const banUser = createAccountStatusCallable({
  actionType: "userBanned",
  defaultReason: "Account permanently blocked",
  statusMessage: (reason) => `Your account is permanently blocked. Reason: ${reason}`,
  apply() {
    return {
      accountStatus: "bannedPermanent",
      blockState: "bannedPermanent",
      banExpiresAt: null,
    };
  },
});

export const deactivateUser = createAccountStatusCallable({
  actionType: "userDeactivated",
  defaultReason: "Account deactivated",
  statusMessage: (reason) => `Your account is deactivated. Reason: ${reason}`,
  apply() {
    return {
      accountStatus: "deactivated",
      blockState: "deactivated",
      banExpiresAt: null,
    };
  },
});

export const restoreUser = createAccountStatusCallable({
  actionType: "userRestored",
  defaultReason: "Account restored",
  statusMessage: (reason) => `Your account access has been restored. Reason: ${reason}`,
  apply() {
    return {
      accountStatus: "active",
      blockState: "active",
      banExpiresAt: null,
    };
  },
});

export const restoreExpiredTemporarySuspensions = onSchedule(schedulerOptions, async () => {
  const now = Timestamp.now();
  const committedAt = new Date().toISOString();
  const expiredUsersSnapshot = await db.collection("users")
    .where("accountStatus", "==", "suspendedUntil")
    .where("blockState", "==", "suspendedUntil")
    .where("banExpiresAt", "<=", now)
    .orderBy("banExpiresAt", "asc")
    .limit(expiredSuspensionBatchSize)
    .get();

  if (expiredUsersSnapshot.empty) {
    return;
  }

  const batch = db.batch();
  let restoredCount = 0;
  const restoredUsers: Array<{
    userId: string;
    warningCount: number;
    expiredAt: string | null;
  }> = [];

  for (const userSnapshot of expiredUsersSnapshot.docs) {
    const target = accountStatusSnapshotFromData(userSnapshot.id, userSnapshot.data());

    if (
      target.accountStatus !== "suspendedUntil"
      || target.blockState !== "suspendedUntil"
      || !target.banExpiresAt
      || target.banExpiresAt.toMillis() > now.toMillis()
    ) {
      continue;
    }

    batch.update(userSnapshot.ref, {
      accountStatus: "active",
      blockState: "active",
      banExpiresAt: null,
      isBlocked: false,
      statusReason: temporarySuspensionExpiredReason,
      statusMessage: `Your account access has been restored. Reason: ${
        temporarySuspensionExpiredReason
      }`,
      statusUpdatedAt: FieldValue.serverTimestamp(),
      statusUpdatedBy: systemActor,
      statusAcknowledgedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    batch.set(auditLogRef(), buildAuditLog({
      actionType: "userSuspensionExpired",
      targetUserId: userSnapshot.id,
      performedBy: systemActor,
      reason: temporarySuspensionExpiredReason,
      previousValue: {
        accountStatus: target.accountStatus,
        blockState: target.blockState,
        warningCount: target.warningCount,
        banExpiresAt: timestampToISO(target.banExpiresAt),
      },
      newValue: {
        accountStatus: "active",
        blockState: "active",
        warningCount: target.warningCount,
        banExpiresAt: null,
        statusUpdatedAt: committedAt,
        statusUpdatedBy: systemActor,
      },
    }));

    restoredCount += 1;
    restoredUsers.push({
      userId: userSnapshot.id,
      warningCount: target.warningCount,
      expiredAt: timestampToISO(target.banExpiresAt),
    });
  }

  if (restoredCount > 0) {
    await batch.commit();
    await Promise.all(restoredUsers.map((restoredUser) => writeUserNotification({
      targetUserId: restoredUser.userId,
      type: "accountStatusChanged",
      title: accountStatusNotificationTitle("active"),
      message: `Your account access has been restored. Reason: ${
        temporarySuspensionExpiredReason
      }`,
      severity: "success",
      actionType: "openProfile",
      actionTargetId: restoredUser.userId,
      requiresPopup: false,
      actorUserId: systemActor,
      sourceType: "account",
      sourceId: restoredUser.userId,
      metadata: {
        previousAccountStatus: "suspendedUntil",
        newAccountStatus: "active",
        previousBlockState: "suspendedUntil",
        newBlockState: "active",
        warningCount: restoredUser.warningCount,
        banExpiresAt: null,
        reason: temporarySuspensionExpiredReason,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "accountStatus",
        restoredUser.userId,
        "active",
        "expiredSuspension",
        restoredUser.expiredAt ?? "none",
      ].join(":"),
    })));
  }
});
