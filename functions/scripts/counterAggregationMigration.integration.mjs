import assert from "node:assert/strict";
import {mkdtemp, readFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {spawnSync} from "node:child_process";
import test from "node:test";

import {initializeApp} from "firebase-admin/app";
import {Timestamp, getFirestore} from "firebase-admin/firestore";

const projectId = "demo-ukrainian-community-counter-migration";
const cutoverAt = "2026-08-24T10:00:00.123456789Z";
const app = initializeApp({projectId}, `counter-migration-test-${Date.now()}`);
const db = getFirestore(app);

test("bounded bootstrap and reconcile modes preserve lifetime views", async () => {
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "counter-migration-test-"));
  try {
    await seedFixture();

    const orphanStateID = "a".repeat(64);
    await db.collection("counterAggregationSourceStates").doc(orphanStateID).set({
      schemaVersion: 2,
      sourcePathHash: orphanStateID,
      targetCollection: "news",
      targetDocumentId: "news-1",
      counterField: "viewCount",
      isActive: true,
      lastEventId: "orphan-before-bootstrap",
      lastEventTime: new Timestamp(1_777_000_000, 123_456_000),
      lastEventTimeSeconds: 1_777_000_000,
      lastEventTimeNanoseconds: 123_456_789,
      counterContributionApplied: true,
      counterManagedAtomically: false,
    });
    const orphanStateGate = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      `--checkpoint-file=${join(temporaryDirectory, "orphan-state-checkpoint.json")}`,
      "--page-size=1",
    ]);
    assert.equal(orphanStateGate.status, 2, orphanStateGate.stderr);
    assert.equal(
      JSON.parse(orphanStateGate.stdout).preflight.issueCounts
        .byCode["orphan-transition-state-before-bootstrap"],
      1
    );
    await db.collection("counterAggregationSourceStates").doc(orphanStateID).delete();

    const dryRun = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      `--checkpoint-file=${join(temporaryDirectory, "dry-checkpoint.json")}`,
      "--page-size=1",
    ]);
    assert.equal(dryRun.status, 2, dryRun.stderr);
    const dryReport = JSON.parse(dryRun.stdout);
    assert.equal(dryReport.releaseGate.passed, false);
    assert.ok(dryReport.preflight.issueCounts.byCode["state-create"] >= 2);
    assert.equal(dryReport.preflight.issueCounts.byCode["baseline-create"], 1);
    const resumedDryRun = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      `--checkpoint-file=${join(temporaryDirectory, "dry-checkpoint.json")}`,
      "--page-size=1",
      "--resume",
    ]);
    assert.equal(resumedDryRun.status, 2, resumedDryRun.stderr);
    const resumedReport = JSON.parse(resumedDryRun.stdout);
    assert.equal(resumedReport.preflight.issueCounts.byCode["state-create"], 2);
    assert.equal(resumedReport.preflight.issueCounts.byCode["baseline-create"], 1);

    const boundedTargetFailure = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      `--checkpoint-file=${join(temporaryDirectory, "bounded-target-checkpoint.json")}`,
      "--page-size=1",
      "--max-targets=2",
    ]);
    assert.equal(boundedTargetFailure.status, 2, boundedTargetFailure.stderr);
    assert.ok(JSON.parse(boundedTargetFailure.stdout)
      .preflight.issueCounts.byCode["public-target-cardinality-limit"] >= 1);

    const reportPath = join(temporaryDirectory, "apply-report.json");
    const apply = runScript([
      `--project=${projectId}`,
      `--confirm-project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      `--checkpoint-file=${join(temporaryDirectory, "apply-checkpoint.json")}`,
      `--report-file=${reportPath}`,
      "--page-size=1",
      "--maintenance=confirmed",
      "--operator=integration-test",
      "--ticket=TEST-1",
      "--apply",
    ]);
    assert.equal(apply.status, 0, `${apply.stderr}\n${apply.stdout}`);
    const applyReport = JSON.parse(await readFile(reportPath, "utf8"));
    assert.equal(applyReport.releaseGate.passed, true);
    assert.match(applyReport.reportDigestSha256, /^[a-f0-9]{64}$/);

    const news = await db.collection("news").doc("news-1").get();
    assert.equal(news.get("viewCount"), 5);
    assert.equal(news.get("likeCount"), 1);
    const states = await db.collection("counterAggregationSourceStates").get();
    assert.equal(states.size, 2);
    assert.ok(states.docs.every((document) =>
      document.get("counterContributionApplied") === true
    ));
    assert.ok(states.docs.every((document) =>
      document.get("lastEventTimeNanoseconds") === 123_456_789
    ));
    const baselines = await db.collection("counterAggregationBaselines").get();
    assert.equal(baselines.size, 1);
    assert.equal(baselines.docs[0].get("legacyCount"), 4);
    assert.equal(baselines.docs[0].get("activeMarkerCountAtCutover"), 1);
    assert.equal(baselines.docs[0].get("cutoverTimeNanoseconds"), 123_456_789);

    const disabledReconcile = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      "--mode=reconcile",
      `--checkpoint-file=${join(temporaryDirectory, "disabled-reconcile.json")}`,
      "--page-size=1",
    ]);
    assert.equal(disabledReconcile.status, 2, disabledReconcile.stderr);
    assert.equal(
      JSON.parse(disabledReconcile.stdout).preflight.issueCounts
        .byCode["aggregation-not-enabled"],
      1
    );
    assert.equal(
      JSON.parse(disabledReconcile.stdout).preflight.summary.sourcePages,
      0
    );
    await db.doc("appRuntimeConfig/counterAggregation").update({enabled: true});
    const resumedDisabledReconcile = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      "--mode=reconcile",
      `--checkpoint-file=${join(temporaryDirectory, "disabled-reconcile.json")}`,
      "--page-size=1",
      "--resume",
    ]);
    assert.equal(resumedDisabledReconcile.status, 0, [
      resumedDisabledReconcile.stderr,
      resumedDisabledReconcile.stdout,
    ].join("\n"));
    assert.ok(
      JSON.parse(resumedDisabledReconcile.stdout).preflight.summary.sourcePages > 0
    );

    await db.collection("counterAggregationDeadLetters").doc("resolved-evidence").set({
      resolutionStatus: "resolved",
      resolvedAt: Timestamp.now(),
      resolvedBy: "integration-test",
      resolutionReason: "authoritative source reconciled",
      resolutionTicket: "TEST-RESOLVED-1",
    });
    const reconcile = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      "--mode=reconcile",
      `--checkpoint-file=${join(temporaryDirectory, "reconcile-checkpoint.json")}`,
      "--page-size=1",
    ]);
    assert.equal(reconcile.status, 0, `${reconcile.stderr}\n${reconcile.stdout}`);
    const reconcileReport = JSON.parse(reconcile.stdout);
    assert.equal(reconcileReport.releaseGate.passed, true);
    assert.equal(reconcileReport.preflight.summary.resolvedDeadLetters, 1);

    await db.collection("counterAggregationDeadLetters")
      .doc("resolved-evidence")
      .update({resolutionStatus: "unresolved"});
    const unresolved = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      "--mode=reconcile",
      `--checkpoint-file=${join(temporaryDirectory, "unresolved-checkpoint.json")}`,
      "--page-size=1",
    ]);
    assert.equal(unresolved.status, 2, unresolved.stderr);
    assert.equal(
      JSON.parse(unresolved.stdout).preflight.issueCounts
        .byCode["unresolved-dead-letter"],
      1
    );
    await db.collection("counterAggregationDeadLetters")
      .doc("resolved-evidence")
      .delete();

    const likeState = states.docs.find((document) =>
      document.get("counterField") === "likeCount"
    );
    assert.ok(likeState);
    await likeState.ref.update({
      isActive: false,
      counterContributionApplied: false,
    });
    await Promise.all([
      db.collection("likes").doc("news-1_user-1").delete(),
      db.doc("users/user-1/newsViews/news-1").delete(),
      db.collection("news").doc("news-1").delete(),
    ]);
    const retiredTarget = runScript([
      `--project=${projectId}`,
      `--cutover-at=${cutoverAt}`,
      "--mode=reconcile",
      `--checkpoint-file=${join(temporaryDirectory, "retired-target-checkpoint.json")}`,
      "--page-size=1",
    ]);
    assert.equal(retiredTarget.status, 0, retiredTarget.stderr);
    const retiredReport = JSON.parse(retiredTarget.stdout);
    assert.equal(retiredReport.releaseGate.passed, true);
    assert.equal(retiredReport.preflight.summary.retiredViewTargets, 1);
    assert.equal(
      retiredReport.preflight.summary.retiredViewStateContributions,
      1
    );
  } finally {
    await rm(temporaryDirectory, {recursive: true, force: true});
  }
});

async function seedFixture() {
  await db.doc("appRuntimeConfig/counterAggregation").set({enabled: false});
  await db.collection("news").doc("news-1").set({
    id: "news-1",
    moderationStatus: "approved",
    createdAt: Timestamp.fromDate(new Date("2026-01-01T00:00:00Z")),
    likeCount: 1,
    commentCount: 0,
    viewCount: 5,
  });
  await db.collection("likes").doc("news-1_user-1").set({
    id: "news-1_user-1",
    userId: "user-1",
    newsId: "news-1",
    createdAt: Timestamp.fromDate(new Date("2026-08-01T00:00:00Z")),
  });
  await db.doc("users/user-1/newsViews/news-1").set({
    id: "news-1",
    userId: "user-1",
    newsId: "news-1",
    createdAt: Timestamp.fromDate(new Date("2026-08-01T00:00:00Z")),
  });
}

function runScript(argumentsList) {
  return spawnSync(
    process.execPath,
    ["scripts/reconcileCounterAggregation.mjs", ...argumentsList],
    {
      cwd: process.cwd(),
      encoding: "utf8",
      env: process.env,
      timeout: 60_000,
    }
  );
}
