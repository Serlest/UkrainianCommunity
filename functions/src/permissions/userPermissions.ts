import { HttpsError } from "firebase-functions/v2/https";

import { db } from "../firebase/admin";

export type AccountStatus =
  | "active"
  | "warned"
  | "suspendedUntil"
  | "bannedPermanent"
  | "deactivated";
export type BlockState =
  | "active"
  | "warned"
  | "suspendedUntil"
  | "bannedPermanent"
  | "deactivated";
export type GlobalRole = "owner" | "admin" | "moderator" | "user" | "topAdmin" | "appModerator";

export interface UserPermissionSnapshot {
  uid: string;
  accountStatus?: AccountStatus;
  blockState?: BlockState;
  globalRole?: GlobalRole;
  canManageGuide?: boolean;
}

export async function getUserPermissions(uid: string): Promise<UserPermissionSnapshot> {
  const snapshot = await db.collection("users").doc(uid).get();

  if (!snapshot.exists) {
    throw new HttpsError("permission-denied", "User profile does not exist.");
  }

  const data = snapshot.data() ?? {};

  return {
    uid,
    accountStatus: data.accountStatus,
    blockState: data.blockState,
    globalRole: data.globalRole,
    canManageGuide: data.canManageGuide,
  };
}

export function isActiveUser(user: UserPermissionSnapshot): boolean {
  const accountStatus = user.accountStatus ?? "active";
  const blockState = user.blockState ?? "active";

  return ["active", "warned"].includes(accountStatus)
    && ["active", "warned"].includes(blockState);
}

export function isOwner(user: UserPermissionSnapshot): boolean {
  return isActiveUser(user) && user.globalRole === "owner";
}

export function isAppOwner(user: UserPermissionSnapshot): boolean {
  return isOwner(user);
}

export function isAppAdmin(user: UserPermissionSnapshot): boolean {
  return isActiveUser(user) && user.globalRole === "admin";
}

export function isAppModerator(user: UserPermissionSnapshot): boolean {
  return isActiveUser(user) && user.globalRole === "moderator";
}

export function canManageOrganizationRequests(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user) || isAppAdmin(user);
}

export function canManageUsers(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canAssignAppAdmin(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canAssignAppModerator(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canAssignGuideEditor(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canAccessModerationTools(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user) || isAppAdmin(user) || isAppModerator(user);
}

export function canManageFeedback(user: UserPermissionSnapshot): boolean {
  return canAccessModerationTools(user);
}

export function canManageReports(user: UserPermissionSnapshot): boolean {
  return canAccessModerationTools(user);
}

export function canManageFeaturedBanners(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canUseOrganizationOverride(user: UserPermissionSnapshot): boolean {
  return isAppOwner(user);
}

export function canManageGuide(user: UserPermissionSnapshot): boolean {
  return isActiveUser(user) && (user.globalRole === "owner" || user.canManageGuide === true);
}

export function assertOwner(user: UserPermissionSnapshot): void {
  if (!isOwner(user)) {
    throw new HttpsError("permission-denied", "Owner permissions are required.");
  }
}

export function assertCanManageGuide(user: UserPermissionSnapshot): void {
  if (!canManageGuide(user)) {
    throw new HttpsError("permission-denied", "Guide management permissions are required.");
  }
}
