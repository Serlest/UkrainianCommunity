import {strict as assert} from "node:assert";
import {test} from "node:test";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {getManagedUserPresence, updateUserPresence} from "./userPresence";

// Hard safety gate: these tests must never write to a real Firebase project.
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const sessionId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
function request(uid: string, data: unknown, verified = true) {
  return {auth: {uid, token: {email_verified: verified}}, data} as never;
}

test("presence callable access, multiple devices, account deletion and blocked users", {skip: !enabled}, async () => {
  const prefix = `presence-test-${Date.now()}`;
  const ids = ["owner", "admin", "user", "org-owner", "org-admin", "org-moderator", "blocked"];
  const uid = (id: string) => `${prefix}-${id}`;
  try {
    await db.collection("organizations").doc(prefix).set({
      ownerId: uid("org-owner"), adminIds: [uid("org-admin")], moderatorIds: [uid("org-moderator")],
    });
    for (const id of ids) {
      await db.collection("users").doc(uid(id)).set({
        globalRole: ["owner", "admin"].includes(id) ? id : "user",
        accountStatus: id === "blocked" ? "deactivated" : "active",
        blockState: "active",
      });
    }
    await seedCurrentLegalForIntegration(...ids.map(uid));
    await assert.rejects(getManagedUserPresence.run({data: {targetUserId: uid("user")}} as never), {code: "unauthenticated"});
    await assert.rejects(updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 1, active: true}, false)), {code: "permission-denied"});
    for (const actor of ["user", "org-owner", "org-admin", "org-moderator", "blocked"]) {
      await assert.rejects(getManagedUserPresence.run(request(uid(actor), {targetUserId: uid("user")})), {code: "permission-denied"});
    }
    for (const actor of ["owner", "admin"]) {
      const result = await getManagedUserPresence.run(request(uid(actor), {targetUserId: uid("user")}));
      assert.equal(result.lastSeenAt, null);
      assert.equal(result.onlineUntil, null);
    }
    await assert.rejects(updateUserPresence.run(request(uid("user"), {userId: uid("admin"), sessionId, sequence: 1, active: true})), {code: "permission-denied"});
    await updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 1, active: true}));
    let status = await getManagedUserPresence.run(request(uid("admin"), {targetUserId: uid("user")}));
    assert.ok(status.onlineUntil! > status.serverTime);
    await updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 3, active: false}));
    await updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 2, active: true}));
    status = await getManagedUserPresence.run(request(uid("owner"), {targetUserId: uid("user")}));
    assert.equal(status.onlineUntil, null);
    assert.ok(status.lastSeenAt);
    const secondSession = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
    await updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId: secondSession, sequence: 1, active: true}));
    status = await getManagedUserPresence.run(request(uid("owner"), {targetUserId: uid("user")}));
    assert.ok(status.onlineUntil! > status.serverTime);
    await db.collection("users").doc(uid("user")).update({accountStatus: "deactivated", deletionState: "inProgress"});
    await assert.rejects(updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 4, active: true})), {code: "permission-denied"});
    await db.recursiveDelete(db.collection("users").doc(uid("user")));
    await assert.rejects(updateUserPresence.run(request(uid("user"), {userId: uid("user"), sessionId, sequence: 5, active: true})), {code: "permission-denied"});
    assert.equal((await db.collection("users").doc(uid("user")).collection("privatePresence").doc("current").get()).exists, false);
  } finally {
    await db.collection("organizations").doc(prefix).delete();
    for (const id of ids) await db.recursiveDelete(db.collection("users").doc(uid(id)));
  }
});

test("presence stops when legal acceptance is stale or privileged TOTP is missing", {skip: !enabled}, async () => {
  const uid = `presence-legal-${Date.now()}`;
  const profile = db.doc(`users/${uid}`);
  const update = {userId: uid, sessionId, sequence: 1, active: true};
  try {
    await profile.set({globalRole: "user", accountStatus: "active"});
    await seedCurrentLegalForIntegration(uid);
    const acceptedTermsVersion = (await profile.get()).get("acceptedTermsVersion");
    const acceptedPrivacyVersion = (await profile.get()).get("acceptedPrivacyVersion");

    await profile.update({acceptedTermsVersion: "outdated"});
    await assert.rejects(updateUserPresence.run(request(uid, update)), {code: "failed-precondition"});
    assert.equal((await profile.collection("privatePresence").doc("current").get()).exists, false);

    await profile.update({acceptedTermsVersion, acceptedPrivacyVersion: "outdated"});
    await assert.rejects(updateUserPresence.run(request(uid, update)), {code: "failed-precondition"});

    await profile.update({acceptedPrivacyVersion, globalRole: "admin", requiresMultiFactorAuth: true});
    await assert.rejects(updateUserPresence.run(request(uid, update)), {code: "failed-precondition"});
    const totpRequest = {
      auth: {uid, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}},
      data: update,
    } as never;
    await updateUserPresence.run(totpRequest);
    assert.equal((await profile.collection("privatePresence").doc("current").get()).get("sessions")[sessionId].active, true);
  } finally {
    await db.recursiveDelete(profile);
  }
});
