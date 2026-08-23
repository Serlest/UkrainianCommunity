import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {assertUsableTargetUser, type TargetAuthSnapshot} from "./targetUserValidation";

const usableAuth: TargetAuthSnapshot = {
  uid: "user-2",
  emailVerified: true,
  disabled: false,
};

function assertErrorCode(error: unknown, expectedCode: string): boolean {
  assert.ok(error instanceof HttpsError);
  assert.equal(error.code, expectedCode);
  return true;
}

test("accepts a verified enabled active target", () => {
  assert.doesNotThrow(() => assertUsableTargetUser(usableAuth, {
    uid: "user-2",
    accountStatus: "active",
    blockState: "active",
  }));
});

test("rejects disabled and unverified target identities", () => {
  for (const auth of [
    {...usableAuth, disabled: true},
    {...usableAuth, emailVerified: false},
  ]) {
    assert.throws(
      () => assertUsableTargetUser(auth, {uid: "user-2"}),
      (error) => assertErrorCode(error, "failed-precondition")
    );
  }
});

test("rejects suspended, deactivated, and inconsistent targets", () => {
  for (const accountStatus of ["suspendedUntil", "deactivated"] as const) {
    assert.throws(
      () => assertUsableTargetUser(usableAuth, {uid: "user-2", accountStatus}),
      (error) => assertErrorCode(error, "failed-precondition")
    );
  }

  assert.throws(
    () => assertUsableTargetUser(usableAuth, {uid: "different-user"}),
    (error) => assertErrorCode(error, "internal")
  );
});
