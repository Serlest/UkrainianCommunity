import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { type AuditActionType, auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireVerifiedActiveUser } from "../auth/context";
import { db } from "../firebase/admin";
import {
  resolveNotificationRecipients,
  type WriteNotificationInput,
  writeUserNotification,
} from "../notifications/notificationPayloads";
import {
  canAssignAppAdmin,
  type AccountStatus,
  type BlockState,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";
import {assertUsableTargetUser, getTargetAuthSnapshot} from "./targetUserValidation";

type ActiveGlobalRole = "owner" | "admin" | "user";

interface PlatformRoleChangeRequest {
  targetUserId: string;
  reason?: string;
}

interface PlatformRoleChangeResponse {
  targetUserId: string;
  previousGlobalRole: ActiveGlobalRole;
  newGlobalRole: ActiveGlobalRole;
  updatedAt: string;
}

type AppAdminActionType = Extract<
  AuditActionType,
  "appAdminAssigned" | "appAdminRemoved"
>;

interface AppAdminRoleMutation {
  actionType: AppAdminActionType;
  defaultReason: string;
  notificationTitle: string;
  notificationMessage: string;
  requiresUsableTarget: boolean;
  nextGlobalRole(current: ActiveGlobalRole): ActiveGlobalRole;
}

interface UserRoleSnapshot extends UserPermissionSnapshot {
  globalRole: ActiveGlobalRole;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

function parsePlatformRoleChangeRequest(data: unknown): PlatformRoleChangeRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    targetUserId: normalizedRequiredString(data.targetUserId, "targetUserId"),
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
  switch (value) {
    case "owner":
      return "owner";
    case "admin":
      return "admin";
    case "user":
    case "moderator":
    case "topAdmin":
    case "appModerator":
    default:
      return "user";
  }
}

function userRoleSnapshotFromData(uid: string, data: DocumentData | undefined): UserRoleSnapshot {
  return {
    uid,
    accountStatus: data?.accountStatus as AccountStatus | undefined,
    blockState: data?.blockState as BlockState | undefined,
    globalRole: normalizeGlobalRole(data?.globalRole),
  };
}

function assertMutableTarget(
  target: UserRoleSnapshot
): void {
  if (target.globalRole === "owner") {
    throw new HttpsError("permission-denied", "Owner role cannot be changed here.");
  }
}

function assertChanged(current: UserRoleSnapshot, nextGlobalRole: ActiveGlobalRole): void {
  if (current.globalRole === nextGlobalRole) {
    throw new HttpsError("failed-precondition", "Requested role change is already applied.");
  }
}

async function writeNotificationIfRecipientEligible(
  input: WriteNotificationInput
): Promise<void> {
  const recipients = await resolveNotificationRecipients([input.targetUserId]);
  if (!recipients.inboxRecipientIds.includes(input.targetUserId)) {
    return;
  }

  await writeUserNotification(input);
}

function createAppAdminRoleCallable(mutation: AppAdminRoleMutation) {
  return onCall(callableOptions, async (request): Promise<PlatformRoleChangeResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const roleRequest = parsePlatformRoleChangeRequest(request.data);
    if (!canAssignAppAdmin(auth.permissions)) {
      throw new HttpsError("permission-denied", "App owner permissions are required.");
    }

    if (roleRequest.targetUserId === auth.uid) {
      throw new HttpsError("failed-precondition", "Self role changes are not allowed here.");
    }

    const targetAuth = mutation.requiresUsableTarget
      ? await getTargetAuthSnapshot(roleRequest.targetUserId)
      : undefined;
    const targetReference = db.collection("users").doc(roleRequest.targetUserId);
    const committedAt = new Date().toISOString();
    let previousGlobalRole: ActiveGlobalRole = "user";
    let newGlobalRole: ActiveGlobalRole = "user";

    await db.runTransaction(async (transaction) => {
      const targetSnapshot = await transaction.get(targetReference);

      if (!targetSnapshot.exists) {
        throw new HttpsError("not-found", "Target user does not exist.");
      }

      const target = userRoleSnapshotFromData(roleRequest.targetUserId, targetSnapshot.data());
      assertMutableTarget(target);
      if (targetAuth) {
        assertUsableTargetUser(targetAuth, target);
      }

      const nextRole = mutation.nextGlobalRole(target.globalRole);
      assertChanged(target, nextRole);

      previousGlobalRole = target.globalRole;
      newGlobalRole = nextRole;

      transaction.update(targetReference, {
        globalRole: nextRole,
        roleUpdatedAt: FieldValue.serverTimestamp(),
        roleUpdatedBy: auth.uid,
      });

      transaction.set(auditLogRef(), buildAuditLog({
        actionType: mutation.actionType,
        targetUserId: roleRequest.targetUserId,
        performedBy: auth.uid,
        reason: roleRequest.reason ?? mutation.defaultReason,
        previousValue: {
          globalRole: target.globalRole,
          accountStatus: target.accountStatus ?? "active",
          blockState: target.blockState ?? "active",
        },
        newValue: {
          globalRole: nextRole,
          roleUpdatedAt: committedAt,
          roleUpdatedBy: auth.uid,
        },
      }));
    });

    await writeNotificationIfRecipientEligible({
      notificationId: [
        "roleChanged",
        roleRequest.targetUserId,
        committedAt,
        roleRequest.targetUserId,
      ].join("_"),
      targetUserId: roleRequest.targetUserId,
      type: "roleChanged",
      title: mutation.notificationTitle,
      message: mutation.notificationMessage,
      severity: "info",
      actionType: "openProfile",
      actionTargetId: roleRequest.targetUserId,
      requiresPopup: false,
      actorUserId: auth.uid,
      metadata: {
        previousGlobalRole,
        newGlobalRole,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "platformRole",
        mutation.actionType,
        roleRequest.targetUserId,
        newGlobalRole,
      ].join(":"),
    });

    return {
      targetUserId: roleRequest.targetUserId,
      previousGlobalRole,
      newGlobalRole,
      updatedAt: committedAt,
    };
  });
}

export const assignAppAdmin = createAppAdminRoleCallable({
  actionType: "appAdminAssigned",
  defaultReason: "App admin assigned",
  notificationTitle: "App admin role assigned",
  notificationMessage: "Your platform role was changed to app admin.",
  requiresUsableTarget: true,
  nextGlobalRole() {
    return "admin";
  },
});

export const removeAppAdmin = createAppAdminRoleCallable({
  actionType: "appAdminRemoved",
  defaultReason: "App admin removed",
  notificationTitle: "App admin role removed",
  notificationMessage: "Your app admin role was removed.",
  requiresUsableTarget: false,
  nextGlobalRole(current) {
    return current === "admin" ? "user" : current;
  },
});
