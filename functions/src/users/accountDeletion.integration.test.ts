import {strict as assert} from "node:assert";
import {createHash} from "node:crypto";
import {test} from "node:test";
import {adminAuth, db} from "../firebase/admin";
import {deleteOwnAccount} from "./accountDeletion";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST && process.env.FIREBASE_STORAGE_EMULATOR_HOST);
test("Build80 deletion resumes after Auth failure without losing canonical DSA evidence", {skip: !enabled}, async t => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  for (const key of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) assert.match(process.env[key] ?? "", /^(127\.0\.0\.1|localhost):/);
  const uid = `fix80-delete-${Date.now()}`;
  await adminAuth.createUser({uid, email: `${uid}@example.org`, emailVerified: true});
  await db.doc(`users/${uid}`).set({id: uid, globalRole: "user", accountStatus: "active", displayName: "Deletion fixture"});
  await db.doc(`users/${uid}/activityHistory/one`).set({title: "Private"});
  await db.doc(`analyticsConsentStates/${uid}`).set({enabled: true});
  await db.doc(`feedback/${uid}`).set({userId: uid, userDisplayName: "Deletion fixture"});
  await db.doc(`feedback/${uid}/messages/evidence`).set({body: "Retained evidence"});
  await db.doc(`dsaCases/${uid}`).set({reporterUserId: uid, status: "submitted"});
  const request = {auth: {uid, token: {email_verified: true, auth_time: Math.floor(Date.now() / 1000)}}, data: {}} as never;
  const original = adminAuth.deleteUser.bind(adminAuth);
  let failed = false;
  const mocked = t.mock.method(adminAuth, "deleteUser", async (id: string) => {
    if (!failed) {failed = true; throw Object.assign(new Error("Injected Auth outage"), {code: "auth/internal-error"});}
    return original(id);
  });
  await assert.rejects(deleteOwnAccount.run(request), {code: "auth/internal-error"});
  assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`analyticsConsentStates/${uid}`).get()).exists, false);
  assert.equal((await adminAuth.getUser(uid)).uid, uid);
  const completed = await deleteOwnAccount.run(request);
  assert.equal(completed.status, "deleted");
  mocked.mock.restore();
  await assert.rejects(adminAuth.getUser(uid), {code: "auth/user-not-found"});
  assert.equal((await db.doc(`feedback/${uid}`).get()).exists, true);
  assert.equal((await db.doc(`feedback/${uid}/messages/evidence`).get()).exists, true);
  assert.notEqual((await db.doc(`feedback/${uid}`).get()).get("userId"), uid);
  const receiptId = createHash("sha256").update(`account-deletion:${uid}`).digest("hex");
  assert.equal((await db.doc(`accountDeletionOperations/${receiptId}`).get()).get("status"), "completed");
  assert.equal((await deleteOwnAccount.run(request)).status, "deleted");
});
