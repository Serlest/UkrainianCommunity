import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {processOrganizationRequest} from "./organizationRequestRetention";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const userId = "organization-retention-submitter";
const warningOrganizationId = "organization-retention-warning";
const expiredOrganizationId = "organization-retention-expired";
const day = 24 * 60 * 60 * 1_000;
const now = Date.UTC(2026, 7, 27, 12);

before(async () => {
  if (!shouldRun) return;
  await db.collection("users").doc(userId).set({accountStatus: "active"});
});

after(async () => {
  if (!shouldRun) return;
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(userId)),
    db.recursiveDelete(db.collection("organizations").doc(warningOrganizationId)),
    db.recursiveDelete(db.collection("organizations").doc(expiredOrganizationId)),
    db.collection("organizationCreationProofs").doc(expiredOrganizationId).delete(),
  ]);
  const audit = await db.collection("auditLogs").where("targetUserId", "==", userId).get();
  await Promise.all(audit.docs.map((document) => document.ref.delete()));
});

test("retention warns once and preserves an editable organization request", {skip: !shouldRun}, async () => {
  await db.collection("organizations").doc(warningOrganizationId).set({
    name: "Warning organization",
    submittedByUserId: userId,
    moderationStatus: "needsRevision",
    updatedAt: Timestamp.fromMillis(now - 24 * day),
  });

  assert.equal(await processOrganizationRequest(warningOrganizationId, now), "warning");
  assert.equal(await processOrganizationRequest(warningOrganizationId, now), "skipped");
  assert.equal((await db.collection("organizations").doc(warningOrganizationId).get()).exists, true);

  const notifications = await db.collection("users").doc(userId)
    .collection("notificationInbox")
    .where("type", "==", "organizationRequestCleanupWarning")
    .get();
  assert.equal(notifications.size, 1);
});

test("retention deletes an expired request, proof, subcollections and writes evidence", {skip: !shouldRun}, async () => {
  const organizationReference = db.collection("organizations").doc(expiredOrganizationId);
  await Promise.all([
    organizationReference.set({
      name: "Expired organization",
      submittedByUserId: userId,
      moderationStatus: "rejected",
      updatedAt: Timestamp.fromMillis(now - 31 * day),
    }),
    organizationReference.collection("photos").doc("photo-1").set({path: "test"}),
    db.collection("organizationCreationProofs").doc(expiredOrganizationId).set({userId}),
  ]);

  assert.equal(await processOrganizationRequest(expiredOrganizationId, now), "expired");
  assert.equal((await organizationReference.get()).exists, false);
  assert.equal((await organizationReference.collection("photos").doc("photo-1").get()).exists, false);
  assert.equal((await db.collection("organizationCreationProofs").doc(expiredOrganizationId).get()).exists, false);

  const [audit, notifications] = await Promise.all([
    db.collection("auditLogs")
      .where("targetUserId", "==", userId)
      .where("actionType", "==", "organizationRequestExpired")
      .get(),
    db.collection("users").doc(userId)
      .collection("notificationInbox")
      .where("type", "==", "organizationRequestExpired")
      .get(),
  ]);
  assert.equal(audit.size, 1);
  assert.equal(notifications.size, 1);
});
