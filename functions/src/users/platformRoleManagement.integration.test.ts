import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";

import {requireVerifiedActiveUser} from "../auth/context";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {adminAuth, db} from "../firebase/admin";
import {assignAppAdmin, removeAppAdmin} from "./platformRoleManagement";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);

function request(uid: string, data: unknown, totp: boolean) {
  return {
    data,
    auth: {
      uid,
      token: {
        email_verified: true,
        firebase: {sign_in_second_factor: totp ? "totp" : undefined},
      },
    },
  } as any;
}

test("app admin promotion requires TOTP from the same commit as the role change", {skip: !enabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const prefix = `platform-role-${randomUUID()}`;
  const ownerId = `${prefix}-owner`;
  const targetId = `${prefix}-target`;
  const owner = db.doc(`users/${ownerId}`);
  const target = db.doc(`users/${targetId}`);

  try {
    await adminAuth.createUser({uid: targetId, email: `${targetId}@example.org`, emailVerified: true});
    await owner.set({globalRole: "owner", accountStatus: "active", requiresMultiFactorAuth: true});
    await target.set({globalRole: "user", accountStatus: "active"});
    await seedCurrentLegalForIntegration(ownerId, targetId);

    await assert.rejects(assignAppAdmin.run(request(ownerId, {targetUserId: targetId}, false)), {
      code: "failed-precondition",
    });
    assert.equal((await target.get()).get("globalRole"), "user");

    const assigned = await assignAppAdmin.run(request(ownerId, {targetUserId: targetId}, true));
    assert.equal(assigned.newGlobalRole, "admin");
    const promoted = await target.get();
    assert.equal(promoted.get("globalRole"), "admin");
    assert.equal(promoted.get("requiresMultiFactorAuth"), true);
    assert.equal(promoted.get("multiFactorAuthRequiredMethod"), "totp");
    assert.ok(promoted.get("multiFactorAuthRequiredAt"));

    await assert.rejects(requireVerifiedActiveUser(request(targetId, {}, false)), {
      code: "failed-precondition",
    });
    assert.equal((await requireVerifiedActiveUser(request(targetId, {}, true))).uid, targetId);

    const removed = await removeAppAdmin.run(request(ownerId, {targetUserId: targetId}, true));
    assert.equal(removed.newGlobalRole, "user");
    assert.equal((await target.get()).get("requiresMultiFactorAuth"), true);
    assert.equal((await requireVerifiedActiveUser(request(targetId, {}, false))).uid, targetId);
  } finally {
    await Promise.all([db.recursiveDelete(owner), db.recursiveDelete(target)]);
    const audit = await db.collection("auditLogs").where("targetUserId", "==", targetId).get();
    await Promise.all(audit.docs.map((document) => document.ref.delete()));
    await adminAuth.deleteUser(targetId).catch((error: unknown) => {
      if ((error as {code?: string}).code !== "auth/user-not-found") throw error;
    });
  }
});
