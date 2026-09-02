import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  assertPrivilegedMFARecoverySafe,
  buildPrivilegedMFARecoveryWrite,
  inspectPrivilegedMFARecovery,
  parsePrivilegedMFARecoveryOptions,
  redactEmail,
  verifyPrivilegedMFARecovery,
} from "./privilegedMFARecoveryCore.mjs";

const authUser = (overrides = {}) => ({
  localId: "owner-uid",
  email: "owner@example.com",
  emailVerified: true,
  disabled: false,
  mfaInfo: [{totpInfo: {}}],
  ...overrides,
});

const firestoreUser = (overrides = {}) => ({
  email: "owner@example.com",
  globalRole: "owner",
  accountStatus: "active",
  blockState: "active",
  requiresMultiFactorAuth: true,
  ...overrides,
});

test("dry-run identifies a recoverable privileged TOTP account", () => {
  const options = parsePrivilegedMFARecoveryOptions([
    "--project=example",
    "--actor-email=recovery@example.com",
    "--target-email=OWNER@example.com",
    "--reason=Lost authenticator during recovery drill",
  ]);
  const snapshot = inspectPrivilegedMFARecovery(authUser(), firestoreUser());
  assert.doesNotThrow(() => assertPrivilegedMFARecoverySafe(snapshot, options));
  assert.equal(snapshot.factorCount, 1);
  assert.deepEqual(snapshot.factorTypes, ["totp"]);
  assert.equal(options.actorEmail, "recovery@example.com");
});

test("apply requires exact project, identity, and fresh state confirmations", () => {
  assert.throws(() => parsePrivilegedMFARecoveryOptions([
    "--project=example",
    "--actor-email=recovery@example.com",
    "--target-email=owner@example.com",
    "--reason=Lost authenticator during recovery drill",
    "--apply",
  ]), /confirm-project/);

  const options = parsePrivilegedMFARecoveryOptions([
    "--project=example",
    "--actor-email=recovery@example.com",
    "--target-email=owner@example.com",
    "--reason=Lost authenticator during recovery drill",
    "--apply",
    "--confirm-project=example",
    "--confirm-email=owner@example.com",
    "--confirm-uid=owner-uid",
    "--expect-factors=1",
    "--expect-required=true",
  ]);
  const changed = inspectPrivilegedMFARecovery(
    authUser({mfaInfo: []}),
    firestoreUser()
  );
  assert.throws(
    () => assertPrivilegedMFARecoverySafe(changed, options),
    /preflight changed/
  );
});

test("rejects non-privileged, blocked, mismatched, and no-op targets", () => {
  const options = parsePrivilegedMFARecoveryOptions([
    "--project=example",
    "--actor-email=recovery@example.com",
    "--target-email=owner@example.com",
    "--reason=Lost authenticator during recovery drill",
  ]);
  assert.throws(() => assertPrivilegedMFARecoverySafe(
    inspectPrivilegedMFARecovery(authUser(), firestoreUser({globalRole: "user"})),
    options
  ), /owner or admin/);
  assert.throws(() => assertPrivilegedMFARecoverySafe(
    inspectPrivilegedMFARecovery(authUser(), firestoreUser({accountStatus: "blocked"})),
    options
  ), /active, unblocked/);
  assert.throws(() => inspectPrivilegedMFARecovery(
    authUser(),
    firestoreUser({email: "other@example.com"})
  ), /do not match/);
  assert.throws(() => assertPrivilegedMFARecoverySafe(
    inspectPrivilegedMFARecovery(
      authUser({mfaInfo: []}),
      firestoreUser({requiresMultiFactorAuth: false})
    ),
    options
  ), /no privileged MFA/);
});

test("requires an explicit recovery actor account", () => {
  assert.throws(() => parsePrivilegedMFARecoveryOptions([
    "--project=example",
    "--target-email=owner@example.com",
    "--reason=Lost authenticator during recovery drill",
  ]), /actor-email/);
});

test("builds a guarded recovery write and verifies complete read-back", () => {
  const write = buildPrivilegedMFARecoveryWrite({
    documentName: "projects/example/databases/(default)/documents/users/owner-uid",
    updateTime: "2026-09-02T10:00:00.000000Z",
    actorEmail: "recovery@example.com",
    reason: "Lost authenticator during recovery drill",
  });
  assert.equal(write.currentDocument.updateTime, "2026-09-02T10:00:00.000000Z");
  assert.equal(write.update.fields.requiresMultiFactorAuth.booleanValue, false);
  assert.ok(write.updateMask.fieldPaths.includes("multiFactorAuthRequiredMethod"));
  assert.equal(write.updateTransforms.length, 2);

  assert.equal(verifyPrivilegedMFARecovery({
    factorCount: 0,
    requiresMultiFactorAuth: false,
  }, {
    multiFactorAuthRecoveryAt: "2026-09-02T10:01:00Z",
    multiFactorAuthRecoveryActor: "recovery@example.com",
    multiFactorAuthRecoveryReason: "Lost authenticator during recovery drill",
  }), true);
  assert.equal(redactEmail("recovery@example.com"), "r***@example.com");
});
