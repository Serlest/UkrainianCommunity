import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { type AuditActionType, auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import {
  resolveNotificationRecipients,
  type WriteNotificationInput,
  writeUserNotification,
} from "../notifications/notificationPayloads";
import {
  assertCanManageUsers,
  canAssignAppAdmin,
  canAssignAppModerator,
  canAssignGuideEditor,
  isActiveUser,
  type AccountStatus,
  type BlockState,
  type GlobalRole,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";

type ActiveGlobalRole = "owner" | "admin" | "moderator" | "user";

interface PlatformRoleChangeRequest {
  targetUserId: string;
  reason?: string;
}

interface PlatformRoleChangeResponse {
  targetUserId: string;
  previousGlobalRole: ActiveGlobalRole;
  newGlobalRole: ActiveGlobalRole;
  previousCanManageGuide: boolean;
  newCanManageGuide: boolean;
  updatedAt: string;
}

interface PlatformRoleMutation {
  actionType: AuditActionType;
  defaultReason: string;
  requiresUsableTarget: boolean;
  canPerform(actor: UserPermissionSnapshot): boolean;
  apply(current: UserRoleSnapshot): UserRoleUpdate;
}

interface UserRoleSnapshot extends UserPermissionSnapshot {
  globalRole: ActiveGlobalRole;
  canManageGuide: boolean;
}

interface UserRoleUpdate {
  globalRole: ActiveGlobalRole;
  canManageGuide: boolean;
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

function userRoleSnapshotFromData(uid: string, data: DocumentData | undefined): UserRoleSnapshot {
  return {
    uid,
    accountStatus: data?.accountStatus as AccountStatus | undefined,
    blockState: data?.blockState as BlockState | undefined,
    globalRole: normalizeGlobalRole(data?.globalRole),
    canManageGuide: data?.canManageGuide === true,
  };
}

function assertMutableTarget(
  target: UserRoleSnapshot,
  mutation: PlatformRoleMutation
): void {
  if (target.globalRole === "owner") {
    throw new HttpsError("permission-denied", "Owner role cannot be changed here.");
  }

  if (mutation.requiresUsableTarget && !isActiveUser(target)) {
    throw new HttpsError("failed-precondition", "Target user must have a usable account.");
  }
}

function assertChanged(current: UserRoleSnapshot, next: UserRoleUpdate): void {
  if (
    current.globalRole === next.globalRole
    && current.canManageGuide === next.canManageGuide
  ) {
    throw new HttpsError("failed-precondition", "Requested role change is already applied.");
  }
}

function platformRoleNotificationTitle(mutation: PlatformRoleMutation): string {
  switch (mutation.actionType) {
    case "appAdminAssigned":
      return "App admin role assigned";
    case "appAdminRemoved":
      return "App admin role removed";
    case "appModeratorAssigned":
      return "App moderator role assigned";
    case "appModeratorRemoved":
      return "App moderator role removed";
    case "guideEditorAssigned":
      return "Guide editor access assigned";
    case "guideEditorRemoved":
      return "Guide editor access removed";
    default:
      return "Role changed";
  }
}

function platformRoleNotificationMessage(mutation: PlatformRoleMutation): string {
  switch (mutation.actionType) {
    case "appAdminAssigned":
      return "Your platform role was changed to app admin.";
    case "appAdminRemoved":
      return "Your app admin role was removed.";
    case "appModeratorAssigned":
      return "Your platform role was changed to app moderator.";
    case "appModeratorRemoved":
      return "Your app moderator role was removed.";
    case "guideEditorAssigned":
      return "You can now manage guide content.";
    case "guideEditorRemoved":
      return "Your guide editor access was removed.";
    default:
      return "Your platform role was changed.";
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

function createPlatformRoleCallable(mutation: PlatformRoleMutation) {
  return onCall(callableOptions, async (request): Promise<PlatformRoleChangeResponse> => {
    const auth = requireAuth(request);
    const roleRequest = parsePlatformRoleChangeRequest(request.data);
    const actorSnapshot = await db.collection("users").doc(auth.uid).get();

    if (!actorSnapshot.exists) {
      throw new HttpsError("permission-denied", "User profile does not exist.");
    }

    const actorPermissions = userRoleSnapshotFromData(auth.uid, actorSnapshot.data());
    assertCanManageUsers(actorPermissions);

    if (!mutation.canPerform(actorPermissions)) {
      throw new HttpsError("permission-denied", "Platform role permissions are required.");
    }

    if (roleRequest.targetUserId === auth.uid) {
      throw new HttpsError("failed-precondition", "Self role changes are not allowed here.");
    }

    const targetReference = db.collection("users").doc(roleRequest.targetUserId);
    const committedAt = new Date().toISOString();
    let previousGlobalRole: ActiveGlobalRole = "user";
    let newGlobalRole: ActiveGlobalRole = "user";
    let previousCanManageGuide = false;
    let newCanManageGuide = false;

    await db.runTransaction(async (transaction) => {
      const targetSnapshot = await transaction.get(targetReference);

      if (!targetSnapshot.exists) {
        throw new HttpsError("not-found", "Target user does not exist.");
      }

      const target = userRoleSnapshotFromData(roleRequest.targetUserId, targetSnapshot.data());
      assertMutableTarget(target, mutation);

      const next = mutation.apply(target);
      assertChanged(target, next);

      previousGlobalRole = target.globalRole;
      newGlobalRole = next.globalRole;
      previousCanManageGuide = target.canManageGuide;
      newCanManageGuide = next.canManageGuide;

      transaction.update(targetReference, {
        globalRole: next.globalRole,
        canManageGuide: next.canManageGuide,
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
          canManageGuide: target.canManageGuide,
          accountStatus: target.accountStatus ?? "active",
          blockState: target.blockState ?? "active",
        },
        newValue: {
          globalRole: next.globalRole,
          canManageGuide: next.canManageGuide,
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
      title: platformRoleNotificationTitle(mutation),
      message: platformRoleNotificationMessage(mutation),
      severity: "info",
      actionType: "openProfile",
      actionTargetId: roleRequest.targetUserId,
      requiresPopup: false,
      actorUserId: auth.uid,
      metadata: {
        previousGlobalRole,
        newGlobalRole,
        previousCanManageGuide,
        newCanManageGuide,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "platformRole",
        mutation.actionType,
        roleRequest.targetUserId,
        newGlobalRole,
        String(newCanManageGuide),
      ].join(":"),
    });

    return {
      targetUserId: roleRequest.targetUserId,
      previousGlobalRole,
      newGlobalRole,
      previousCanManageGuide,
      newCanManageGuide,
      updatedAt: committedAt,
    };
  });
}

export const assignAppAdmin = createPlatformRoleCallable({
  actionType: "appAdminAssigned",
  defaultReason: "App admin assigned",
  requiresUsableTarget: true,
  canPerform: canAssignAppAdmin,
  apply(current) {
    return {
      globalRole: "admin",
      canManageGuide: current.canManageGuide,
    };
  },
});

export const removeAppAdmin = createPlatformRoleCallable({
  actionType: "appAdminRemoved",
  defaultReason: "App admin removed",
  requiresUsableTarget: false,
  canPerform: canAssignAppAdmin,
  apply(current) {
    return {
      globalRole: current.globalRole === "admin" ? "user" : current.globalRole,
      canManageGuide: current.canManageGuide,
    };
  },
});

export const assignAppModerator = createPlatformRoleCallable({
  actionType: "appModeratorAssigned",
  defaultReason: "App moderator assigned",
  requiresUsableTarget: true,
  canPerform: canAssignAppModerator,
  apply(current) {
    return {
      globalRole: "moderator",
      canManageGuide: current.canManageGuide,
    };
  },
});

export const removeAppModerator = createPlatformRoleCallable({
  actionType: "appModeratorRemoved",
  defaultReason: "App moderator removed",
  requiresUsableTarget: false,
  canPerform: canAssignAppModerator,
  apply(current) {
    return {
      globalRole: current.globalRole === "moderator" ? "user" : current.globalRole,
      canManageGuide: current.canManageGuide,
    };
  },
});

export const assignGuideEditor = createPlatformRoleCallable({
  actionType: "guideEditorAssigned",
  defaultReason: "Guide editor assigned",
  requiresUsableTarget: true,
  canPerform: canAssignGuideEditor,
  apply(current) {
    return {
      globalRole: current.globalRole,
      canManageGuide: true,
    };
  },
});

export const removeGuideEditor = createPlatformRoleCallable({
  actionType: "guideEditorRemoved",
  defaultReason: "Guide editor removed",
  requiresUsableTarget: false,
  canPerform: canAssignGuideEditor,
  apply(current) {
    return {
      globalRole: current.globalRole,
      canManageGuide: false,
    };
  },
});
