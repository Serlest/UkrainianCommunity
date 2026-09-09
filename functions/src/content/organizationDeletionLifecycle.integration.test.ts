import {strict as assert} from "node:assert";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, beforeEach, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {adminStorage, db} from "../firebase/admin";
import {
  completeOrganizationDeletionNotifications,
  deleteOrganization,
  organizationDeletionOperationCollection,
  organizationDeletionHistoryQueries,
  prepareOrganizationDeletionNotificationPlan,
  repairDeletedOrganizationLifecycleFromCreationProof,
} from "./contentDeletion";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const organizationId = "organization-deletion-lifecycle";
const actorUserId = "organization-deletion-actor";
const ownerUserId = "organization-deletion-owner";
const adminUserId = "organization-deletion-admin";
const moderatorUserId = "organization-deletion-moderator";
const userIds = [ownerUserId, adminUserId, moderatorUserId];

beforeEach(async () => {
  if (!live) return;
  await cleanup();
  await Promise.all([
    db.doc(`users/${ownerUserId}`).set({preferredLanguage: "uk"}),
    db.doc(`users/${adminUserId}`).set({preferredLanguage: "de"}),
    db.doc(`users/${moderatorUserId}`).set({}),
  ]);
});

after(async () => {
  if (live) await cleanup();
});

test("deletion snapshots every organization role before the root document disappears", {
  skip: !live,
}, async () => {
  await db.doc(`organizations/${organizationId}`).set({
    name: "Testverein",
    ownerId: ownerUserId,
    adminIds: [adminUserId, ownerUserId],
    moderatorIds: [moderatorUserId, adminUserId],
  });

  const plan = await prepareOrganizationDeletionNotificationPlan(
    organizationId,
    actorUserId
  );
  assert.deepEqual(plan.recipients, [
    {userId: ownerUserId, role: "communityOwner"},
    {userId: adminUserId, role: "communityAdmin"},
    {userId: moderatorUserId, role: "communityModerator"},
  ]);
  const operation = await db.doc(
    `${organizationDeletionOperationCollection}/${organizationId}`
  ).get();
  assert.equal(operation.exists, true);
  assert.equal(operation.get("expiresAt") instanceof Timestamp, true);

  await db.doc(`organizations/${organizationId}`).delete();
  await completeOrganizationDeletionNotifications(plan);
  await completeOrganizationDeletionNotifications(plan);

  for (const userId of userIds) {
    const notification = await db.doc(
      `users/${userId}/notificationInbox/organizationDeleted_${organizationId}_${userId}`
    ).get();
    assert.equal(notification.exists, true);
    assert.equal(notification.get("actionType"), "none");
    assert.equal(notification.get("metadata.reasonCode"), "organizationDeleted");
  }
  assert.match((await db.doc(
    `users/${ownerUserId}/notificationInbox/organizationDeleted_${organizationId}_${ownerUserId}`
  ).get()).get("title"), /видалено/iu);
  assert.match((await db.doc(
    `users/${adminUserId}/notificationInbox/organizationDeleted_${organizationId}_${adminUserId}`
  ).get()).get("title"), /gelöscht/iu);
  assert.equal((await db.doc(
    `${organizationDeletionOperationCollection}/${organizationId}`
  ).get()).exists, false);
});

test("guarded historical repair removes dead navigation and retains legal and audit evidence", {
  skip: !live,
}, async () => {
  const future = Timestamp.fromMillis(Date.now() + 60_000);
  await Promise.all([
    db.doc(`organizationCreationProofs/${organizationId}`).set({
      organizationId,
      organizationName: "Testverein",
      userId: ownerUserId,
      locale: "uk",
      expiresAt: future,
    }),
    db.doc(`auditLogs/${organizationId}`).set({organizationId, retained: true}),
    db.doc(`dsaCases/${organizationId}`).set({organizationId, retained: true}),
    db.doc(`users/${ownerUserId}/notificationInbox/old-request`).set({
      sourceId: organizationId,
      actionTargetId: organizationId,
      actionType: "openOrganizationRequest",
    }),
    db.doc(`users/${adminUserId}/notificationInbox/old-organization`).set({
      sourceId: organizationId,
      actionTargetId: organizationId,
      actionType: "openOrganization",
    }),
  ]);

  await repairDeletedOrganizationLifecycleFromCreationProof(
    organizationId,
    actorUserId
  );
  await repairDeletedOrganizationLifecycleFromCreationProof(
    organizationId,
    actorUserId
  );

  assert.equal((await db.doc(
    `users/${ownerUserId}/notificationInbox/old-request`
  ).get()).exists, false);
  assert.equal((await db.doc(
    `users/${adminUserId}/notificationInbox/old-organization`
  ).get()).exists, false);
  assert.equal((await db.doc(
    `users/${ownerUserId}/notificationInbox/organizationDeleted_${organizationId}_${ownerUserId}`
  ).get()).exists, true);
  assert.equal((await db.doc(`organizationCreationProofs/${organizationId}`).get()).exists, true);
  assert.equal((await db.doc(`auditLogs/${organizationId}`).get()).exists, true);
  assert.equal((await db.doc(`dsaCases/${organizationId}`).get()).exists, true);
});

async function cleanup(): Promise<void> {
  await Promise.all([
    db.doc(`organizations/${organizationId}`).delete(),
    db.doc(`organizationCreationProofs/${organizationId}`).delete(),
    db.doc(`auditLogs/${organizationId}`).delete(),
    db.doc(`dsaCases/${organizationId}`).delete(),
    db.doc(`${organizationDeletionOperationCollection}/${organizationId}`).delete(),
    ...userIds.map((userId) => db.recursiveDelete(db.doc(`users/${userId}`))),
  ]);
}


test("owner callable removes organization, news and actual stored images and notifies once", {
  skip: !live || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const newsId = "organization-deletion-news";
  const photoPath = `organizations/${organizationId}/photos/test.jpg`;
  const coverPath = `news/${newsId}/cover.jpg`;
  const bucket = adminStorage.bucket();
  await db.doc(`users/${actorUserId}`).set({globalRole: "owner", accountStatus: "active"});
  await db.doc(`organizations/${organizationId}`).set({name: "Test", ownerId: ownerUserId, moderationStatus: "approved"});
  await db.doc(`organizations/${organizationId}/photos/test`).set({uploadedBy: ownerUserId});
  await db.doc(`news/${newsId}`).set({organizationId, authorId: ownerUserId});
  await bucket.file(photoPath).save(Buffer.from("test-photo"));
  await bucket.file(coverPath).save(Buffer.from("test-cover"));
  const request = {auth: {uid: actorUserId, token: {email_verified: true}}, data: {organizationId}} as never;
  try {
    assert.equal((await deleteOrganization.run(request)).status, "deleted");
    assert.equal((await db.doc(`organizations/${organizationId}`).get()).exists, false);
    assert.equal((await db.doc(`organizations/${organizationId}/photos/test`).get()).exists, false);
    assert.equal((await db.doc(`news/${newsId}`).get()).exists, false);
    assert.equal((await bucket.file(photoPath).exists())[0], false);
    assert.equal((await bucket.file(coverPath).exists())[0], false);
    assert.equal((await db.collection("organizations").where("ownerId", "==", ownerUserId).get()).empty, true);
    assert.equal((await deleteOrganization.run(request)).status, "alreadyDeleted");
    const notices = await db.collection(`users/${ownerUserId}/notificationInbox`).where("sourceId", "==", organizationId).get();
    assert.equal(notices.size, 1);
    assert.equal(notices.docs[0].get("actionType"), "none");
    assert.match(notices.docs[0].get("metadata.reason"), /Test видалено/);
  } finally {
    await db.doc(`users/${actorUserId}`).delete();
    await db.recursiveDelete(db.doc(`news/${newsId}`));
    await bucket.file(photoPath).delete({ignoreNotFound: true});
    await bucket.file(coverPath).delete({ignoreNotFound: true});
  }
});


test("all organization deletion collection-group queries have deployment indexes", () => {
  const config = JSON.parse(readFileSync(resolve(__dirname, "../../../Firebase/firestore.indexes.json"), "utf8"));
  for (const [collection, field] of organizationDeletionHistoryQueries) {
    assert.ok(config.fieldOverrides.some((entry: {collectionGroup: string; fieldPath: string; indexes: Array<{queryScope: string; order?: string}>}) =>
      entry.collectionGroup === collection && entry.fieldPath === field &&
      entry.indexes.some(index => index.queryScope === "COLLECTION_GROUP" && Boolean(index.order))
    ), `Missing index: ${collection}.${field}`);
  }
});

test("missing organization deletion index leaves the organization and owner intact", {skip: !live}, async t => {
  await db.doc(`users/${actorUserId}`).set({globalRole: "owner", accountStatus: "active"});
  await db.doc(`organizations/${organizationId}`).set({name: "Test", ownerId: ownerUserId});
  const original = db.collectionGroup.bind(db);
  const mocked = t.mock.method(db, "collectionGroup", (name: string) => {
    const group = original(name);
    if (name === "notificationInbox") {
      const where = group.where.bind(group);
      t.mock.method(group, "where", (...args: Parameters<typeof group.where>) => {
        const query = where(...args);
        if (args[0] === "sourceId") t.mock.method(query, "limit", () => {throw Object.assign(new Error("Missing index"), {code: 9});});
        return query;
      });
    }
    return group;
  });
  try {
    await assert.rejects(deleteOrganization.run({auth: {uid: actorUserId, token: {email_verified: true}}, data: {organizationId}} as never), {code: "unavailable"});
    assert.equal((await db.doc(`organizations/${organizationId}`).get()).get("ownerId"), ownerUserId);
    assert.equal((await db.doc(`users/${ownerUserId}`).get()).exists, true);
    assert.equal((await db.doc(`${organizationDeletionOperationCollection}/${organizationId}`).get()).exists, false);
  } finally {
    mocked.mock.restore();
    await db.doc(`users/${actorUserId}`).delete();
  }
});
