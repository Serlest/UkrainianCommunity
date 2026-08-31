import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {
  type OrganizationRequestRetentionDependencies,
  organizationRequestRetentionJobCollection,
  processOrganizationRequest,
  processOrganizationRequestRetentionJob,
} from "./organizationRequestRetention";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const userId = "organization-retention-submitter";
const missingUserId = "organization-retention-missing-submitter";
const warningOrganizationId = "organization-retention-warning";
const expiredOrganizationId = "organization-retention-expired";
const resumableOrganizationId = "organization-retention-resumable";
const missingUserOrganizationId = "organization-retention-missing-user";
const concurrentOrganizationId = "organization-retention-concurrent";
const organizationIds = [
  warningOrganizationId,
  expiredOrganizationId,
  resumableOrganizationId,
  missingUserOrganizationId,
  concurrentOrganizationId,
];
const day = 24 * 60 * 60 * 1_000;
const now = Date.UTC(2026, 7, 27, 12);

before(async () => {
  if (!shouldRun) return;
  await db.collection("users").doc(userId).set({accountStatus: "active"});
});

after(async () => {
  if (!shouldRun) return;
  const jobs = await db.collection(organizationRequestRetentionJobCollection)
    .where("organizationId", "in", organizationIds)
    .get();
  await Promise.all([
    db.recursiveDelete(db.collection("users").doc(userId)),
    db.recursiveDelete(db.collection("users").doc(missingUserId)),
    ...organizationIds.map((organizationId) => db.recursiveDelete(
      db.collection("organizations").doc(organizationId)
    )),
    ...organizationIds.map((organizationId) => db.collection("organizationCreationProofs")
      .doc(organizationId)
      .delete()),
    ...jobs.docs.map((job) => job.ref.delete()),
    ...jobs.docs.map((job) => db.collection("auditLogs").doc(job.id).delete()),
  ]);
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

test("retention deletes Storage, Firestore and proof before completing evidence", {skip: !shouldRun}, async () => {
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
  const storagePrefixes: string[] = [];

  assert.equal(await processOrganizationRequest(
    expiredOrganizationId,
    now,
    successfulDependencies(storagePrefixes)
  ), "expired");
  assert.equal((await organizationReference.get()).exists, false);
  assert.equal((await organizationReference.collection("photos").doc("photo-1").get()).exists, false);
  assert.equal((await db.collection("organizationCreationProofs").doc(expiredOrganizationId).get()).exists, false);
  assert.deepEqual(storagePrefixes, [`organizations/${expiredOrganizationId}/`]);

  const job = await retentionJob(expiredOrganizationId);
  assert.equal(job.data().status, "completed");
  assert.equal((await db.collection("auditLogs").doc(job.id).get()).exists, true);
  assert.equal((await db.collection("users").doc(userId)
    .collection("notificationInbox").doc(job.id).get()).exists, true);
  assert.equal(await processOrganizationRequest(
    expiredOrganizationId,
    now,
    successfulDependencies(storagePrefixes)
  ), "skipped");
  assert.deepEqual(storagePrefixes, [`organizations/${expiredOrganizationId}/`]);
});

test("retention resumes after Firestore deletion fails without deleting Storage twice", {skip: !shouldRun}, async () => {
  const organizationReference = db.collection("organizations").doc(resumableOrganizationId);
  await Promise.all([
    organizationReference.set({
      name: "Resumable organization",
      submittedByUserId: userId,
      moderationStatus: "needsRevision",
      updatedAt: Timestamp.fromMillis(now - 31 * day),
    }),
    organizationReference.collection("photos").doc("photo-1").set({path: "test"}),
    db.collection("organizationCreationProofs").doc(resumableOrganizationId).set({userId}),
  ]);
  const storagePrefixes: string[] = [];
  let recursiveDeleteAttempts = 0;
  const dependencies: OrganizationRequestRetentionDependencies = {
    async deleteStoragePrefix(prefix: string) {
      storagePrefixes.push(prefix);
    },
    async recursivelyDeleteOrganization(organizationId: string) {
      recursiveDeleteAttempts += 1;
      await db.recursiveDelete(db.collection("organizations").doc(organizationId));
      if (recursiveDeleteAttempts === 1) throw new Error("Injected recursive delete failure.");
    },
  };

  await assert.rejects(
    () => processOrganizationRequest(resumableOrganizationId, now, dependencies),
    /Injected recursive delete failure/
  );
  const pendingJob = await retentionJob(resumableOrganizationId);
  assert.equal(pendingJob.data().status, "storageDeleted");
  assert.equal(pendingJob.data().leaseId, null);
  assert.equal((await organizationReference.get()).exists, false);

  assert.equal(await processOrganizationRequestRetentionJob(
    pendingJob.id,
    now + 1,
    dependencies
  ), "completed");
  assert.deepEqual(storagePrefixes, [`organizations/${resumableOrganizationId}/`]);
  assert.equal(recursiveDeleteAttempts, 2);
  assert.equal((await organizationReference.get()).exists, false);
  assert.equal((await pendingJob.ref.get()).data()?.status, "completed");
  assert.equal((await db.collection("auditLogs").doc(pendingJob.id).get()).exists, true);
});

test("retention cleans an expired request when the submitter document is absent", {skip: !shouldRun}, async () => {
  const organizationReference = db.collection("organizations").doc(missingUserOrganizationId);
  await organizationReference.set({
    name: "Missing submitter organization",
    submittedByUserId: missingUserId,
    moderationStatus: "rejected",
    updatedAt: Timestamp.fromMillis(now - 31 * day),
  });
  const storagePrefixes: string[] = [];

  assert.equal(await processOrganizationRequest(
    missingUserOrganizationId,
    now,
    successfulDependencies(storagePrefixes)
  ), "expired");
  const job = await retentionJob(missingUserOrganizationId);
  assert.equal((await organizationReference.get()).exists, false);
  assert.equal(job.data().status, "completed");
  assert.deepEqual(storagePrefixes, [`organizations/${missingUserOrganizationId}/`]);
  assert.equal((await db.collection("users").doc(missingUserId)
    .collection("notificationInbox").doc(job.id).get()).exists, false);
  assert.equal((await db.collection("auditLogs").doc(job.id).get()).data()?.targetUserId, missingUserId);
});

test("retention lease prevents two workers from deleting the same request", {skip: !shouldRun}, async () => {
  const organizationReference = db.collection("organizations").doc(concurrentOrganizationId);
  await organizationReference.set({
    name: "Concurrent organization",
    submittedByUserId: userId,
    moderationStatus: "rejected",
    updatedAt: Timestamp.fromMillis(now - 31 * day),
  });
  let releaseStorage!: () => void;
  let reportStorageStarted!: () => void;
  const storageStarted = new Promise<void>((resolve) => {
    reportStorageStarted = resolve;
  });
  const storageReleased = new Promise<void>((resolve) => {
    releaseStorage = resolve;
  });
  let storageDeletes = 0;
  const dependencies: OrganizationRequestRetentionDependencies = {
    async deleteStoragePrefix() {
      storageDeletes += 1;
      reportStorageStarted();
      await storageReleased;
    },
    async recursivelyDeleteOrganization(organizationId: string) {
      await db.recursiveDelete(db.collection("organizations").doc(organizationId));
    },
  };

  const firstWorker = processOrganizationRequest(concurrentOrganizationId, now, dependencies);
  await storageStarted;
  assert.equal(await processOrganizationRequest(
    concurrentOrganizationId,
    now + 1,
    dependencies
  ), "skipped");
  releaseStorage();
  assert.equal(await firstWorker, "expired");
  assert.equal(storageDeletes, 1);
  assert.equal((await organizationReference.get()).exists, false);
});

function successfulDependencies(
  storagePrefixes: string[]
): OrganizationRequestRetentionDependencies {
  return {
    async deleteStoragePrefix(prefix: string) {
      storagePrefixes.push(prefix);
    },
    async recursivelyDeleteOrganization(organizationId: string) {
      await db.recursiveDelete(db.collection("organizations").doc(organizationId));
    },
  };
}

async function retentionJob(organizationId: string) {
  const snapshot = await db.collection(organizationRequestRetentionJobCollection)
    .where("organizationId", "==", organizationId)
    .get();
  assert.equal(snapshot.size, 1);
  return snapshot.docs[0];
}
