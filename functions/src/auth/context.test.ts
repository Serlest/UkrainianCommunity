import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";

import {
  type AuthContext,
  assertActiveUser,
  assertPrivilegedMFA,
  canManagePasskeyCredentials,
  hasCurrentLegalAcknowledgements,
  isTOTPAuthenticated,
  isPrivilegedSessionAuthenticated,
  requireAuth,
  requireVerifiedAuth,
  requiresPrivilegedMFA,
} from "./context";

function authToken(secondFactor?: string): AuthContext["token"] {
  return {
    aud: "demo-project",
    auth_time: 1_700_000_000,
    exp: 1_700_003_600,
    firebase: {
      identities: {email: ["owner@example.com"]},
      sign_in_provider: "password",
      ...(secondFactor ? {sign_in_second_factor: secondFactor} : {}),
    },
    iat: 1_700_000_000,
    iss: "https://securetoken.google.com/demo-project",
    sub: "owner",
    uid: "owner",
    email_verified: true,
  };
}

function callableRequest(auth: CallableRequest["auth"]): CallableRequest {
  return {auth} as CallableRequest;
}

function assertHttpsErrorCode(error: unknown, expectedCode: string): boolean {
  assert.ok(error instanceof HttpsError);
  assert.equal(error.code, expectedCode);
  return true;
}

test("requireAuth rejects missing authentication", () => {
  assert.throws(
    () => requireAuth(callableRequest(undefined)),
    (error) => assertHttpsErrorCode(error, "unauthenticated")
  );
});

test("passkey claim requires custom provider and current account epoch", () => {
  const permissions = {uid: "owner", globalRole: "owner" as const,
    requiresMultiFactorAuth: true, passkeyEpoch: "current"};
  const token = {...authToken(), firebase: {identities: {}, sign_in_provider: "custom"},
    uac_passkey_verified: true, uac_passkey_epoch: "current"};
  assert.equal(isPrivilegedSessionAuthenticated(token, permissions), true);
  assert.equal(isPrivilegedSessionAuthenticated(
    {...token, uac_passkey_epoch: "revoked"}, permissions), false);
  assert.equal(isPrivilegedSessionAuthenticated(
    {...token, firebase: {identities: {}, sign_in_provider: "password"}}, permissions), false);
  assert.equal(isPrivilegedSessionAuthenticated(
    {...token, uac_passkey_verified: false}, permissions), false);
});

test("ordinary users may manage passkeys only after recent sign-in; privileged users need TOTP", () => {
  const now = 1_700_000_500;
  const user = {uid: "user", globalRole: "user" as const};
  const owner = {uid: "owner", globalRole: "owner" as const};
  assert.equal(canManagePasskeyCredentials(authToken(), user, now), true);
  assert.equal(canManagePasskeyCredentials(authToken(), user, now + 100), false);
  assert.equal(canManagePasskeyCredentials(authToken(), owner, now), false);
  assert.equal(canManagePasskeyCredentials(authToken("totp"), owner, now), true);
  assert.equal(canManagePasskeyCredentials(authToken("totp"), owner, now + 100), false);
});

test("requireVerifiedAuth rejects unverified authentication", () => {
  assert.throws(
    () => requireVerifiedAuth(callableRequest({
      uid: "user-1",
      token: {email_verified: false},
    } as CallableRequest["auth"])),
    (error) => assertHttpsErrorCode(error, "permission-denied")
  );
});

test("requireVerifiedAuth returns the verified actor", () => {
  const auth = requireVerifiedAuth(callableRequest({
    uid: "user-1",
    token: {email_verified: true},
  } as CallableRequest["auth"]));

  assert.equal(auth.uid, "user-1");
  assert.equal(auth.token.email_verified, true);
});

test("assertActiveUser rejects suspended and deactivated accounts", () => {
  for (const accountStatus of ["suspendedUntil", "deactivated"] as const) {
    assert.throws(
      () => assertActiveUser({uid: "user-1", accountStatus}),
      (error) => assertHttpsErrorCode(error, "permission-denied")
    );
  }
});

test("assertActiveUser accepts active and warned accounts", () => {
  assert.doesNotThrow(() => assertActiveUser({uid: "user-1", accountStatus: "active"}));
  assert.doesNotThrow(() => assertActiveUser({uid: "user-1", blockState: "warned"}));
});

test("both current legal versions are required for account operations", () => {
  const versions = {terms: "2026.11", privacy: "2026.15"};
  const current = {uid: "user-1", acceptedTermsVersion: versions.terms, acceptedPrivacyVersion: versions.privacy};
  assert.equal(hasCurrentLegalAcknowledgements(current, versions), true);
  assert.equal(hasCurrentLegalAcknowledgements({...current, acceptedTermsVersion: "2026.10"}, versions), false);
  assert.equal(hasCurrentLegalAcknowledgements({...current, acceptedPrivacyVersion: "2026.14"}, versions), false);
  assert.equal(hasCurrentLegalAcknowledgements(current, {terms: undefined, privacy: versions.privacy}), false);
});

test("privileged MFA stays opt-in per account during rollout", () => {
  assert.equal(requiresPrivilegedMFA({
    uid: "owner",
    globalRole: "owner",
  }), false);
  assert.equal(requiresPrivilegedMFA({
    uid: "owner",
    globalRole: "owner",
    requiresMultiFactorAuth: true,
  }), true);
  assert.equal(requiresPrivilegedMFA({
    uid: "user",
    globalRole: "user",
    requiresMultiFactorAuth: true,
  }), false);
});

test("privileged MFA requires a TOTP-authenticated token", () => {
  const permissions = {
    uid: "owner",
    globalRole: "owner" as const,
    requiresMultiFactorAuth: true,
  };

  assert.throws(
    () => assertPrivilegedMFA(authToken(), permissions),
    (error) => assertHttpsErrorCode(error, "failed-precondition")
  );
  assert.doesNotThrow(() => assertPrivilegedMFA(authToken("totp"), permissions));
  assert.equal(isTOTPAuthenticated(authToken("phone")), false);
});
