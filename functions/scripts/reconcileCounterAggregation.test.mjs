import assert from "node:assert/strict";
import {mkdtemp, mkdir, rm, stat, symlink, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {
  assertDistinctEvidencePaths,
  checkpointFingerprint,
  counterConfigurationChanged,
  counterConfigurationIssueCode,
  parseArguments,
  recordCheckpointedConfigurationIssue,
  runConfigurationGatedAudit,
} from "./reconcileCounterAggregation.mjs";

const required = [
  "--project=demo-project",
  "--cutover-at=2026-08-24T10:00:00.123456789Z",
  "--checkpoint-file=/tmp/counter-checkpoint.json",
];

test("counter reconciliation is dry-run by default", () => {
  const options = parseArguments(required);
  assert.equal(options.apply, false);
  assert.equal(options.mode, "bootstrap");
  assert.equal(options.pageSize, 250);
  assert.equal(options.maximumTargets, 100_000);
});

test("configuration gate rejects disabled and mid-run flipped reconcile", () => {
  assert.equal(
    counterConfigurationIssueCode("bootstrap", false),
    undefined
  );
  assert.equal(
    counterConfigurationIssueCode("bootstrap", true),
    "aggregation-not-disabled"
  );
  assert.equal(counterConfigurationIssueCode("reconcile", true), undefined);
  assert.equal(
    counterConfigurationIssueCode("reconcile", false),
    "aggregation-not-enabled"
  );

  const startIssue = counterConfigurationIssueCode("reconcile", true);
  const endIssue = counterConfigurationIssueCode("reconcile", false);
  assert.equal(startIssue, undefined);
  assert.equal(endIssue, "aggregation-not-enabled");
  assert.equal(counterConfigurationChanged(
    {exists: true, enabled: true, revision: "10:1"},
    {exists: true, enabled: true, revision: "12:3"}
  ), true);
  assert.equal(counterConfigurationChanged(
    {exists: true, enabled: true, revision: "12:3"},
    {exists: true, enabled: true, revision: "12:3"}
  ), false);
});

test("configuration failures persist before an audit scan can start", async () => {
  const persisted = [];
  const checkpoint = {
    async completeAuditPhase(phase, audit) {
      persisted.push({phase, issueCounts: structuredClone(audit.issueCounts)});
    },
  };
  let auditStarted = false;
  const audit = await runConfigurationGatedAudit(
    checkpoint,
    "preflight",
    "aggregation-not-enabled",
    {message: "disabled at start"},
    async () => {
      auditStarted = true;
      throw new Error("audit must not start");
    }
  );
  assert.equal(auditStarted, false);

  await recordCheckpointedConfigurationIssue(
    checkpoint,
    "preflight",
    audit,
    "aggregation-not-enabled",
    {message: "disabled before completion"}
  );

  assert.deepEqual(persisted, [
    {
      phase: "preflight",
      issueCounts: {
        fatal: 1,
        actionable: 0,
        byCode: {"aggregation-not-enabled": 1},
      },
    },
    {
      phase: "preflight",
      issueCounts: {
        fatal: 2,
        actionable: 0,
        byCode: {"aggregation-not-enabled": 2},
      },
    },
  ]);
});

test("apply requires exact project, maintenance, attribution, and report gates", () => {
  assert.throws(
    () => parseArguments([...required, "--apply"]),
    /confirm-project/
  );
  assert.throws(
    () => parseArguments([
      ...required,
      "--apply",
      "--confirm-project=demo-project",
    ]),
    /maintenance/
  );
  const options = parseArguments([
    ...required,
    "--apply",
    "--confirm-project=demo-project",
    "--maintenance=confirmed",
    "--operator=release-owner",
    "--ticket=CHANGE-1",
    "--report-file=/tmp/counter-report.json",
  ]);
  assert.equal(options.apply, true);
  assert.equal(options.maintenanceProof, "confirmed");
  assert.notEqual(
    checkpointFingerprint(options),
    checkpointFingerprint({...options, operator: "another-operator"})
  );
  assert.notEqual(
    checkpointFingerprint(options),
    checkpointFingerprint({...options, ticket: "CHANGE-2"})
  );
  assert.throws(() => parseArguments([
    ...required,
    "--apply",
    "--confirm-project=demo-project",
    "--two-watermark=confirmed",
    "--operator=release-owner",
    "--ticket=CHANGE-1",
    "--report-file=/tmp/counter-report.json",
  ]), /unavailable/);
});

test("report and checkpoint paths must remain distinct through symlinks", async () => {
  const directory = await mkdtemp(join(tmpdir(), "counter-path-test-"));
  const actual = join(directory, "actual");
  const alias = join(directory, "alias");
  try {
    await mkdir(actual);
    await symlink(actual, alias);
    assert.throws(() => parseArguments([
      "--project=demo-project",
      "--confirm-project=demo-project",
      "--cutover-at=2026-08-24T10:00:00.123456789Z",
      `--checkpoint-file=${join(actual, "evidence.json")}`,
      `--report-file=${join(alias, "evidence.json")}`,
      "--maintenance=confirmed",
      "--operator=release-owner",
      "--ticket=CHANGE-1",
      "--apply",
    ]), /must be different paths/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("existing case aliases cannot share report and checkpoint evidence", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "counter-case-path-test-"));
  const checkpointFile = join(directory, "Evidence.json");
  const reportFile = join(directory, "evidence.json");
  try {
    await writeFile(checkpointFile, "checkpoint", "utf8");
    let caseInsensitive = true;
    try {
      await stat(reportFile);
    } catch (error) {
      if (error?.code !== "ENOENT") {
        throw error;
      }
      caseInsensitive = false;
    }
    if (!caseInsensitive) {
      t.skip("filesystem is case-sensitive");
      return;
    }
    assert.throws(
      () => assertDistinctEvidencePaths({checkpointFile, reportFile}),
      /must be different paths/
    );
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("pagination, cardinality, mode, and RFC3339 inputs are bounded", () => {
  assert.throws(
    () => parseArguments([...required, "--page-size=501"]),
    /1 through 500/
  );
  assert.throws(
    () => parseArguments([...required, "--max-targets=1000001"]),
    /1 through 1000000/
  );
  assert.throws(
    () => parseArguments([...required, "--mode=repair-everything"]),
    /bootstrap or reconcile/
  );
  assert.throws(
    () => parseArguments([
      "--project=demo-project",
      "--cutover-at=2026-02-30T10:00:00Z",
      "--checkpoint-file=/tmp/counter-checkpoint.json",
    ]),
    /valid calendar/
  );
  assert.throws(
    () => parseArguments([
      "--project=demo-project",
      "--cutover-at=2999-01-01T00:00:00Z",
      "--checkpoint-file=/tmp/counter-checkpoint.json",
    ]),
    /future/
  );
});
