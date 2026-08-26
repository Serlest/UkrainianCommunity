import {strict as assert} from "node:assert";
import {test} from "node:test";
import {db} from "../firebase/admin";
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
