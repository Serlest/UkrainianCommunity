import { HttpsError } from "firebase-functions/v2/https";

import { db } from "../firebase/admin";
import { isOwner, type UserPermissionSnapshot } from "./userPermissions";

export type OrganizationRole = "communityOwner" | "communityAdmin" | "communityModerator";

export interface OrganizationRoleSnapshot {
  organizationId: string;
  ownerId?: string;
  adminIds: string[];
  moderatorIds: string[];
}

export async function getOrganizationRoles(
  organizationId: string
): Promise<OrganizationRoleSnapshot> {
  const snapshot = await db.collection("organizations").doc(organizationId).get();

  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Organization does not exist.");
  }

  const data = snapshot.data() ?? {};

  return {
    organizationId,
    ownerId: data.ownerId,
    adminIds: Array.isArray(data.adminIds) ? data.adminIds : [],
    moderatorIds: Array.isArray(data.moderatorIds) ? data.moderatorIds : [],
  };
}

export function hasOrganizationRole(
  roles: OrganizationRoleSnapshot,
  uid: string,
  role: OrganizationRole
): boolean {
  switch (role) {
    case "communityOwner":
      return roles.ownerId === uid;
    case "communityAdmin":
      return roles.adminIds.includes(uid);
    case "communityModerator":
      return roles.moderatorIds.includes(uid);
  }
}

export function canManageOrganizationRoles(
  user: UserPermissionSnapshot,
  roles: OrganizationRoleSnapshot
): boolean {
  return isOwner(user) || hasOrganizationRole(roles, user.uid, "communityOwner");
}
