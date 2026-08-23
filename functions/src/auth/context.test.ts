import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";

import {assertActiveUser, requireAuth, requireVerifiedAuth} from "./context";

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
