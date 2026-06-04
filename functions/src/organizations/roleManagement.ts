import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import { writeUserNotification } from "../notifications/notificationPayloads";
import {
  canManageOrganizationRoles,
  type OrganizationRole,
  type OrganizationRoleSnapshot,
} from "../permissions/organizationPermissions";
import { assertOwner, getUserPermissions } from "../permissions/userPermissions";

type AssignableOrganizationRole = "communityAdmin" | "communityModerator";
type OrganizationRoleResult = "none" | OrganizationRole;

interface OrganizationRoleChangeRequest {
  organizationId: string;
  targetUserId: string;
  reason?: string;
}

interface OrganizationRoleChangeResponse {
  organizationId: string;
  targetUserId: string;
  previousRole: OrganizationRoleResult;
  newRole: OrganizationRoleResult;
  updatedAt: string;
}

interface OrganizationOwnershipTransferResponse {
  organizationId: string;
  previousOwnerId: string | null;
  newOwnerId: string;
  updatedAt: string;
}

interface RoleMutation {
  targetRole: AssignableOrganizationRole;
  isRemoval: boolean;
  defaultReason: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

function parseRoleChangeRequest(data: unknown): OrganizationRoleChangeRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const organizationId = normalizedRequiredString(data.organizationId, "organizationId");
  const targetUserId = normalizedRequiredString(data.targetUserId, "targetUserId");
  const reason = optionalTrimmedString(data.reason, "reason");

  return {
    organizationId,
    targetUserId,
    reason,
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

function organizationRolesFromData(
  organizationId: string,
  data: DocumentData | undefined
): OrganizationRoleSnapshot {
  return {
    organizationId,
    ownerId: typeof data?.ownerId === "string" ? data.ownerId : undefined,
    adminIds: stringArray(data?.adminIds),
    moderatorIds: stringArray(data?.moderatorIds),
  };
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function roleForUser(roles: OrganizationRoleSnapshot, uid: string): OrganizationRoleResult {
  if (roles.ownerId === uid) {
    return "communityOwner";
  }

  if (roles.adminIds.includes(uid)) {
    return "communityAdmin";
  }

  if (roles.moderatorIds.includes(uid)) {
    return "communityModerator";
  }

  return "none";
}

function sortedUniqueUserIds(userIds: string[]): string[] {
  return Array.from(new Set(userIds)).sort();
}

function withoutUser(userIds: string[], uid: string): string[] {
  return userIds.filter((userId) => userId !== uid);
}

function organizationRoleName(role: OrganizationRoleResult): string {
  switch (role) {
    case "communityOwner":
      return "organization owner";
    case "communityAdmin":
      return "organization admin";
    case "communityModerator":
      return "organization moderator";
    case "none":
      return "organization role";
  }
}

function createRoleCallable(mutation: RoleMutation) {
  return onCall(callableOptions, async (request): Promise<OrganizationRoleChangeResponse> => {
    const auth = requireAuth(request);
    const roleRequest = parseRoleChangeRequest(request.data);
    const actorPermissions = await getUserPermissions(auth.uid);
    const organizationReference = db.collection("organizations").doc(roleRequest.organizationId);
    const committedAt = new Date().toISOString();
    let previousRole: OrganizationRoleResult = "none";
    const newRole: OrganizationRoleResult = mutation.isRemoval ? "none" : mutation.targetRole;

    await db.runTransaction(async (transaction) => {
      const organizationSnapshot = await transaction.get(organizationReference);

      if (!organizationSnapshot.exists) {
        throw new HttpsError("not-found", "Organization does not exist.");
      }

      const roles = organizationRolesFromData(
        roleRequest.organizationId,
        organizationSnapshot.data()
      );
      if (!canManageOrganizationRoles(actorPermissions, roles)) {
        throw new HttpsError("permission-denied", "Organization role permissions are required.");
      }

      previousRole = roleForUser(roles, roleRequest.targetUserId);
      if (previousRole === "communityOwner") {
        throw new HttpsError(
          "permission-denied",
          "Organization owner role cannot be changed here."
        );
      }

      const adminIdsWithoutTarget = withoutUser(roles.adminIds, roleRequest.targetUserId);
      const moderatorIdsWithoutTarget = withoutUser(roles.moderatorIds, roleRequest.targetUserId);
      const nextAdminIds = mutation.isRemoval || mutation.targetRole !== "communityAdmin"
        ? adminIdsWithoutTarget
        : sortedUniqueUserIds([...adminIdsWithoutTarget, roleRequest.targetUserId]);
      const nextModeratorIds = mutation.isRemoval || mutation.targetRole !== "communityModerator"
        ? moderatorIdsWithoutTarget
        : sortedUniqueUserIds([...moderatorIdsWithoutTarget, roleRequest.targetUserId]);

      transaction.update(organizationReference, {
        adminIds: nextAdminIds,
        moderatorIds: nextModeratorIds,
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(auditLogRef(), buildAuditLog({
        actionType: mutation.isRemoval ? "organizationRoleRemoved" : "organizationRoleAssigned",
        targetUserId: roleRequest.targetUserId,
        performedBy: auth.uid,
        reason: roleRequest.reason ?? mutation.defaultReason,
        previousValue: {
          organizationId: roleRequest.organizationId,
          role: previousRole,
        },
        newValue: {
          organizationId: roleRequest.organizationId,
          role: newRole,
        },
      }));
    });

    const notificationType = mutation.isRemoval
      ? "organizationRoleRemoved"
      : "organizationRoleAssigned";
    const changedRole = mutation.isRemoval ? previousRole : newRole;

    await writeUserNotification({
      targetUserId: roleRequest.targetUserId,
      type: notificationType,
      title: mutation.isRemoval
        ? "Organization role removed"
        : "Organization role assigned",
      message: mutation.isRemoval
        ? `Your ${organizationRoleName(changedRole)} role was removed.`
        : `You were assigned as ${organizationRoleName(changedRole)}.`,
      severity: "info",
      actionType: "openOrganization",
      actionTargetId: roleRequest.organizationId,
      requiresPopup: false,
      actorUserId: auth.uid,
      sourceType: "organization",
      sourceId: roleRequest.organizationId,
      metadata: {
        organizationId: roleRequest.organizationId,
        previousRole,
        newRole,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "organizationRole",
        roleRequest.organizationId,
        roleRequest.targetUserId,
        newRole,
      ].join(":"),
    });

    return {
      organizationId: roleRequest.organizationId,
      targetUserId: roleRequest.targetUserId,
      previousRole,
      newRole,
      updatedAt: committedAt,
    };
  });
}

export const assignOrganizationAdmin = createRoleCallable({
  targetRole: "communityAdmin",
  isRemoval: false,
  defaultReason: "Organization role update",
});

export const removeOrganizationAdmin = createRoleCallable({
  targetRole: "communityAdmin",
  isRemoval: true,
  defaultReason: "Organization role update",
});

export const assignOrganizationModerator = createRoleCallable({
  targetRole: "communityModerator",
  isRemoval: false,
  defaultReason: "Organization role update",
});

export const removeOrganizationModerator = createRoleCallable({
  targetRole: "communityModerator",
  isRemoval: true,
  defaultReason: "Organization role update",
});

export const transferOrganizationOwnership = onCall(
  callableOptions,
  async (request): Promise<OrganizationOwnershipTransferResponse> => {
    const auth = requireAuth(request);
    const roleRequest = parseRoleChangeRequest(request.data);
    const actorPermissions = await getUserPermissions(auth.uid);
    assertOwner(actorPermissions);

    const organizationReference = db.collection("organizations").doc(roleRequest.organizationId);
    const committedAt = new Date().toISOString();
    let previousOwnerId: string | null = null;

    await db.runTransaction(async (transaction) => {
      const organizationSnapshot = await transaction.get(organizationReference);

      if (!organizationSnapshot.exists) {
        throw new HttpsError("not-found", "Organization does not exist.");
      }

      const roles = organizationRolesFromData(
        roleRequest.organizationId,
        organizationSnapshot.data()
      );
      previousOwnerId = roles.ownerId ?? null;

      if (roles.ownerId === roleRequest.targetUserId) {
        throw new HttpsError("failed-precondition", "Target user already owns this organization.");
      }

      transaction.update(organizationReference, {
        ownerId: roleRequest.targetUserId,
        adminIds: withoutUser(
          withoutUser(roles.adminIds, roleRequest.targetUserId),
          roles.ownerId ?? ""
        ),
        moderatorIds: withoutUser(
          withoutUser(roles.moderatorIds, roleRequest.targetUserId),
          roles.ownerId ?? ""
        ),
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.set(auditLogRef(), buildAuditLog({
        actionType: "organizationOwnerChanged",
        targetUserId: roleRequest.targetUserId,
        performedBy: auth.uid,
        reason: roleRequest.reason ?? "Organization owner changed",
        previousValue: {
          organizationId: roleRequest.organizationId,
          ownerId: previousOwnerId ?? "none",
        },
        newValue: {
          organizationId: roleRequest.organizationId,
          ownerId: roleRequest.targetUserId,
        },
      }));
    });

    await writeUserNotification({
      targetUserId: roleRequest.targetUserId,
      type: "organizationRoleAssigned",
      title: "Organization ownership transferred",
      message: "You were assigned as organization owner.",
      severity: "info",
      actionType: "openOrganization",
      actionTargetId: roleRequest.organizationId,
      requiresPopup: false,
      actorUserId: auth.uid,
      sourceType: "organization",
      sourceId: roleRequest.organizationId,
      metadata: {
        organizationId: roleRequest.organizationId,
        previousOwnerId,
        newOwnerId: roleRequest.targetUserId,
        updatedAt: committedAt,
      },
      dedupeKey: [
        "organizationOwnership",
        roleRequest.organizationId,
        roleRequest.targetUserId,
      ].join(":"),
    });

    if (previousOwnerId) {
      await writeUserNotification({
        targetUserId: previousOwnerId,
        type: "organizationRoleRemoved",
        title: "Organization ownership transferred",
        message: "Your organization owner role was transferred.",
        severity: "info",
        actionType: "openOrganization",
        actionTargetId: roleRequest.organizationId,
        requiresPopup: false,
        actorUserId: auth.uid,
        sourceType: "organization",
        sourceId: roleRequest.organizationId,
        metadata: {
          organizationId: roleRequest.organizationId,
          previousOwnerId,
          newOwnerId: roleRequest.targetUserId,
          updatedAt: committedAt,
        },
        dedupeKey: [
          "organizationOwnershipRemoved",
          roleRequest.organizationId,
          previousOwnerId,
        ].join(":"),
      });
    }

    return {
      organizationId: roleRequest.organizationId,
      previousOwnerId,
      newOwnerId: roleRequest.targetUserId,
      updatedAt: committedAt,
    };
  }
);
