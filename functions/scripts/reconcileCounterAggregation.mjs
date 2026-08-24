import {createHash} from "node:crypto";
import {realpathSync, statSync} from "node:fs";
import {readFile, rename, unlink, writeFile} from "node:fs/promises";
import {basename, dirname, join, resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {
  assertCounterCutoverNotFuture,
  boundedChunks,
  classifyCounterBackfillState,
  classifyCounterBaseline,
  classifyCounterDeadLetter,
  compareTimestampParts,
  counterMigrationBaselineID,
  counterMigrationSourceDescriptor,
  counterMigrationSourceStateID,
  counterTargetFields,
  counterTargetFromKey,
  counterTargetKey,
  incrementCounterTargetCount,
  lifetimeViewBaselinePlan,
  normalizedMigrationCounter,
  parseRfc3339TimestampParts,
  stableReportEnvelope,
  timestampParts,
} from "./counterAggregationMigrationCore.mjs";

const checkpointSchemaVersion = 3;
const reportSchemaVersion = 2;
const stateCollection = "counterAggregationSourceStates";
const baselineCollection = "counterAggregationBaselines";
const deadLetterCollection = "counterAggregationDeadLetters";
const configPath = "appRuntimeConfig/counterAggregation";
const maximumIssueSamples = 200;
const stateReadBatchSize = 100;
const writeConcurrency = 10;

const sourceScans = Object.freeze([
  {id: "likes", scope: "collection", collection: "likes"},
  {id: "registrations", scope: "collection", collection: "registrations"},
  {id: "comments", scope: "collectionGroup", collection: "comments"},
  {id: "newsViews", scope: "collectionGroup", collection: "newsViews"},
  {id: "eventViews", scope: "collectionGroup", collection: "eventViews"},
]);

const targetScans = Object.freeze([
  {id: "target-news", collection: "news"},
  {id: "target-events", collection: "events"},
  {id: "target-organizations", collection: "organizations"},
]);

if (isMainModule()) {
  run().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}

async function run() {
  const options = parseArguments(process.argv.slice(2));
  const cutoverParts = parseRfc3339TimestampParts(options.cutoverAt);
  const [appModule, firestoreModule] = await Promise.all([
    import("firebase-admin/app"),
    import("firebase-admin/firestore"),
  ]);
  const {applicationDefault, initializeApp} = appModule;
  const {
    FieldPath,
    FieldValue,
    Timestamp,
    getFirestore,
  } = firestoreModule;
  const checkpoint = await CheckpointStore.open(options);
  // Recheck after checkpoint creation so case-insensitive filesystems resolve
  // differently-cased aliases to the same existing inode.
  assertDistinctEvidencePaths(options);
  const cutover = new Timestamp(cutoverParts.seconds, cutoverParts.nanoseconds);
  const app = initializeApp({
    credential: applicationDefault(),
    projectId: options.projectId,
  }, `counter-aggregation-${Date.now()}`);
  const db = getFirestore(app);
  const runtime = {db, FieldPath, FieldValue, Timestamp, cutover, cutoverParts};

  const configuration = await loadCounterConfiguration(db);
  await checkpoint?.bindAuditConfiguration(
    "preflight",
    configuration.revision,
    !options.apply
  );
  const configurationIssueCode = counterConfigurationIssueCode(
    options.mode,
    configuration.enabled
  );

  const preflight = await runConfigurationGatedAudit(
    checkpoint,
    "preflight",
    configurationIssueCode,
    {
      message: configurationIssueCode === undefined ?
        "" : counterConfigurationIssueMessage(configurationIssueCode),
    },
    () => runAudit(runtime, options, checkpoint, "preflight")
  );

  let verification;
  let applySummary;
  if (options.apply && preflight.issueCounts.fatal === 0) {
    applySummary = await applyPlan(runtime, options, checkpoint, preflight);
    verification = await runAudit(runtime, options, undefined, "verification");
  }

  let postConfiguration = configuration;
  if (configurationIssueCode === undefined) {
    postConfiguration = await loadCounterConfiguration(db);
    const postIssueCode = counterConfigurationIssueCode(
      options.mode,
      postConfiguration.enabled
    );
    const effectivePostIssueCode = postIssueCode ?? (
      counterConfigurationChanged(configuration, postConfiguration) ?
        "aggregation-configuration-changed" : undefined
    );
    if (effectivePostIssueCode !== undefined) {
      const postAudit = verification ?? preflight;
      await recordCheckpointedConfigurationIssue(
        verification === undefined ? checkpoint : undefined,
        verification === undefined ? "preflight" : "verification",
        postAudit,
        effectivePostIssueCode,
        {message: counterConfigurationIssueMessage(effectivePostIssueCode)}
      );
    }
  }

  const effectiveAudit = verification ?? preflight;
  const reportPayload = {
    schemaVersion: reportSchemaVersion,
    projectId: options.projectId,
    mode: options.mode,
    execution: options.apply ? "apply" : "dry-run",
    cutoverAt: options.cutoverAt,
    migrationGeneration: options.generation,
    generatedAt: new Date().toISOString(),
    operator: options.operator ?? null,
    changeTicket: options.ticket ?? null,
    maintenanceProof: options.maintenanceProof ?? "not-confirmed-dry-run",
    configuration: {
      enabled: configuration.enabled ?? null,
      exists: configuration.exists,
      revision: configuration.revision,
      endEnabled: postConfiguration.enabled ?? null,
      endRevision: postConfiguration.revision,
    },
    pageSize: options.pageSize,
    maximumTargets: options.maximumTargets,
    preflight: auditReport(preflight),
    ...(applySummary === undefined ? {} : {applySummary}),
    ...(verification === undefined ? {} : {verification: auditReport(verification)}),
    releaseGate: {
      passed: isAuditClean(effectiveAudit),
      requirements: [
        "No fatal or actionable mismatch remains.",
        "No unresolved counterAggregationDeadLetters document remains.",
        "Bootstrap was run with aggregation disabled during confirmed maintenance.",
        "The report digest, operator, change ticket, cutover and exact deployed commit are retained together.",
        "After enablement, reconcile mode is clean daily for seven consecutive days.",
      ],
    },
  };
  const report = stableReportEnvelope(reportPayload);
  const reportJSON = `${JSON.stringify(report, null, 2)}\n`;
  if (options.reportFile !== undefined) {
    await atomicWrite(options.reportFile, reportJSON);
  }
  console.log(reportJSON);

  if (isAuditClean(effectiveAudit)) {
    await checkpoint?.remove();
  } else {
    process.exitCode = 2;
  }
}

async function runAudit(runtime, options, checkpoint, phase) {
  let restored = checkpoint?.auditForPhase(phase);
  if (restored !== undefined && checkpoint?.isAuditPhaseComplete(phase)) {
    if (options.apply) {
      return hydrateAudit(restored);
    }
    await checkpoint.resetAuditPhase(phase);
    restored = undefined;
  }
  const audit = restored === undefined ? emptyAudit() : hydrateAudit(restored);

  for (const definition of sourceScans) {
    await scanPages(
      runtime,
      options,
      checkpoint,
      phase,
      definition,
      async (documents) => auditSourcePage(runtime, options, audit, documents),
      false,
      audit
    );
  }

  await scanPages(
    runtime,
    options,
    checkpoint,
    phase,
    {id: "transition-states", scope: "collection", collection: stateCollection},
    async (documents) => auditTransitionStatePage(runtime, options, audit, documents),
    false,
    audit
  );

  if (options.mode === "bootstrap" &&
    audit.summary.transitionStates !== audit.summary.liveSourceStatesFound) {
    recordIssue(audit, "fatal", "orphan-transition-state-before-bootstrap", {
      transitionStates: audit.summary.transitionStates,
      liveSourceStatesFound: audit.summary.liveSourceStatesFound,
    });
  }

  for (const definition of targetScans) {
    await scanPages(
      runtime,
      options,
      checkpoint,
      phase,
      {...definition, scope: "collection"},
      async (documents) => auditTargetPage(runtime, options, audit, documents),
      false,
      audit
    );
  }

  await scanPages(
    runtime,
    options,
    checkpoint,
    phase,
    {id: "dead-letters", scope: "collection", collection: deadLetterCollection},
    async (documents) => auditDeadLetterPage(runtime, audit, documents),
    false,
    audit
  );

  finalizeAudit(options, audit);
  await checkpoint?.completeAuditPhase(phase, audit);
  return audit;
}

async function auditSourcePage(runtime, options, audit, documents) {
  const descriptors = [];
  for (const document of documents) {
    let source;
    try {
      source = counterMigrationSourceDescriptor(document.ref.path, document.data());
    } catch (error) {
      recordIssue(audit, "fatal", "invalid-source", {
        sourcePathHash: opaquePathHash(document.ref.path),
        reason: errorMessage(error),
      });
      continue;
    }
    if (source === undefined) {
      continue;
    }
    try {
      incrementCounterTargetCount(
        audit.sourceCounts,
        source.target,
        options.maximumTargets
      );
    } catch (error) {
      recordIssue(audit, "fatal", "target-cardinality-limit", {
        reason: errorMessage(error),
      });
      continue;
    }
    audit.summary.activeSources += 1;
    incrementDimension(audit.summary.activeSourcesByDimension, source.target);
    descriptors.push(source);
  }

  const stateSnapshots = new Map();
  for (const chunk of boundedChunks(descriptors, stateReadBatchSize)) {
    const references = chunk.map((source) => runtime.db
      .collection(stateCollection)
      .doc(counterMigrationSourceStateID(source.sourcePath)));
    const snapshots = await runtime.db.getAll(...references);
    snapshots.forEach((snapshot) => stateSnapshots.set(snapshot.id, snapshot));
  }

  for (const source of descriptors) {
    const sourcePathHash = counterMigrationSourceStateID(source.sourcePath);
    const snapshot = stateSnapshots.get(sourcePathHash);
    if (snapshot?.exists) {
      audit.summary.liveSourceStatesFound += 1;
    }
    const desired = desiredStateData(
      source,
      sourcePathHash,
      options,
      runtime.cutover,
      runtime.cutoverParts
    );
    if (options.mode === "bootstrap") {
      const storedData = snapshot?.data();
      const classification = storedData !== undefined &&
        !(storedData.lastEventTime instanceof runtime.Timestamp) ?
        {kind: "conflict", reason: "malformed-state-time"} :
        classifyCounterBackfillState(
          storedData,
          desired,
          runtime.cutoverParts
        );
      audit.summary.stateStatus[classification.kind] =
        (audit.summary.stateStatus[classification.kind] ?? 0) + 1;
      if (classification.kind === "create" || classification.kind === "replace-older") {
        recordIssue(audit, "actionable", `state-${classification.kind}`, {
          sourcePathHash,
        });
      } else if (classification.kind === "conflict") {
        recordIssue(audit, "fatal", "state-conflict", {
          sourcePathHash,
          reason: classification.reason,
        });
      }
      continue;
    }

    const liveStateIssue = liveSourceStateIssue(
      snapshot?.data(),
      source,
      sourcePathHash,
      runtime.Timestamp
    );
    if (liveStateIssue !== undefined) {
      recordIssue(audit, "fatal", liveStateIssue, {sourcePathHash});
    }
  }
  audit.summary.sourcePages += 1;
}

function auditTransitionStatePage(runtime, options, audit, documents) {
  audit.summary.transitionStates += documents.length;
  for (const document of documents) {
    const data = document.data();
    const issue = transitionStateIssue(data, document.id, runtime.Timestamp);
    if (issue !== undefined) {
      recordIssue(audit, "fatal", issue, {sourcePathHash: document.id});
      continue;
    }
    if (data.counterContributionApplied !== true) {
      if (data.isActive === true) {
        recordIssue(audit, "fatal", "active-source-missing-contribution", {
          sourcePathHash: document.id,
          target: safeTargetLabel(data),
        });
      }
      continue;
    }
    const target = {
      collection: data.targetCollection,
      documentId: data.targetDocumentId,
      field: data.counterField,
    };
    try {
      incrementCounterTargetCount(
        audit.stateContributionCounts,
        target,
        options.maximumTargets
      );
      incrementDimension(audit.summary.stateContributionsByDimension, target);
    } catch (error) {
      recordIssue(audit, "fatal", "state-target-cardinality-limit", {
        reason: errorMessage(error),
      });
    }
  }
  audit.summary.statePages += 1;
}

async function auditTargetPage(runtime, options, audit, documents) {
  const viewDocuments = documents.filter((document) =>
    document.ref.parent.id === "news" || document.ref.parent.id === "events"
  );
  const baselineSnapshots = new Map();
  for (const chunk of boundedChunks(viewDocuments, stateReadBatchSize)) {
    const references = chunk.map((document) => runtime.db
      .collection(baselineCollection)
      .doc(counterMigrationBaselineID(
        document.ref.parent.id,
        document.id,
        "viewCount"
      )));
    const snapshots = await runtime.db.getAll(...references);
    snapshots.forEach((snapshot) => baselineSnapshots.set(snapshot.id, snapshot));
  }

  for (const document of documents) {
    const collection = document.ref.parent.id;
    const data = document.data();
    for (const field of counterTargetFields[collection]) {
      const key = counterTargetKey(collection, document.id, field);
      if (!audit.seenTargetKeys.has(key) &&
        audit.seenTargetKeys.size >= options.maximumTargets) {
        recordIssue(audit, "fatal", "public-target-cardinality-limit", {
          maximumTargets: options.maximumTargets,
        });
        continue;
      }
      audit.seenTargetKeys.add(key);
      const sourceCount = audit.sourceCounts.get(key) ?? 0;
      const stateContributionCount = audit.stateContributionCounts.get(key) ?? 0;
      let currentCount;
      try {
        currentCount = normalizedMigrationCounter(data[field]);
      } catch (error) {
        recordIssue(audit, "fatal", "invalid-public-counter", {
          target: targetLabel(collection, document.id, field),
          reason: errorMessage(error),
        });
        continue;
      }

      let expectedCount = sourceCount;
      if (field === "viewCount") {
        const baselineID = counterMigrationBaselineID(collection, document.id, field);
        const baselineSnapshot = baselineSnapshots.get(baselineID);
        if (options.mode === "bootstrap") {
          let plan;
          try {
            plan = lifetimeViewBaselinePlan(currentCount, sourceCount);
          } catch (error) {
            recordIssue(audit, "fatal", "invalid-view-baseline", {
              target: targetLabel(collection, document.id, field),
              reason: errorMessage(error),
            });
            continue;
          }
          const desired = desiredBaselineData(
            collection,
            document.id,
            plan,
            options,
            runtime.cutover,
            runtime.cutoverParts
          );
          const storedBaseline = baselineSnapshot?.data();
          const classification = storedBaseline !== undefined &&
            !(storedBaseline.cutoverAt instanceof runtime.Timestamp) ?
            {kind: "conflict", reason: "malformed-baseline-cutover"} :
            classifyCounterBaseline(storedBaseline, desired);
          if (classification.kind === "create") {
            audit.baselineActionKeys.add(key);
            recordIssue(audit, "actionable", "baseline-create", {
              target: targetLabel(collection, document.id, field),
            });
          } else if (classification.kind === "conflict") {
            recordIssue(audit, "fatal", "baseline-conflict", {
              target: targetLabel(collection, document.id, field),
              reason: classification.reason,
            });
          }
          expectedCount = currentCount;
        } else {
          const result = reconcileViewExpectation(
            data,
            baselineSnapshot?.data(),
            collection,
            document.id,
            stateContributionCount,
            options,
            runtime
          );
          if (result.issue !== undefined) {
            recordIssue(audit, result.issue.severity, result.issue.code, result.issue.details);
            if (result.issue.code === "post-cutover-baseline-create") {
              audit.baselineActionKeys.add(key);
            }
          }
          if (result.expectedCount === undefined) {
            continue;
          }
          expectedCount = result.expectedCount;
        }
      } else if (options.mode === "reconcile" &&
        sourceCount !== stateContributionCount) {
        recordIssue(audit, "fatal", "live-source-state-count-mismatch", {
          target: targetLabel(collection, document.id, field),
          liveSourceCount: sourceCount,
          stateContributionCount,
        });
      }

      audit.expectedTargetCounts.set(key, expectedCount);
      if (currentCount !== expectedCount) {
        audit.targetMismatchKeys.add(key);
        recordIssue(audit, "actionable", "public-counter-mismatch", {
          target: targetLabel(collection, document.id, field),
          actual: currentCount,
          expected: expectedCount,
        });
      }
    }
  }
  audit.summary.targetPages += 1;
}

function auditDeadLetterPage(runtime, audit, documents) {
  for (const document of documents) {
    const data = document.data();
    const classification = data.resolutionStatus === "resolved" &&
      !(data.resolvedAt instanceof runtime.Timestamp) ?
      {kind: "invalid", reason: "incomplete-resolution-evidence"} :
      classifyCounterDeadLetter(data);
    audit.summary.deadLetters += 1;
    if (classification.kind === "resolved") {
      audit.summary.resolvedDeadLetters += 1;
      continue;
    }
    audit.summary.unresolvedDeadLetters += 1;
    recordIssue(
      audit,
      "fatal",
      classification.kind === "invalid" ?
        "invalid-dead-letter-resolution" :
        "unresolved-dead-letter",
      {
        deadLetterId: document.id,
        ...(classification.reason === undefined ? {} : {
          reason: classification.reason,
        }),
      }
    );
  }
  audit.summary.deadLetterPages += 1;
}

function reconcileViewExpectation(
  targetData,
  baselineData,
  collection,
  documentId,
  stateContributionCount,
  options,
  runtime
) {
  const target = targetLabel(collection, documentId, "viewCount");
  if (baselineData === undefined) {
    const createdAt = timestampParts(targetData.createdAt);
    if (createdAt !== undefined &&
      compareTimestampParts(createdAt, runtime.cutoverParts) > 0) {
      return {
        expectedCount: stateContributionCount,
        issue: {
          severity: "actionable",
          code: "post-cutover-baseline-create",
          details: {target},
        },
      };
    }
    return {
      issue: {
        severity: "fatal",
        code: "missing-view-baseline",
        details: {target},
      },
    };
  }
  if (!(baselineData.cutoverAt instanceof runtime.Timestamp)) {
    return {
      issue: {
        severity: "fatal",
        code: "invalid-view-baseline",
        details: {target, reason: "malformed-baseline-cutover"},
      },
    };
  }
  let legacyCount;
  let sourceViewCountAtCutover;
  let activeMarkerCountAtCutover;
  try {
    legacyCount = normalizedMigrationCounter(baselineData.legacyCount);
    sourceViewCountAtCutover = normalizedMigrationCounter(
      baselineData.sourceViewCountAtCutover
    );
    activeMarkerCountAtCutover = normalizedMigrationCounter(
      baselineData.activeMarkerCountAtCutover
    );
  } catch (error) {
    return {
      issue: {
        severity: "fatal",
        code: "invalid-view-baseline",
        details: {target, reason: errorMessage(error)},
      },
    };
  }
  const desired = {
    schemaVersion: 2,
    targetCollection: collection,
    targetDocumentId: documentId,
    counterField: "viewCount",
    legacyCount,
    sourceViewCountAtCutover,
    activeMarkerCountAtCutover,
    migrationGeneration: options.generation,
    cutoverAt: runtime.cutover,
    cutoverTimeSeconds: runtime.cutoverParts.seconds,
    cutoverTimeNanoseconds: runtime.cutoverParts.nanoseconds,
  };
  const classification = classifyCounterBaseline(baselineData, desired);
  if (classification.kind !== "verified" ||
    sourceViewCountAtCutover - activeMarkerCountAtCutover !== legacyCount ||
    !Number.isSafeInteger(legacyCount + stateContributionCount)) {
    return {
      issue: {
        severity: "fatal",
        code: "invalid-view-baseline",
        details: {target, reason: classification.reason ?? "invalid-count-identity"},
      },
    };
  }
  return {expectedCount: legacyCount + stateContributionCount};
}

function finalizeAudit(options, audit) {
  const contributionKeys = options.mode === "reconcile" ?
    new Set([...audit.sourceCounts.keys(), ...audit.stateContributionCounts.keys()]) :
    new Set(audit.sourceCounts.keys());
  for (const key of contributionKeys) {
    if (audit.seenTargetKeys.has(key)) {
      continue;
    }
    const target = counterTargetFromKey(key);
    const liveSourceCount = audit.sourceCounts.get(key) ?? 0;
    const stateContributionCount = audit.stateContributionCounts.get(key) ?? 0;
    if (options.mode === "reconcile" &&
      target.field === "viewCount" &&
      liveSourceCount === 0 &&
      stateContributionCount > 0) {
      audit.summary.retiredViewTargets += 1;
      audit.summary.retiredViewStateContributions += stateContributionCount;
      continue;
    }
    recordIssue(audit, "fatal", "missing-counter-target", {
      target: targetLabel(target.collection, target.documentId, target.field),
      liveSourceCount,
      stateContributionCount,
    });
  }
}

async function applyPlan(runtime, options, checkpoint, preflight) {
  if (options.mode === "bootstrap") {
    await ensureAggregationDisabled(runtime.db);
    for (const definition of sourceScans) {
      await scanPages(
        runtime,
        options,
        checkpoint,
        "apply-states",
        definition,
        async (documents) => applyStatePage(runtime, options, documents),
        true
      );
    }
  }

  for (const definition of targetScans) {
    await scanPages(
      runtime,
      options,
      checkpoint,
      "apply-baselines",
      {...definition, scope: "collection"},
      async (documents) => applyBaselinePage(runtime, options, preflight, documents),
      true
    );
  }

  const mismatchTargets = [...preflight.targetMismatchKeys].map(counterTargetFromKey);
  await mapWithConcurrency(mismatchTargets, writeConcurrency, async (target) => {
    await repairTargetCounter(runtime, options, preflight, target);
  });
  await checkpoint?.markApplyCountersComplete();
  if (options.mode === "bootstrap") {
    await ensureAggregationDisabled(runtime.db);
  }
  return {
    stateScansCompleted: checkpoint?.completedCount("apply-states") ?? undefined,
    baselineScansCompleted: checkpoint?.completedCount("apply-baselines") ?? undefined,
    counterRepairsRequested: mismatchTargets.length,
  };
}

async function applyStatePage(runtime, options, documents) {
  const sources = documents.flatMap((document) => {
    const source = counterMigrationSourceDescriptor(document.ref.path, document.data());
    return source === undefined ? [] : [source];
  });
  await mapWithConcurrency(sources, writeConcurrency, async (source) => {
    const sourcePathHash = counterMigrationSourceStateID(source.sourcePath);
    const stateReference = runtime.db.collection(stateCollection).doc(sourcePathHash);
    const targetReference = runtime.db
      .collection(source.target.collection)
      .doc(source.target.documentId);
    const configReference = runtime.db.doc(configPath);
    const desired = desiredStateData(
      source,
      sourcePathHash,
      options,
      runtime.cutover,
      runtime.cutoverParts
    );
    await runtime.db.runTransaction(async (transaction) => {
      const [configSnapshot, stateSnapshot, targetSnapshot] = await Promise.all([
        transaction.get(configReference),
        transaction.get(stateReference),
        transaction.get(targetReference),
      ]);
      if (configSnapshot.data()?.enabled !== false) {
        throw new Error("Counter aggregation became enabled during state backfill.");
      }
      if (!targetSnapshot.exists) {
        throw new Error(`Counter target disappeared: ${safeTargetLabel(desired)}`);
      }
      const classification = classifyCounterBackfillState(
        stateSnapshot.data(),
        desired,
        runtime.cutoverParts
      );
      if (classification.kind === "conflict") {
        throw new Error(`State conflict for ${sourcePathHash}: ${classification.reason}`);
      }
      if (classification.kind === "verified") {
        return;
      }
      transaction.set(stateReference, {
        ...desired,
        migratedAt: runtime.FieldValue.serverTimestamp(),
        updatedAt: runtime.FieldValue.serverTimestamp(),
        ...(stateSnapshot.exists ? {} : {
          createdAt: runtime.FieldValue.serverTimestamp(),
        }),
      });
    });
  });
}

async function applyBaselinePage(runtime, options, preflight, documents) {
  const candidates = documents.filter((document) =>
    document.ref.parent.id === "news" || document.ref.parent.id === "events"
  );
  await mapWithConcurrency(candidates, writeConcurrency, async (document) => {
    const collection = document.ref.parent.id;
    const key = counterTargetKey(collection, document.id, "viewCount");
    if (!preflight.baselineActionKeys.has(key)) {
      return;
    }
    const baselineReference = runtime.db.collection(baselineCollection).doc(
      counterMigrationBaselineID(collection, document.id, "viewCount")
    );
    const configReference = runtime.db.doc(configPath);
    await runtime.db.runTransaction(async (transaction) => {
      const [configSnapshot, targetSnapshot, baselineSnapshot] = await Promise.all([
        transaction.get(configReference),
        transaction.get(document.ref),
        transaction.get(baselineReference),
      ]);
      if (options.mode === "bootstrap" && configSnapshot.data()?.enabled !== false) {
        throw new Error("Counter aggregation became enabled during baseline capture.");
      }
      if (!targetSnapshot.exists) {
        throw new Error(`View target disappeared: ${collection}/${document.id}`);
      }
      let plan;
      if (options.mode === "bootstrap") {
        const current = normalizedMigrationCounter(targetSnapshot.get("viewCount"));
        plan = lifetimeViewBaselinePlan(
          current,
          preflight.sourceCounts.get(key) ?? 0
        );
      } else {
        const createdAt = timestampParts(targetSnapshot.get("createdAt"));
        if (createdAt === undefined ||
          compareTimestampParts(createdAt, runtime.cutoverParts) <= 0) {
          throw new Error(`Cannot prove post-cutover target: ${collection}/${document.id}`);
        }
        plan = {sourceViewCount: 0, activeMarkerCount: 0, legacyCount: 0};
      }
      const desired = desiredBaselineData(
        collection,
        document.id,
        plan,
        options,
        runtime.cutover,
        runtime.cutoverParts
      );
      const classification = classifyCounterBaseline(
        baselineSnapshot.data(),
        desired
      );
      if (classification.kind === "conflict") {
        throw new Error(`Baseline conflict: ${collection}/${document.id}`);
      }
      if (classification.kind === "verified") {
        return;
      }
      transaction.create(baselineReference, {
        ...desired,
        createdAt: runtime.FieldValue.serverTimestamp(),
        createdBy: options.operator,
        changeTicket: options.ticket,
      });
    });
  });
}

async function repairTargetCounter(runtime, options, preflight, target) {
  const key = counterTargetKey(target.collection, target.documentId, target.field);
  const expected = preflight.expectedTargetCounts.get(key);
  if (expected === undefined) {
    throw new Error(`Missing expected counter for ${targetLabel(
      target.collection,
      target.documentId,
      target.field
    )}`);
  }
  const targetReference = runtime.db.collection(target.collection).doc(target.documentId);
  const configReference = runtime.db.doc(configPath);
  await runtime.db.runTransaction(async (transaction) => {
    const [configSnapshot, targetSnapshot] = await Promise.all([
      transaction.get(configReference),
      transaction.get(targetReference),
    ]);
    if (options.mode === "bootstrap" && configSnapshot.data()?.enabled !== false) {
      throw new Error("Counter aggregation became enabled during counter repair.");
    }
    if (!targetSnapshot.exists) {
      throw new Error(`Counter target disappeared: ${target.collection}/${target.documentId}`);
    }
    const current = normalizedMigrationCounter(targetSnapshot.get(target.field));
    if (current !== expected) {
      transaction.update(targetReference, {[target.field]: expected});
    }
  });
}

async function scanPages(
  runtime,
  options,
  checkpoint,
  phase,
  definition,
  processPage,
  applyPhase = false,
  auditForCheckpoint = undefined
) {
  const scanKey = `${phase}:${definition.id}`;
  if (checkpoint?.isScanComplete(scanKey)) {
    return;
  }
  let cursor = checkpoint?.cursor(scanKey);
  let pagesSinceCheckpoint = 0;
  while (true) {
    let query = definition.scope === "collectionGroup" ?
      runtime.db.collectionGroup(definition.collection) :
      runtime.db.collection(definition.collection);
    query = query.orderBy(runtime.FieldPath.documentId()).limit(options.pageSize);
    if (cursor !== undefined) {
      query = query.startAfter(cursor);
    }
    const snapshot = await query.get();
    if (snapshot.empty) {
      if (!applyPhase) {
        checkpoint?.setAudit(phase, auditForCheckpoint);
      }
      await checkpoint?.completeScan(scanKey);
      return;
    }
    await processPage(snapshot.docs);
    const lastDocument = snapshot.docs.at(-1);
    cursor = definition.scope === "collectionGroup" ?
      lastDocument.ref.path :
      lastDocument.id;
    pagesSinceCheckpoint += 1;
    const complete = snapshot.size < options.pageSize;
    if (checkpoint !== undefined &&
      (complete || pagesSinceCheckpoint >= options.checkpointPageInterval)) {
      checkpoint.setCursor(scanKey, cursor);
      if (!applyPhase) {
        checkpoint.setAudit(phase, auditForCheckpoint);
      }
      await checkpoint.save();
      pagesSinceCheckpoint = 0;
    }
    if (complete) {
      if (!applyPhase) {
        checkpoint?.setAudit(phase, auditForCheckpoint);
      }
      await checkpoint?.completeScan(scanKey);
      return;
    }
  }
}

function desiredStateData(source, sourcePathHash, options, cutover, cutoverParts) {
  return {
    schemaVersion: 2,
    sourcePathHash,
    targetCollection: source.target.collection,
    targetDocumentId: source.target.documentId,
    counterField: source.target.field,
    isActive: true,
    lastEventId: options.generation,
    lastEventTime: cutover,
    lastEventTimeSeconds: cutoverParts.seconds,
    lastEventTimeNanoseconds: cutoverParts.nanoseconds,
    counterContributionApplied: true,
    counterManagedAtomically: source.counterManagedAtomically,
    migrationGeneration: options.generation,
  };
}

function desiredBaselineData(
  collection,
  documentId,
  plan,
  options,
  cutover,
  cutoverParts
) {
  return {
    schemaVersion: 2,
    targetCollection: collection,
    targetDocumentId: documentId,
    counterField: "viewCount",
    legacyCount: plan.legacyCount,
    sourceViewCountAtCutover: plan.sourceViewCount,
    activeMarkerCountAtCutover: plan.activeMarkerCount,
    migrationGeneration: options.generation,
    cutoverAt: cutover,
    cutoverTimeSeconds: cutoverParts.seconds,
    cutoverTimeNanoseconds: cutoverParts.nanoseconds,
  };
}

function liveSourceStateIssue(data, source, sourcePathHash, TimestampClass) {
  if (transitionStateIssue(data, sourcePathHash, TimestampClass) !== undefined) {
    return "missing-or-malformed-live-source-state";
  }
  if (data.targetCollection !== source.target.collection ||
    data.targetDocumentId !== source.target.documentId ||
    data.counterField !== source.target.field) {
    return "live-source-state-target-mismatch";
  }
  if (data.isActive !== true) {
    return "live-source-state-inactive";
  }
  if (data.counterContributionApplied !== true) {
    return "live-source-state-not-contributing";
  }
  return undefined;
}

function transitionStateIssue(data, documentId, TimestampClass) {
  if (data === undefined || data.schemaVersion !== 2 ||
    data.sourcePathHash !== documentId ||
    typeof data.lastEventId !== "string" || data.lastEventId.length === 0 ||
    timestampParts({
      seconds: data.lastEventTimeSeconds,
      nanoseconds: data.lastEventTimeNanoseconds,
    }) === undefined ||
    !(data.lastEventTime instanceof TimestampClass) ||
    typeof data.isActive !== "boolean" ||
    typeof data.counterContributionApplied !== "boolean" ||
    typeof data.counterManagedAtomically !== "boolean") {
    return "malformed-transition-state";
  }
  try {
    counterTargetKey(
      data.targetCollection,
      data.targetDocumentId,
      data.counterField
    );
  } catch {
    return "malformed-transition-state-target";
  }
  if (data.counterContributionApplied === true && data.isActive !== true) {
    return "inactive-state-has-contribution";
  }
  return undefined;
}

function emptyAudit() {
  return {
    sourceCounts: new Map(),
    stateContributionCounts: new Map(),
    expectedTargetCounts: new Map(),
    seenTargetKeys: new Set(),
    targetMismatchKeys: new Set(),
    baselineActionKeys: new Set(),
    issueCounts: {fatal: 0, actionable: 0, byCode: {}},
    issues: [],
    summary: {
      activeSources: 0,
      activeSourcesByDimension: {},
      stateContributionsByDimension: {},
      sourcePages: 0,
      statePages: 0,
      transitionStates: 0,
      liveSourceStatesFound: 0,
      targetPages: 0,
      deadLetterPages: 0,
      deadLetters: 0,
      resolvedDeadLetters: 0,
      stateStatus: {},
      unresolvedDeadLetters: 0,
      retiredViewTargets: 0,
      retiredViewStateContributions: 0,
    },
  };
}

function recordIssue(audit, severity, code, details) {
  audit.issueCounts[severity] += 1;
  audit.issueCounts.byCode[code] = (audit.issueCounts.byCode[code] ?? 0) + 1;
  if (audit.issues.length < maximumIssueSamples) {
    audit.issues.push({severity, code, ...details});
  }
}

async function recordCheckpointedConfigurationIssue(
  checkpoint,
  phase,
  audit,
  code,
  details
) {
  recordIssue(audit, "fatal", code, details);
  await checkpoint?.completeAuditPhase(phase, audit);
}

async function runConfigurationGatedAudit(
  checkpoint,
  phase,
  issueCode,
  issueDetails,
  auditOperation
) {
  if (issueCode === undefined) {
    return auditOperation();
  }
  const audit = emptyAudit();
  await recordCheckpointedConfigurationIssue(
    checkpoint,
    phase,
    audit,
    issueCode,
    issueDetails
  );
  return audit;
}

function auditReport(audit) {
  return {
    clean: isAuditClean(audit),
    issueCounts: audit.issueCounts,
    issueSamples: audit.issues,
    summary: {
      ...audit.summary,
      distinctLiveTargets: audit.sourceCounts.size,
      distinctContributingStateTargets: audit.stateContributionCounts.size,
      publicCounterMismatches: audit.targetMismatchKeys.size,
      baselineActions: audit.baselineActionKeys.size,
    },
  };
}

function isAuditClean(audit) {
  return audit.issueCounts.fatal === 0 && audit.issueCounts.actionable === 0;
}

function serializeAudit(audit) {
  return {
    sourceCounts: [...audit.sourceCounts],
    stateContributionCounts: [...audit.stateContributionCounts],
    expectedTargetCounts: [...audit.expectedTargetCounts],
    seenTargetKeys: [...audit.seenTargetKeys],
    targetMismatchKeys: [...audit.targetMismatchKeys],
    baselineActionKeys: [...audit.baselineActionKeys],
    issueCounts: audit.issueCounts,
    issues: audit.issues,
    summary: audit.summary,
  };
}

function hydrateAudit(value) {
  return {
    sourceCounts: new Map(value.sourceCounts),
    stateContributionCounts: new Map(value.stateContributionCounts),
    expectedTargetCounts: new Map(value.expectedTargetCounts),
    seenTargetKeys: new Set(value.seenTargetKeys),
    targetMismatchKeys: new Set(value.targetMismatchKeys),
    baselineActionKeys: new Set(value.baselineActionKeys),
    issueCounts: value.issueCounts,
    issues: value.issues,
    summary: value.summary,
  };
}

class CheckpointStore {
  static async open(options) {
    if (options.checkpointFile === undefined) {
      return undefined;
    }
    const fingerprint = checkpointFingerprint(options);
    let existing;
    try {
      existing = JSON.parse(await readFile(options.checkpointFile, "utf8"));
    } catch (error) {
      if (error?.code !== "ENOENT") {
        throw error;
      }
    }
    if (existing !== undefined && !options.resume) {
      throw new Error("Checkpoint already exists; pass --resume or choose another file.");
    }
    if (existing !== undefined &&
      (existing.schemaVersion !== checkpointSchemaVersion ||
        existing.fingerprint !== fingerprint)) {
      throw new Error("Checkpoint does not match this project/mode/cutover/generation.");
    }
    const data = existing ?? {
      schemaVersion: checkpointSchemaVersion,
      fingerprint,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      cursors: {},
      completedScans: [],
      audits: {},
      completedAuditPhases: [],
      auditConfigurationRevisions: {},
      countersApplied: false,
    };
    const store = new CheckpointStore(options.checkpointFile, data);
    await store.save();
    return store;
  }

  constructor(file, data) {
    this.file = file;
    this.data = data;
  }

  cursor(key) {
    return this.data.cursors[key];
  }

  setCursor(key, value) {
    this.data.cursors[key] = value;
  }

  isScanComplete(key) {
    return this.data.completedScans.includes(key);
  }

  async completeScan(key) {
    if (!this.isScanComplete(key)) {
      this.data.completedScans.push(key);
    }
    delete this.data.cursors[key];
    await this.save();
  }

  setAudit(phase, audit) {
    if (audit !== undefined) {
      this.data.audits[phase] = serializeAudit(audit);
    }
  }

  auditForPhase(phase) {
    return this.data.audits[phase];
  }

  isAuditPhaseComplete(phase) {
    return (this.data.completedAuditPhases ?? []).includes(phase);
  }

  async completeAuditPhase(phase, audit) {
    this.setAudit(phase, audit);
    this.data.completedAuditPhases ??= [];
    if (!this.data.completedAuditPhases.includes(phase)) {
      this.data.completedAuditPhases.push(phase);
    }
    await this.save();
  }

  async resetAuditPhase(phase) {
    const prefix = `${phase}:`;
    this.data.completedScans = this.data.completedScans.filter(
      (key) => !key.startsWith(prefix)
    );
    for (const key of Object.keys(this.data.cursors)) {
      if (key.startsWith(prefix)) {
        delete this.data.cursors[key];
      }
    }
    delete this.data.audits[phase];
    this.data.completedAuditPhases = (
      this.data.completedAuditPhases ?? []
    ).filter((value) => value !== phase);
    await this.save();
  }

  async bindAuditConfiguration(phase, revision, allowReset) {
    this.data.auditConfigurationRevisions ??= {};
    const previous = this.data.auditConfigurationRevisions[phase];
    if (previous !== undefined && previous !== revision) {
      if (!allowReset) {
        throw new Error(
          "Counter configuration changed; apply resume requires a new checkpoint."
        );
      }
      await this.resetAuditPhase(phase);
    }
    this.data.auditConfigurationRevisions[phase] = revision;
    await this.save();
  }

  async markApplyCountersComplete() {
    this.data.countersApplied = true;
    await this.save();
  }

  completedCount(phase) {
    return this.data.completedScans.filter((key) => key.startsWith(`${phase}:`)).length;
  }

  async save() {
    this.data.updatedAt = new Date().toISOString();
    await atomicWrite(this.file, `${JSON.stringify(this.data)}\n`);
  }

  async remove() {
    try {
      await unlink(this.file);
    } catch (error) {
      if (error?.code !== "ENOENT") {
        throw error;
      }
    }
  }
}

async function loadCounterConfiguration(db) {
  const snapshot = await db.doc(configPath).get();
  const updateTime = timestampParts(snapshot.updateTime);
  if (snapshot.exists && updateTime === undefined) {
    throw new Error("Counter configuration has no valid Firestore update time.");
  }
  return {
    exists: snapshot.exists,
    enabled: snapshot.data()?.enabled,
    revision: updateTime === undefined ?
      "missing" : `${updateTime.seconds}:${updateTime.nanoseconds}`,
  };
}

async function ensureAggregationDisabled(db) {
  const configuration = await loadCounterConfiguration(db);
  if (configuration.enabled !== false) {
    throw new Error("Counter aggregation must remain explicitly disabled.");
  }
}

function parseArguments(argumentsList) {
  const options = {
    apply: false,
    mode: "bootstrap",
    generation: "counter-backfill-v1",
    pageSize: 250,
    maximumTargets: 100_000,
    checkpointPageInterval: 10,
    resume: false,
  };
  for (const argument of argumentsList) {
    if (argument === "--apply") {
      options.apply = true;
    } else if (argument === "--resume") {
      options.resume = true;
    } else if (argument.startsWith("--project=")) {
      options.projectId = optionValue(argument, "--project=");
    } else if (argument.startsWith("--confirm-project=")) {
      options.confirmProject = optionValue(argument, "--confirm-project=");
    } else if (argument.startsWith("--cutover-at=")) {
      options.cutoverAt = optionValue(argument, "--cutover-at=");
    } else if (argument.startsWith("--mode=")) {
      options.mode = optionValue(argument, "--mode=");
    } else if (argument.startsWith("--generation=")) {
      options.generation = optionValue(argument, "--generation=");
    } else if (argument.startsWith("--maintenance=")) {
      options.maintenanceProof = optionValue(argument, "--maintenance=");
    } else if (argument.startsWith("--two-watermark=")) {
      throw new Error(
        "--two-watermark is unavailable until executable replay tooling exists."
      );
    } else if (argument.startsWith("--operator=")) {
      options.operator = optionValue(argument, "--operator=");
    } else if (argument.startsWith("--ticket=")) {
      options.ticket = optionValue(argument, "--ticket=");
    } else if (argument.startsWith("--checkpoint-file=")) {
      options.checkpointFile = optionValue(argument, "--checkpoint-file=");
    } else if (argument.startsWith("--report-file=")) {
      options.reportFile = optionValue(argument, "--report-file=");
    } else if (argument.startsWith("--page-size=")) {
      options.pageSize = positiveIntegerOption(argument, "--page-size=", 500);
    } else if (argument.startsWith("--max-targets=")) {
      options.maximumTargets = positiveIntegerOption(
        argument,
        "--max-targets=",
        1_000_000
      );
    } else if (argument.startsWith("--checkpoint-pages=")) {
      options.checkpointPageInterval = positiveIntegerOption(
        argument,
        "--checkpoint-pages=",
        100
      );
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }
  if (!options.projectId || !options.cutoverAt || !options.checkpointFile) {
    throw new Error("--project, --cutover-at and --checkpoint-file are required.");
  }
  if (options.mode !== "bootstrap" && options.mode !== "reconcile") {
    throw new Error("--mode must be bootstrap or reconcile.");
  }
  assertDistinctEvidencePaths(options);
  parseRfc3339TimestampParts(options.cutoverAt);
  assertCounterCutoverNotFuture(
    parseRfc3339TimestampParts(options.cutoverAt)
  );
  if (options.apply) {
    if (options.confirmProject !== options.projectId) {
      throw new Error("--confirm-project must exactly match --project for apply mode.");
    }
    if (options.maintenanceProof !== "confirmed") {
      throw new Error("Apply requires --maintenance=confirmed.");
    }
    if (!options.operator || !options.ticket || !options.reportFile) {
      throw new Error("Apply requires --operator, --ticket and --report-file.");
    }
  }
  return options;
}

function checkpointFingerprint(options) {
  return createHash("sha256").update(JSON.stringify({
    projectId: options.projectId,
    mode: options.mode,
    cutoverAt: options.cutoverAt,
    generation: options.generation,
    pageSize: options.pageSize,
    maximumTargets: options.maximumTargets,
    apply: options.apply,
    ...(options.apply ? {
      maintenanceProof: options.maintenanceProof,
      operator: options.operator,
      ticket: options.ticket,
    } : {}),
  })).digest("hex");
}

function counterConfigurationIssueMessage(code) {
  if (code === "aggregation-not-disabled") {
    return "Bootstrap requires appRuntimeConfig/counterAggregation.enabled == false.";
  }
  if (code === "aggregation-not-enabled") {
    return "Reconcile release evidence requires counter aggregation to stay enabled.";
  }
  return "Counter configuration changed before verification completed.";
}

function counterConfigurationIssueCode(mode, enabled) {
  if (mode === "bootstrap") {
    return enabled === false ? undefined : "aggregation-not-disabled";
  }
  return enabled === true ? undefined : "aggregation-not-enabled";
}

function counterConfigurationChanged(start, end) {
  return start.exists !== end.exists ||
    start.enabled !== end.enabled ||
    start.revision !== end.revision;
}

function optionValue(argument, prefix) {
  const value = argument.slice(prefix.length).trim();
  if (value.length === 0) {
    throw new Error(`${prefix} requires a value.`);
  }
  return value;
}

function canonicalFilePath(filePath) {
  let candidate = resolve(filePath);
  const missingComponents = [];
  while (true) {
    try {
      return missingComponents.reduce(
        (path, component) => join(path, component),
        realpathSync(candidate)
      );
    } catch (error) {
      if (error?.code !== "ENOENT" && error?.code !== "ENOTDIR") {
        throw error;
      }
      const parent = dirname(candidate);
      if (parent === candidate) {
        return resolve(filePath);
      }
      missingComponents.unshift(basename(candidate));
      candidate = parent;
    }
  }
}

function assertDistinctEvidencePaths(options) {
  if (options.reportFile !== undefined &&
    pathsReferToSameFile(options.reportFile, options.checkpointFile)) {
    throw new Error("--report-file and --checkpoint-file must be different paths.");
  }
}

function pathsReferToSameFile(first, second) {
  if (canonicalFilePath(first) === canonicalFilePath(second)) {
    return true;
  }
  try {
    const firstStat = statSync(first);
    const secondStat = statSync(second);
    return firstStat.dev === secondStat.dev && firstStat.ino === secondStat.ino;
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "ENOTDIR") {
      return false;
    }
    throw error;
  }
}

function positiveIntegerOption(argument, prefix, maximum) {
  const value = Number(optionValue(argument, prefix));
  if (!Number.isSafeInteger(value) || value <= 0 || value > maximum) {
    throw new Error(`${prefix} must be an integer from 1 through ${maximum}.`);
  }
  return value;
}

function incrementDimension(dimensions, target) {
  const key = `${target.collection}.${target.field}`;
  dimensions[key] = (dimensions[key] ?? 0) + 1;
}

function targetLabel(collection, documentId, field) {
  return `${collection}/${documentId}#${field}`;
}

function safeTargetLabel(data) {
  return targetLabel(
    String(data.targetCollection ?? "invalid"),
    String(data.targetDocumentId ?? "invalid"),
    String(data.counterField ?? "invalid")
  );
}

function opaquePathHash(path) {
  return createHash("sha256").update(String(path), "utf8").digest("hex");
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

async function mapWithConcurrency(items, concurrency, operation) {
  for (let offset = 0; offset < items.length; offset += concurrency) {
    await Promise.all(items.slice(offset, offset + concurrency).map(operation));
  }
}

async function atomicWrite(path, contents) {
  const temporaryPath = `${path}.tmp-${process.pid}`;
  await writeFile(temporaryPath, contents, {encoding: "utf8", mode: 0o600});
  await rename(temporaryPath, path);
}

function isMainModule() {
  return process.argv[1] !== undefined &&
    import.meta.url === pathToFileURL(process.argv[1]).href;
}

export {
  assertDistinctEvidencePaths,
  checkpointFingerprint,
  counterConfigurationChanged,
  counterConfigurationIssueCode,
  parseArguments,
  recordCheckpointedConfigurationIssue,
  runConfigurationGatedAudit,
};
