import {strict as assert} from "node:assert";
import {afterEach, mock, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import type {UserRecord} from "firebase-admin/auth";
import {adminAuth, adminStorage, db} from "../firebase/admin";
import {retentionMode, runUnverifiedAccountRetention} from "./unverifiedAccountRetention";
import {UnverifiedRetentionStore} from "./unverifiedAccountRetentionStore";
import {
  authRetentionSkipReason, profileRetentionSkipReason,
  type RetentionAuthIdentity,
} from "./unverifiedAccountRetentionPolicy";
import {
  executeUnverifiedDeletion, inspectUnverifiedAccount,
  type RetentionDeletionJob, type RetentionProfileSnapshot, type UnverifiedRetentionDependencies,
} from "./unverifiedAccountRetentionWorker";

const now = Date.parse("2026-09-03T12:00:00Z");
const day = 86_400_000;
function identity(patch: Partial<RetentionAuthIdentity> = {}): RetentionAuthIdentity {
  return {uid: "abandoned-user", email: "synthetic@example.invalid", emailVerified: false, disabled: false,
    createdAt: new Date(now - 40 * day).toISOString(), lastSignInAt: new Date(now - 40 * day).toISOString(),
    providerIds: ["password"], hasCustomClaims: false, hasMFA: false, hasPhone: false, hasPhoto: false, ...patch};
}
function profile() {
  return {id: "abandoned-user", email: "synthetic@example.invalid", globalRole: "user", accountStatus: "active",
    isBlocked: false, blockState: "active", warningCount: 0, communityMemberships: [],
    createdAt: Timestamp.fromMillis(now - 40 * day), updatedAt: Timestamp.fromMillis(now - 40 * day)};
}

afterEach(() => mock.restoreAll());

test("30-day and 7-day boundaries are inclusive", () => {
  assert.equal(authRetentionSkipReason(identity(), now), undefined);
  const boundary = identity({createdAt: new Date(now - 30 * day).toISOString(),
    lastSignInAt: new Date(now - 7 * day).toISOString()});
  assert.equal(authRetentionSkipReason(boundary, now), undefined);
  assert.equal(authRetentionSkipReason({...boundary, createdAt: new Date(now - 30 * day + 1).toISOString()}, now), "tooYoung");
  assert.equal(authRetentionSkipReason({...boundary, lastRefreshAt: new Date(now - 7 * day + 1).toISOString()}, now), "recentSession");
});

test("verified accounts are never candidates even after years without activity", () => {
  const inactiveButVerified = identity({emailVerified: true,
    createdAt: "2010-01-01T00:00:00Z", lastSignInAt: "2010-01-01T00:00:00Z"});
  assert.equal(authRetentionSkipReason(inactiveButVerified, now), "verified");
});

const excludedIdentities: [string, Partial<RetentionAuthIdentity>, string][] = [
  ["verified email", {emailVerified: true}, "verified"],
  ["disabled", {disabled: true}, "protectedIdentity"],
  ["claims", {hasCustomClaims: true}, "protectedIdentity"],
  ["MFA", {hasMFA: true}, "protectedIdentity"],
  ["phone", {hasPhone: true}, "protectedIdentity"],
  ["photo", {hasPhoto: true}, "protectedIdentity"],
  ["anonymous", {providerIds: []}, "protectedIdentity"],
  ["Google", {providerIds: ["google.com"]}, "protectedIdentity"],
  ["linked providers", {providerIds: ["password", "apple.com"]}, "protectedIdentity"],
  ["recent sign-in", {lastSignInAt: new Date(now - day).toISOString()}, "recentSession"],
  ["bad refresh date", {lastRefreshAt: "invalid"}, "invalidMetadata"],
  ["future timestamp", {createdAt: new Date(now + day).toISOString()}, "invalidMetadata"],
  ["invalid creation date", {createdAt: "invalid"}, "invalidMetadata"],
  ["missing email", {email: undefined}, "invalidMetadata"],
  ["invalid document ID", {uid: "a/b"}, "invalidMetadata"],
];
for (const [name, patch, reason] of excludedIdentities) {
  test(`retention protects ${name}`, () => assert.equal(authRetentionSkipReason(identity(patch), now), reason));
}

test("only an unchanged registration profile or absent root is eligible", () => {
  assert.equal(profileRetentionSkipReason(identity(), undefined, now), undefined);
  assert.equal(profileRetentionSkipReason(identity(), profile(), now), undefined);
  const patches = [
    {globalRole: "owner"}, {globalRole: "admin"}, {communityMemberships: [{role: "owner"}]},
    {accountStatus: "deactivated"}, {warningCount: 1}, {id: "someone-else"},
    {email: "other@example.invalid"}, {lastSeenAt: Timestamp.fromMillis(now)},
    {createdAt: "2026-01-01"}, {createdAt: Timestamp.fromMillis(now - 50 * day)},
    {updatedAt: new Timestamp(profile().updatedAt.seconds, 1)},
  ];
  for (const patch of patches) assert.equal(profileRetentionSkipReason(identity(), {...profile(), ...patch}, now), "changedProfile");
});

function fixture() {
  const state = {identity: identity() as RetentionAuthIdentity | undefined,
    profile: {data: profile(), version: "1:184433000"} as RetentionProfileSnapshot,
    job: undefined as RetentionDeletionJob | undefined, related: false, authDeletes: 0, profileDeletes: 0,
    statuses: [] as string[]};
  const deps: UnverifiedRetentionDependencies = {
    now: () => now, getIdentity: async () => state.identity, getProfile: async () => state.profile,
    hasRelatedData: async () => state.related,
    claimJob: async (job) => { if (state.job) return false; state.job = {...job}; return true; },
    assertLease: async () => {},
    setJobStatus: async (_uid, status) => { state.job!.status = status; state.statuses.push(status); },
    deleteIdentity: async () => { state.authDeletes += 1; state.identity = undefined; },
    deleteProfileIfUnchanged: async (_uid, version) => {
      if (state.profile.version !== null && version !== state.profile.version) return false;
      state.profileDeletes += 1; state.profile = {version: null}; return true;
    },
  };
  const candidate = async () => {
    const inspection = await inspectUnverifiedAccount("abandoned-user", deps);
    assert.ok(inspection.eligible); return inspection.job;
  };
  return {state, deps, candidate};
}

test("related data excludes a candidate and inspection never creates a job", async () => {
  const {state, deps} = fixture(); state.related = true;
  assert.deepEqual(await inspectUnverifiedAccount("abandoned-user", deps), {eligible: false, reason: "relatedData"});
  assert.equal(state.job, undefined);
});

test("successful deletion is Auth-first, read back, journaled and idempotent", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  const removeProfile = deps.deleteProfileIfUnchanged;
  deps.deleteProfileIfUnchanged = async (uid, version) => {
    assert.equal(state.identity, undefined); assert.equal(state.job?.status, "authDeleted");
    return removeProfile(uid, version);
  };
  assert.equal(await executeUnverifiedDeletion(job, deps), "completed");
  assert.equal(await executeUnverifiedDeletion(job, deps), "skipped");
  assert.equal(state.authDeletes, 1); assert.equal(state.profileDeletes, 1);
  assert.deepEqual(state.statuses, ["authDeleted", "completed"]);
});

for (const changed of ["email", "signIn", "profile", "linkedData"] as const) {
  test(`fresh ${changed} change cancels deletion`, async () => {
    const {state, deps, candidate} = fixture(); const job = await candidate();
    if (changed === "email") state.identity!.emailVerified = true;
    if (changed === "signIn") state.identity!.lastSignInAt = new Date(now).toISOString();
    if (changed === "profile") state.profile.version = "1:184433001";
    if (changed === "linkedData") state.related = true;
    assert.equal(await executeUnverifiedDeletion(job, deps), "skipped");
    assert.equal(state.authDeletes, 0); assert.equal(state.profileDeletes, 0);
  });
}

test("last Auth check catches verification after the related-data check", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  deps.hasRelatedData = async () => { state.identity!.emailVerified = true; return false; };
  assert.equal(await executeUnverifiedDeletion(job, deps), "skipped");
  assert.equal(state.authDeletes, 0);
});

test("expired lease and read failures never trigger deletion", async () => {
  for (const operation of ["assertLease", "getIdentity", "hasRelatedData"] as const) {
    const {state, deps, candidate} = fixture(); const job = await candidate();
    deps[operation] = async () => { throw new Error("unavailable"); };
    await assert.rejects(executeUnverifiedDeletion(job, deps), /unavailable/);
    assert.equal(state.authDeletes, 0); assert.equal(state.profileDeletes, 0);
  }
});

test("uncertain Auth deletion keeps the profile; a later run safely resumes", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  deps.deleteIdentity = async () => { state.identity = undefined; throw new Error("timeout after commit"); };
  await assert.rejects(executeUnverifiedDeletion(job, deps), /timeout/);
  assert.ok(state.profile.data); assert.equal(state.job?.status, "authDeletePending");
  assert.equal(await executeUnverifiedDeletion(state.job!, deps, true), "completed");
  assert.equal(state.profile.data, undefined);
});

test("failed Auth deletion does not erase the profile", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  deps.deleteIdentity = async () => { throw new Error("permission denied"); };
  await assert.rejects(executeUnverifiedDeletion(job, deps), /permission denied/);
  assert.ok(state.identity); assert.ok(state.profile.data); assert.equal(state.profileDeletes, 0);
});

test("recreated Auth identity during recovery is retained for manual review", async () => {
  const {state, deps, candidate} = fixture(); state.job = await candidate(); state.job.status = "authDeleted";
  assert.equal(await executeUnverifiedDeletion(state.job, deps, true), "manualReview");
  assert.equal(state.authDeletes, 0); assert.ok(state.profile.data);
});

test("concurrently modified Firestore data after Auth deletion is retained", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  deps.deleteIdentity = async () => { state.identity = undefined; state.profile.version = "2:0"; };
  assert.equal(await executeUnverifiedDeletion(job, deps), "manualReview");
  assert.ok(state.profile.data); assert.equal(state.profileDeletes, 0);
});

test("new references after Auth deletion are retained for manual review", async () => {
  const {state, deps, candidate} = fixture(); const job = await candidate();
  deps.deleteIdentity = async () => { state.identity = undefined; state.related = true; };
  assert.equal(await executeUnverifiedDeletion(job, deps), "manualReview");
  assert.ok(state.profile.data);
});

test("recovery finishes after profile deletion but before completion receipt", async () => {
  const {state, deps, candidate} = fixture(); state.job = await candidate(); state.job.status = "authDeleted";
  state.identity = undefined; state.profile = {version: null};
  assert.equal(await executeUnverifiedDeletion(state.job, deps, true), "completed");
});

test("unknown mode fails closed; default off never reads or writes", async () => {
  assert.equal(retentionMode(undefined), "off");
  assert.throws(() => retentionMode("enabled"), /Invalid/);
  mock.method(adminAuth, "listUsers", async () => { throw new Error("unexpected Auth read"); });
  mock.method(db, "runTransaction", async () => { throw new Error("unexpected transaction"); });
  assert.equal((await runUnverifiedAccountRetention("off")).scanned, 0);
});

test("report finds an eligible candidate without any write or Auth deletion", async () => {
  const created = new Date(Date.now() - 40 * day).toUTCString();
  const record = {uid: "abandoned-user", email: "synthetic@example.invalid", emailVerified: false,
    disabled: false, metadata: {creationTime: created, lastSignInTime: created},
    providerData: [{providerId: "password"}]} as UserRecord;
  mock.method(adminAuth, "listUsers", async () => ({users: [record]}));
  mock.method(adminAuth, "getUser", async () => record);
  const deletion = mock.method(adminAuth, "deleteUser", async () => { throw new Error("unexpected deletion"); });
  mock.method(db, "runTransaction", async () => { throw new Error("unexpected write"); });
  mock.method(UnverifiedRetentionStore.prototype, "getProfile", async () => ({version: null}));
  const query = {where: () => query, limit: () => query,
    get: async () => ({empty: true}), doc: () => ({get: async () => ({exists: false}), listCollections: async () => []})};
  mock.method(db, "collection", () => query as never);
  mock.method(db, "collectionGroup", () => query as never);
  mock.method(adminStorage, "bucket", () => ({getFiles: async () => [[]]}) as never);
  const result = await runUnverifiedAccountRetention("report");
  assert.equal(result.candidates, 1); assert.equal(result.completed, 0); assert.equal(result.scanComplete, true);
  assert.equal(deletion.mock.calls.length, 0);
});

test("read-only scan is bounded and can continue without writing a cursor", async () => {
  const tokens: (string | undefined)[] = [];
  const record = {uid: "verified", emailVerified: true, metadata: {}, providerData: []} as unknown as UserRecord;
  mock.method(db, "runTransaction", async () => { throw new Error("unexpected write"); });
  mock.method(adminAuth, "listUsers", async (_limit?: number, token?: string) => {
    tokens.push(token);
    return tokens.length <= 5 ? {users: Array.from({length: 100}, () => record), pageToken: `page-${tokens.length}`}
      : {users: []};
  });
  const first = await runUnverifiedAccountRetention("report", "preflight-start");
  assert.equal(first.scanned, 500); assert.equal(first.scanComplete, false);
  assert.equal(first.continuationToken, "page-5"); assert.equal(tokens[0], "preflight-start");
  const second = await runUnverifiedAccountRetention("report", first.continuationToken);
  assert.equal(second.scanComplete, true); assert.equal(tokens[5], "page-5");
});
