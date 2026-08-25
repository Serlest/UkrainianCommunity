import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  assertMutableAccountStatusTarget,
  type AccountStatusSnapshot,
} from "./accountStatusManagement";
import {type UserPermissionSnapshot} from "../permissions/userPermissions";

function actor(globalRole: "owner" | "admin" | "user"): UserPermissionSnapshot {
  return {
    uid: `actor-${globalRole}`,
    globalRole,
    accountStatus: "active",
    blockState: "active",
  };
}

function target(globalRole: "owner" | "admin" | "user"): AccountStatusSnapshot {
  return {
    uid: `target-${globalRole}`,
    globalRole,
    accountStatus: "active",
    blockState: "active",
    warningCount: 0,
    banExpiresAt: null,
  };
}

function assertPermissionDenied(error: unknown): boolean {
  assert.ok(error instanceof HttpsError);
  assert.equal(error.code, "permission-denied");
  return true;
}

test("app owner may manage an app admin account status", () => {
  assert.doesNotThrow(() => assertMutableAccountStatusTarget(actor("owner"), target("admin")));
});

test("app admin may manage a regular user but not another app admin", () => {
  assert.doesNotThrow(() => assertMutableAccountStatusTarget(actor("admin"), target("user")));
  assert.throws(
    () => assertMutableAccountStatusTarget(actor("admin"), target("admin")),
    assertPermissionDenied
  );
});

test("app owner account status is immutable through user management", () => {
  assert.throws(
    () => assertMutableAccountStatusTarget(actor("owner"), target("owner")),
    assertPermissionDenied
  );
});
