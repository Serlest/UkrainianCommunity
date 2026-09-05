"use strict";

// This is a scoped invocation of existing application code, never the exported cron/cycle.
const assert = require("node:assert/strict");
const {test, before, after} = require("node:test");
const {validateEnvironment} = require("./environment.cjs");
validateEnvironment(process.env);
assert.equal(process.env.UAC_SCHEDULER_MODE, "worker");
const registry = require("./registry.cjs");
let manifest = registry.attachWorker(); // durable PID binding, before Admin or network initialization
const boundary = require("./boundary.cjs");
const {db} = boundary;
const {Timestamp} = require("firebase-admin/firestore");
const {publishScheduledCandidate} = require("../../lib/content/scheduledPublishing.js");
const {cleanupOwned} = require("./cleanup.cjs");
const now = Timestamp.fromDate(new Date("2026-09-03T06:00:00Z"));
const due = Timestamp.fromMillis(now.toMillis() - 60_000);
const future = Timestamp.fromMillis(now.toMillis() + 60_000);
const sentinel = registry.target(manifest.runId, "sentinel");
let sentinelBefore;

function fixture(name) { return registry.target(manifest.runId, name); }
function contents(value, changes = {}) {
  return {id: value.id, title: `Scoped scheduler ${value.name}`, body: "Synthetic local scheduler fixture.",
    authorId: value.uid, organizationId: value.orgId, organizationName: "Synthetic scheduler organization",
    sourceType: "organization", sourceURL: `https://example.invalid/${manifest.runId}/${value.name}`,
    regionScope: "state", federalState: "wien", moderationStatus: "draft", scheduledAt: due,
    createdAt: due, updatedAt: due, publishedAt: due,
    startDate: Timestamp.fromMillis(now.toMillis() + 86_400_000 + registry.cases.indexOf(value.name) * 60_000),
    likeCount: 0, commentCount: 0, registrationCount: 0, ...changes};
}
async function seed(name, options = {}) {
  const value = fixture(name);
  const batch = db.batch();
  batch.create(db.doc(value.user), {uid: value.uid, globalRole: "user", accountStatus: "active", blockState: "active", ...options.user});
  if (!options.missingOrganization) batch.create(db.doc(value.organization), {
    id: value.orgId, ownerId: value.uid, adminIds: [], moderatorIds: [], moderationStatus: "approved", ...options.organization,
  });
  batch.create(db.doc(value.content), contents(value, options.content));
  await batch.commit();
  return value;
}
async function data(value) { const snapshot = await db.doc(value.content).get(); assert.ok(snapshot.exists); return snapshot.data(); }
async function noLease(value) { assert.equal((await db.doc(value.lease).get()).exists, false); }
async function outcome(value, expected, dependencies) {
  assert.equal(await publishScheduledCandidate(value.collection, value.id, now, dependencies), expected);
  const current = await data(value);
  assert.equal(current.moderationStatus, expected);
  assert.equal(Object.hasOwn(current, "scheduledAt"), false);
  assert.ok(current.updatedAt.isEqual(now));
  if (value.collection === "news" && expected === "approved") assert.ok(current.publishedAt.isEqual(now));
  await noLease(value);
  return current;
}
async function withClaimPause(value, during, expected = "skipped") {
  let signalClaim;
  let release;
  const claimed = new Promise(resolve => { signalClaim = resolve; });
  const resumed = new Promise(resolve => { release = resolve; });
  const operation = publishScheduledCandidate(value.collection, value.id, now, {
    planningDraftLookup: async () => { signalClaim(); await resumed; return undefined; },
  });
  // Observe an early worker error rather than hanging a latch until the runner deadline.
  let failure;
  try { await Promise.race([claimed, operation.then(() => { throw new Error("Expected a claimed candidate."); })]); await during(); }
  catch (error) { failure = error; }
  finally { release(); }
  // Always drain the real operation before a failed test can enter fixture cleanup.
  let result;
  try { result = await operation; }
  catch (error) { throw failure ? new AggregateError([failure, error], "Claim pause and worker both failed.") : error; }
  if (failure) throw failure;
  assert.equal(result, expected);
}

before(async () => {
  // All targets must be absent before activation. A pre-existing collision is never cleanup-owned.
  for (const snapshot of await db.getAll(...manifest.paths.map(path => db.doc(path)))) assert.equal(snapshot.exists, false);
  manifest = registry.activateOwned(manifest);
  boundary.installRegistry(manifest);
  await seed("sentinel");
  sentinelBefore = await data(sentinel);
});
after(async () => {
  const failures = [];
  try {
    if (sentinelBefore) assert.deepEqual(await data(sentinel), sentinelBefore);
    assert.equal(boundary.snapshot().blockedAttempts, 0);
    assert.equal(boundary.snapshot().cronCalls, 0);
    assert.equal(boundary.snapshot().schedulesRegistered, 1);
  } catch (error) { failures.push(error); }
  try { await cleanupOwned(db, manifest); } catch (error) { failures.push(error); }
  try { await db.terminate(); } catch (error) { failures.push(error); }
  if (failures.length) throw new AggregateError(failures, "Scoped scheduler final verification failed; inspect retained manifest if present.");
});

test("future target stays byte-for-byte draft and takes no lease", async () => {
  const value = await seed("future", {content: {scheduledAt: future}});
  const original = await data(value);
  assert.equal(await publishScheduledCandidate(value.collection, value.id, now), "skipped");
  assert.deepEqual(await data(value), original); await noLease(value);
});
test("due News uses real lookup, publishes once, exact timestamps and repeat skips", async () => {
  const value = await seed("news");
  const receipt = await outcome(value, "approved");
  assert.equal(await publishScheduledCandidate(value.collection, value.id, now), "skipped");
  assert.deepEqual(await data(value), receipt); await noLease(value);
});
test("due Event publishes with independent start and retained published time", async () => {
  const value = await seed("event"); const original = await data(value);
  const receipt = await outcome(value, "approved");
  assert.ok(receipt.startDate.isEqual(original.startDate)); assert.ok(receipt.publishedAt.isEqual(original.publishedAt));
});
test("ordinary Austria News becomes review, not public approval", async () => {
  await outcome(await seed("austria", {content: {regionScope: "austria"}}), "pendingReview");
});
for (const [name, role] of [["admin", "adminIds"], ["moderator", "moderatorIds"]]) {
  test(`fresh organization ${name} membership may publish`, async () => {
    const value = fixture(name);
    await outcome(await seed(name, {organization: {ownerId: "different-synthetic-owner", [role]: [value.uid]}}), "approved");
  });
}
for (const [name, options] of [
  ["role-lost", {organization: {ownerId: "different-synthetic-owner"}}],
  ["restricted", {user: {accountStatus: "bannedPermanent"}}],
  ["missing-org", {missingOrganization: true}],
  ["unapproved-org", {organization: {moderationStatus: "pendingReview"}}],
]) {
  test(`${name} routes to review with scheduler lease removed`, async () => {
    await outcome(await seed(name, options), "pendingReview");
  });
}
test("exact News source duplicate becomes review and duplicate is untouched", async () => {
  const value = await seed("duplicate-news");
  await db.doc(value.duplicate).create(contents(value, {id: value.duplicateId, moderationStatus: "approved"}));
  const original = (await db.doc(value.duplicate).get()).data();
  await outcome(value, "pendingReview");
  assert.deepEqual((await db.doc(value.duplicate).get()).data(), original);
});
test("Event normalized-title/start/organization duplicate becomes review", async () => {
  const value = await seed("duplicate-event");
  await db.doc(value.duplicate).create(contents(value, {id: value.duplicateId, title: `  SCOPED   SCHEDULER ${value.name.toUpperCase()} `, moderationStatus: "approved"}));
  const original = (await db.doc(value.duplicate).get()).data();
  await outcome(value, "pendingReview");
  assert.deepEqual((await db.doc(value.duplicate).get()).data(), original);
});
test("two real workers compete for one due target: one approval, one skip", async () => {
  const value = await seed("concurrent");
  const completed = await Promise.allSettled([publishScheduledCandidate(value.collection, value.id, now), publishScheduledCandidate(value.collection, value.id, now)]);
  const failures = completed.filter(item => item.status === "rejected").map(item => item.reason);
  if (failures.length) throw new AggregateError(failures, "Concurrent workers drained before cleanup.");
  const results = completed.map(item => item.value);
  assert.deepEqual(results.sort(), ["approved", "skipped"]);
  const receipt = await data(value); assert.equal(receipt.moderationStatus, "approved");
  assert.equal(Object.hasOwn(receipt, "scheduledAt"), false); await noLease(value);
});
test("another live lease prevents publication and is preserved", async () => {
  const value = await seed("active-lease"); const original = await data(value);
  const lease = {leaseId: "synthetic-live", expiresAt: future, documentId: value.id, collection: value.collection};
  await db.doc(value.lease).create(lease);
  assert.equal(await publishScheduledCandidate(value.collection, value.id, now), "skipped");
  assert.deepEqual(await data(value), original); assert.deepEqual((await db.doc(value.lease).get()).data(), lease);
});
test("expired lease is taken over for this target only", async () => {
  const value = await seed("expired-lease");
  await db.doc(value.lease).create({leaseId: "synthetic-expired", expiresAt: due});
  await outcome(value, "approved");
});
test("schedule changed after claim stays draft and owned lease is released", async () => {
  const value = await seed("changed-date");
  await withClaimPause(value, () => db.doc(value.content).update({scheduledAt: future}));
  const receipt = await data(value); assert.equal(receipt.moderationStatus, "draft"); assert.ok(receipt.scheduledAt.isEqual(future)); await noLease(value);
});
test("role revoked after claim is re-read and cannot approve", async () => {
  const value = await seed("changed-role");
  await withClaimPause(value, () => db.doc(value.organization).update({ownerId: "different-synthetic-owner"}), "pendingReview");
  assert.equal((await data(value)).moderationStatus, "pendingReview"); await noLease(value);
});
test("lookup exception releases own lease without changing the draft", async () => {
  const value = await seed("lookup-error"); const original = await data(value);
  await assert.rejects(publishScheduledCandidate(value.collection, value.id, now, {planningDraftLookup: async () => { throw new Error("scoped-lookup-failure"); }}), /scoped-lookup-failure/);
  assert.deepEqual(await data(value), original); await noLease(value);
});
test("replaced lease is not removed by the previous claimant", async () => {
  const value = await seed("replaced-lease"); const original = await data(value);
  await withClaimPause(value, () => db.doc(value.lease).update({leaseId: "replacement", expiresAt: future}));
  assert.deepEqual(await data(value), original);
  const lease = await db.doc(value.lease).get(); assert.equal(lease.get("leaseId"), "replacement"); assert.ok(lease.get("expiresAt").isEqual(future));
});
test("candidate deleted after claim is not recreated", async () => {
  const value = await seed("deleted-candidate");
  await withClaimPause(value, () => db.doc(value.content).delete());
  assert.equal((await db.doc(value.content).get()).exists, false); await noLease(value);
});
