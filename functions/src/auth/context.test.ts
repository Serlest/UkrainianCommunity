import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";

import {
  type AuthContext,
  assertActiveUser,
  assertPrivilegedMFA,
  isTOTPAuthenticated,
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
