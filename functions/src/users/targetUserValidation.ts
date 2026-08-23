import {HttpsError} from "firebase-functions/v2/https";

import {adminAuth} from "../firebase/admin";
import {
  isActiveUser,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";

export interface TargetAuthSnapshot {
  uid: string;
  emailVerified: boolean;
  disabled: boolean;
}

export function assertUsableTargetUser(
  auth: TargetAuthSnapshot,
  permissions: UserPermissionSnapshot
): void {
  if (auth.uid !== permissions.uid) {
    throw new HttpsError("internal", "Target user identity is inconsistent.");
  }

  if (auth.disabled) {
    throw new HttpsError("failed-precondition", "Target user account is disabled.");
  }

  if (!auth.emailVerified) {
    throw new HttpsError(
      "failed-precondition",
      "Target user must verify their email address first."
    );
  }

  if (!isActiveUser(permissions)) {
    throw new HttpsError("failed-precondition", "Target user must have an active account.");
  }
}

export async function getTargetAuthSnapshot(uid: string): Promise<TargetAuthSnapshot> {
  try {
    const user = await adminAuth.getUser(uid);
    return {
      uid: user.uid,
      emailVerified: user.emailVerified,
      disabled: user.disabled,
    };
  } catch (error) {
    if (firebaseErrorCode(error) === "auth/user-not-found") {
      throw new HttpsError("not-found", "Target user does not exist.");
    }
    throw error;
  }
}

function firebaseErrorCode(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return undefined;
  }

  return typeof error.code === "string" ? error.code : undefined;
}
