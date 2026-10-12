import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  getUserPermissions,
  isActiveUser,
  type UserPermissionSnapshot,
} from "../permissions/userPermissions";
import {db} from "../firebase/admin";

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

export function isPrivilegedSessionAuthenticated(
  token: AuthContext["token"], permissions: UserPermissionSnapshot
): boolean {
  const firebaseClaims = token.firebase as
    | {sign_in_provider?: unknown}
    | undefined;
  return isTOTPAuthenticated(token)
    || (firebaseClaims?.sign_in_provider === "custom"
      && token.uac_passkey_verified === true
      && typeof permissions.passkeyEpoch === "string"
      && token.uac_passkey_epoch === permissions.passkeyEpoch);
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
  if (requiresPrivilegedMFA(permissions)
      && !isPrivilegedSessionAuthenticated(token, permissions)) {
    throw new HttpsError(
      "failed-precondition",
      "A passkey or authenticator-verified session is required for this privileged account."
    );
  }
}

export async function requireVerifiedActiveUser(
  request: CallableRequest
): Promise<VerifiedActiveUserContext> {
  const auth = await requireVerifiedActiveUserWithoutLegal(request);
  await assertCurrentLegalAcknowledgements(auth.permissions);
  return auth;
}

export async function requireVerifiedActiveUserWithoutLegal(
  request: CallableRequest
): Promise<VerifiedActiveUserContext> {
  const auth = requireVerifiedAuth(request);
  const permissions = await getUserPermissions(auth.uid);
  assertActiveUser(permissions);
  assertPrivilegedMFA(auth.token, permissions);

  return {...auth, permissions};
}

export async function assertCurrentLegalAcknowledgements(
  permissions: UserPermissionSnapshot
): Promise<void> {
  const [terms, privacy] = await db.getAll(
    db.doc("legalDocuments/terms"),
    db.doc("legalDocuments/privacy")
  );
  if (!terms.exists || !privacy.exists || !hasCurrentLegalAcknowledgements(permissions, {
    terms: terms.get("activeVersion"),
    privacy: privacy.get("activeVersion"),
  })) {
    throw new HttpsError("failed-precondition", "Current legal documents must be acknowledged.");
  }
}

export function hasCurrentLegalAcknowledgements(
  permissions: UserPermissionSnapshot,
  versions: {terms: unknown; privacy: unknown}
): boolean {
  return typeof versions.terms === "string" && versions.terms.length > 0 &&
    typeof versions.privacy === "string" && versions.privacy.length > 0 &&
    permissions.acceptedTermsVersion === versions.terms &&
    permissions.acceptedPrivacyVersion === versions.privacy;
}
