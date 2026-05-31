import { HttpsError } from "firebase-functions/v2/https";

import { db } from "../firebase/admin";

export type AccountStatus = "active" | "warned" | "deactivated" | "suspended" | "banned";
export type BlockState = "active" | "warned" | "deactivated" | "suspended" | "banned";
export type GlobalRole = "user" | "owner";

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

export function assertOwner(user: UserPermissionSnapshot): void {
  if (!isOwner(user)) {
    throw new HttpsError("permission-denied", "Owner permissions are required.");
  }
}
