import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  getUserPermissions,
  isActiveUser,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";

export interface AuthContext {
  uid: string;
  token: NonNullable<CallableRequest["auth"]>["token"];
}

export interface VerifiedActiveUserContext extends AuthContext {
  permissions: UserPermissionSnapshot;
}

export function requireAuth(request: CallableRequest): AuthContext {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Authentication is required.");
  }

  return {
    uid: request.auth.uid,
    token: request.auth.token,
  };
}

export function requireVerifiedAuth(request: CallableRequest): AuthContext {
  const auth = requireAuth(request);

  if (auth.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "A verified email address is required.");
  }

  return auth;
}

export function assertActiveUser(permissions: UserPermissionSnapshot): void {
  if (!isActiveUser(permissions)) {
    throw new HttpsError("permission-denied", "An active account is required.");
  }
}

export function isTOTPAuthenticated(token: AuthContext["token"]): boolean {
  const firebaseClaims = token.firebase as
    | {sign_in_second_factor?: unknown}
    | undefined;
  return firebaseClaims?.sign_in_second_factor === "totp";
}

export function requiresPrivilegedMFA(
  permissions: UserPermissionSnapshot
): boolean {
  return permissions.requiresMultiFactorAuth === true
    && (permissions.globalRole === "owner" || permissions.globalRole === "admin");
}

export function assertPrivilegedMFA(
  token: AuthContext["token"],
  permissions: UserPermissionSnapshot
): void {
  if (requiresPrivilegedMFA(permissions) && !isTOTPAuthenticated(token)) {
    throw new HttpsError(
      "failed-precondition",
      "A TOTP-authenticated session is required for this privileged account."
    );
  }
}

export async function requireVerifiedActiveUser(
  request: CallableRequest
): Promise<VerifiedActiveUserContext> {
  const auth = requireVerifiedAuth(request);
  const permissions = await getUserPermissions(auth.uid);
  assertActiveUser(permissions);
  assertPrivilegedMFA(auth.token, permissions);

  return {...auth, permissions};
}
