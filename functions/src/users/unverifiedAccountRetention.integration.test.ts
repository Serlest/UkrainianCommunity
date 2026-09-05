import {strict as assert} from "node:assert";
import {after, beforeEach, mock, test} from "node:test";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {
  exactProfileVersion, UnverifiedRetentionStore, unverifiedRetentionCollections,
} from "./unverifiedAccountRetentionStore";
import {
  executeUnverifiedDeletion, inspectUnverifiedAccount,
  type RetentionDeletionJob, type UnverifiedRetentionDependencies,
} from "./unverifiedAccountRetentionWorker";
import type {RetentionAuthIdentity} from "./unverifiedAccountRetentionPolicy";
import {adminStorage} from "../firebase/admin";
import {hasUnverifiedAccountRelatedData} from "./unverifiedAccountRetention";
import {accountDeletionReferencePolicies, type AccountDeletionReferencePolicy} from "./accountDeletionPolicy";

// Never run fixtures against a real project, or another task's emulator dataset.
const projectId = "demo-uac-unverified-retention";
const enabled = process.env.GCLOUD_PROJECT === projectId
  && /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const database = new Firestore({projectId});
const uid = "unverified-retention-fixture";
const profile = database.collection("users").doc(uid);
const jobs = database.collection(unverifiedRetentionCollections.jobs);
const control = database.collection(unverifiedRetentionCollections.control).doc("daily");
const now = Date.parse("2026-09-03T12:00:00Z");
const job: RetentionDeletionJob = {uid, identityFingerprint: "a".repeat(64), profileVersion: null,
  status: "authDeletePending"};
const options = {skip: !enabled};

async function cleanFixtures() {
  await Promise.all([profile.delete(), jobs.doc(uid).delete(), control.delete(),
    ...["completed", "cancelled", "manualReview", "authDeletePending", "authDeleted", "recent"]
      .map((id) => jobs.doc(`retention-test-${id}`).delete())]);
}
beforeEach(async () => { if (enabled) await cleanFixtures(); });
after(async () => { if (enabled) await cleanFixtures(); await database.terminate(); });

test("Firestore allows only one concurrent retention run", options, async () => {
  const first = new UnverifiedRetentionStore(database, "first", () => now);
  const second = new UnverifiedRetentionStore(database, "second", () => now);
  const claims = await Promise.all([first.acquire(), second.acquire()]);
  assert.equal(claims.filter(Boolean).length, 1);
});

test("job claim is atomic and refuses changed profile versions", options, async () => {
  const store = new UnverifiedRetentionStore(database, "test", () => now);
  await store.acquire(); await profile.set({test: true});
  const version = exactProfileVersion(await profile.get());
  await profile.update({changed: true});
  assert.equal(await store.claimJob({...job, profileVersion: version}), false);
  const currentVersion = exactProfileVersion(await profile.get());
  const claims = await Promise.all([
    store.claimJob({...job, profileVersion: currentVersion}),
    store.claimJob({...job, profileVersion: currentVersion}),
  ]);
  assert.deepEqual(claims.sort(), [false, true]);
});

test("nanosecond profile version and absent-root guards prevent overwrites", options, async () => {
  const store = new UnverifiedRetentionStore(database, "test", () => now);
  await store.acquire(); await profile.set({test: true});
  const snapshot = await profile.get();
  const update = snapshot.updateTime!;
  const wrong = `${update.seconds}:${update.nanoseconds + 1}`;
  assert.equal(await store.deleteProfileIfUnchanged(uid, wrong), false);
  assert.equal(await store.deleteProfileIfUnchanged(uid, null), false);
  assert.ok((await profile.get()).exists);
  assert.equal(await store.deleteProfileIfUnchanged(uid, exactProfileVersion(snapshot)), true);
  assert.equal(await store.deleteProfileIfUnchanged(uid, exactProfileVersion(snapshot)), true);
});

test("expired owner cannot delete or overwrite the next worker's lease", options, async () => {
  let clock = now;
  const stale = new UnverifiedRetentionStore(database, "stale", () => clock);
  await stale.acquire(); await profile.set({test: true});
  const version = exactProfileVersion(await profile.get());
  clock += 16 * 60_000;
  await assert.rejects(stale.assertLease(), /lease lost/);
  const current = new UnverifiedRetentionStore(database, "current", () => clock);
  assert.ok(await current.acquire());
  await assert.rejects(stale.deleteProfileIfUnchanged(uid, version), /lease lost/);
  await assert.rejects(stale.checkpoint("wrong"), /lease lost/);
  await stale.release(); await current.assertLease();
  assert.ok((await profile.get()).exists);
});

test("cursor survives release and is used by the next invocation", options, async () => {
  const first = new UnverifiedRetentionStore(database, "first", () => now);
  await first.acquire(); await first.checkpoint("page-two"); await first.release();
  const second = new UnverifiedRetentionStore(database, "second", () => now);
  assert.deepEqual(await second.acquire(), {cursor: "page-two"});
  await second.checkpoint(undefined); await second.release();
  assert.deepEqual(await first.acquire(), {cursor: undefined});
});

test("expired receipts are pruned, pending/manual-review jobs are not", options, async () => {
  const store = new UnverifiedRetentionStore(database, "test", () => now);
  await store.acquire();
  for (const status of ["completed", "cancelled", "manualReview", "authDeletePending", "authDeleted"]) {
    await jobs.doc(`retention-test-${status}`).set({status, receiptExpiresAt: Timestamp.fromMillis(now - 1)});
  }
  await jobs.doc("retention-test-recent").set({status: "completed", receiptExpiresAt: Timestamp.fromMillis(now + 1)});
  assert.equal(await store.pruneReceipts(), 2);
  for (const status of ["manualReview", "authDeletePending", "authDeleted", "recent"]) {
    assert.ok((await jobs.doc(`retention-test-${status}`).get()).exists);
  }
});

test("a persisted journal resumes after Auth commits but its response is lost", options, async () => {
  const created = Timestamp.fromMillis(now - 40 * 86_400_000);
  let identity: RetentionAuthIdentity | undefined = {uid, email: "synthetic@example.invalid", emailVerified: false,
    disabled: false, createdAt: created.toDate().toISOString(), providerIds: ["password"],
    hasCustomClaims: false, hasMFA: false, hasPhone: false, hasPhoto: false};
  await profile.set({id: uid, email: identity.email, globalRole: "user", accountStatus: "active",
    isBlocked: false, blockState: "active", warningCount: 0, communityMemberships: [], createdAt: created, updatedAt: created});
  const first = new UnverifiedRetentionStore(database, "first", () => now);
  await first.acquire();
  function dependencies(store: UnverifiedRetentionStore): UnverifiedRetentionDependencies {
    return {now: () => now, getIdentity: async () => identity, hasRelatedData: async () => false,
      getProfile: (id) => store.getProfile(id), claimJob: (input) => store.claimJob(input),
      setJobStatus: (id, status) => store.setJobStatus(id, status), assertLease: () => store.assertLease(),
      deleteIdentity: async () => { identity = undefined; throw new Error("lost response"); },
      deleteProfileIfUnchanged: (id, version) => store.deleteProfileIfUnchanged(id, version)};
  }
  const inspection = await inspectUnverifiedAccount(uid, dependencies(first)); assert.ok(inspection.eligible);
  await assert.rejects(executeUnverifiedDeletion(inspection.job, dependencies(first)), /lost response/);
  assert.ok((await profile.get()).exists);
  await first.release();
  const second = new UnverifiedRetentionStore(database, "second", () => now);
  await second.acquire();
  const pending = await second.pendingJobs(); assert.equal(pending.length, 1);
  assert.equal(await executeUnverifiedDeletion(pending[0], dependencies(second), true), "completed");
  assert.equal((await profile.get()).exists, false);
  assert.equal((await jobs.doc(uid).get()).get("status"), "completed");
  assert.deepEqual(await second.pendingJobs(), []);
});

test("real Firestore queries protect references, roles, public profiles and dangling children", options, async () => {
  const storage = mock.method(adminStorage, "bucket", () => ({getFiles: async () => [[]]}) as never);
  const fixtures: {path: string; data: Record<string, unknown>}[] = [
    {path: `publicProfiles/${uid}`, data: {id: uid}},
    {path: `analyticsUserActivity/${uid}`, data: {lastActiveAt: Timestamp.now()}},
    {path: `users/${uid}/contentPlanningDrafts/retention-test`, data: {ownerUserId: uid}},
    ...[["organizations", "ownerId"], ["organizationCreationProofs", "userId"],
      ["likes", "userId"], ["registrations", "userId"], ["feedback", "userId"]]
      .map(([collection, field]) => ({path: `${collection}/unverified-retention-reference`, data: {[field]: uid}})),
    ...(accountDeletionReferencePolicies as readonly AccountDeletionReferencePolicy[]).map((policy) => ({
      path: policy.scope === "collection" ? `${policy.collection}/unverified-retention-reference`
        : `retentionTestParents/fixture/${policy.collection}/unverified-retention-reference`,
      data: {[policy.field]: policy.operator === "array-contains" ? [uid] : uid,
        ...Object.fromEntries((policy.filters ?? []).map((filter) =>
          [filter.field, filter.operator === "in" ? (filter.value as string[])[0] : filter.value]))},
    })),
  ];
  try {
    assert.equal(await hasUnverifiedAccountRelatedData(uid), false);
    for (const fixture of fixtures) {
      const reference = database.doc(fixture.path);
      try {
        await reference.set(fixture.data);
        assert.equal(await hasUnverifiedAccountRelatedData(uid), true, fixture.path);
      } finally { await reference.delete(); }
    }
    assert.equal(await hasUnverifiedAccountRelatedData(uid), false);
  } finally { storage.mock.restore(); }
});

test("Storage leftovers block cleanup and a listing error is not treated as absence", options, async () => {
  const prefixes: string[] = [];
  let fail = false;
  const storage = mock.method(adminStorage, "bucket", () => ({getFiles: async ({prefix}: {prefix: string}) => {
    prefixes.push(prefix);
    if (fail) throw new Error("Storage permission denied");
    return [prefix.startsWith("users/") ? [{name: "orphaned-cover.jpg"}] : []];
  }}) as never);
  try {
    assert.equal(await hasUnverifiedAccountRelatedData(uid), true);
    assert.deepEqual(prefixes, [`profileImages/${uid}/`, `users/${uid}/`]);
    fail = true;
    await assert.rejects(hasUnverifiedAccountRelatedData(uid), /Storage permission denied/);
  } finally { storage.mock.restore(); }
});
