import {createHash, randomUUID} from "node:crypto";
import {link, mkdir, unlink, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {
  applicationDefault,
  deleteApp,
  initializeApp,
} from "firebase-admin/app";
import {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} from "firebase-admin/firestore";

import {
  analyticsCutoverDayID,
  analyticsCutoverWindowDayIDs,
  analyticsDailyDeltasFromCumulative,
  analyticsSchemaArchiveCollection,
  analyticsSchemaStatePath,
  analyticsSchemaVersion,
  assertDeployedCommit,
  assertSafeAnalyticsCutoverGeneration,
  datedLegacySnapshotData,
  isDrainWindowSatisfied,
  isValidAnalyticsDetailCoverage,
  normalizedAnalyticsSchemaState,
  stableJSONString,
} from "./analyticsSchemaCutoverCore.mjs";

const rootSnapshots = Object.freeze([
  {id: "topContentToday", path: "analyticsTopContent/today"},
  {id: "regionStatsToday", path: "analyticsRegionStats/today"},
  {id: "userStatsToday", path: "analyticsUserStats/today"},
  {id: "topContentDated", collection: "analyticsTopContent"},
  {id: "regionStatsDated", collection: "analyticsRegionStats"},
  {id: "dailyStatsDated", collection: "analyticsDailyStats"},
]);

const legacyDetailSnapshots = Object.freeze([
  {
    id: "contentItems",
    sourcePath: "analyticsContentStats/today/items",
  },
  {
    id: "organizations",
    sourcePath: "analyticsOrganizationStats/today/organizations",
  },
]);

const fixedPeriodIDs = ["today", "seven_days", "thirty_days"];
const detailPeriodSourceCounts = Object.freeze({
  today: 1,
  seven_days: 7,
  thirty_days: 30,
});
const defaultPageSize = 200;
const defaultMinimumDrainSeconds = 600;
const maximumLegacyDetailDocuments = 25_000;
const maximumUserProfiles = 100_000;
const lifecycleBaselineDays = 30;
const lifecycleCaptureDays = lifecycleBaselineDays + 1;
const lifecycleBaselineCollection = "analyticsUserLifecycleBaselines";

if (isMainModule()) {
  runCLI().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}

async function runCLI() {
  const options = parseArguments(process.argv.slice(2));
  assertProductionFirestoreEndpoint();
  const app = initializeApp({
    credential: applicationDefault(),
    projectId: options.projectId,
  }, `analytics-schema-cutover-${Date.now()}`);
  try {
    const database = getFirestore(app);
    const now = new Date();
    let result;
    switch (options.phase) {
    case "prepare":
      result = await prepareAnalyticsSchemaCutover(database, {...options, now});
      break;
    case "finalize":
      result = await finalizeAnalyticsSchemaCutover(database, {...options, now});
      break;
    case "abort":
      result = await abortAnalyticsSchemaCutover(database, {...options, now});
      break;
    case "verify":
      result = await verifyAnalyticsSchemaCutover(database, {...options, now});
      break;
    default:
      throw new Error(`unsupported phase ${options.phase}`);
    }

    const report = {
      reportSchemaVersion: 1,
      projectId: options.projectId,
      phase: options.phase,
      execution: options.apply ? "apply" : "dry-run",
      generation: options.generation,
      operator: options.operator ?? null,
      changeTicket: options.ticket ?? null,
      firestoreEndpoint: "production",
      deployedAt: options.deployedAt ?? null,
      minimumDrainSeconds: options.minimumDrainSeconds,
      generatedAt: now.toISOString(),
      ...result,
    };
    const reportJSON = `${JSON.stringify(report, null, 2)}\n`;
    if (options.reportFile !== undefined) {
      await immutableAtomicWrite(options.reportFile, reportJSON);
    }
    console.log(reportJSON);

    if (options.phase === "verify" && !result.releaseGatePassed) {
      process.exitCode = 2;
    }
  } finally {
    await deleteApp(app);
  }
}

export async function prepareAnalyticsSchemaCutover(database, options) {
  assertMaintenanceConfirmed(options);
  const generation = assertSafeAnalyticsCutoverGeneration(options.generation);
  const cutoverDay = analyticsCutoverDayID(options.now);
  const stateReference = database.doc(analyticsSchemaStatePath);
  const stateSnapshot = await stateReference.get();
  const existingState = normalizedAnalyticsSchemaState(stateSnapshot.data());
  if (stateSnapshot.exists && existingState === undefined) {
    throw new Error("existing analytics schema state is malformed");
  }
  if (existingState !== undefined && existingState.status !== "aborted") {
    throw new Error(
      `analytics schema state is already ${existingState.status} for ${existingState.generation}`
    );
  }
  if (existingState?.generation === generation) {
    throw new Error("an aborted cutover generation cannot be reused");
  }

  const archiveReference = database
    .collection(analyticsSchemaArchiveCollection)
    .doc(generation);
  if ((await archiveReference.get()).exists) {
    throw new Error("cutover archive generation already exists and is immutable");
  }
  if (options.apply) {
    await archiveReference.create({
      schemaVersion: analyticsSchemaVersion,
      generation,
      cutoverDay,
      phase: "preparing",
      operator: options.operator,
      changeTicket: options.ticket,
      maintenanceProof: options.maintenance,
      preparedCaptureStartedAt: Timestamp.fromDate(options.now),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  const capture = await captureLegacyAnalytics(
    database,
    archiveReference,
    "prepare",
    cutoverDay,
    options
  );
  assertLegacyTodayRollover(capture, cutoverDay);

  if (options.apply) {
    await database.runTransaction(async (transaction) => {
      const latestSnapshot = await transaction.get(stateReference);
      const latestState = normalizedAnalyticsSchemaState(latestSnapshot.data());
      if (latestSnapshot.exists && latestState?.status !== "aborted") {
        throw new Error("non-aborted analytics schema state appeared during prepare");
      }
      if (latestState?.generation === generation) {
        throw new Error("an aborted cutover generation cannot be reused");
      }
      transaction.set(stateReference, {
        schemaVersion: analyticsSchemaVersion,
        status: "prepared",
        generation,
        cutoverDay,
        prepareDigest: capture.digest,
        prepareDetailDigest: capture.detailDigest,
        previousGeneration: latestState?.generation ?? null,
        operator: options.operator,
        changeTicket: options.ticket,
        maintenanceProof: options.maintenance,
        preparedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(archiveReference, {
        phase: "prepared",
        prepareDigest: capture.digest,
        prepareDetailDigest: capture.detailDigest,
        prepareSummary: capture.summary,
        preparedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  }

  return {
    cutoverDay,
    capture: capture.summary,
    captureDigestSha256: capture.digest,
    legacyDetailDigestSha256: capture.detailDigest,
    stateAfterPhase: options.apply ? "prepared" : "unchanged",
    releaseGatePassed: false,
    nextRequiredStep: options.apply ?
      "Deploy the exact v2 backend and rules commit while the gate is prepared." :
      "Run prepare with --apply and retained evidence before deploying v2.",
  };
}

export async function finalizeAnalyticsSchemaCutover(database, options) {
  assertMaintenanceConfirmed(options);
  const generation = assertSafeAnalyticsCutoverGeneration(options.generation);
  const deployedCommit = assertDeployedCommit(options.deployedCommit);
  const deployedAt = requiredDate(options.deployedAt, "deployed-at");
  const minimumDrainSeconds = options.minimumDrainSeconds ??
    defaultMinimumDrainSeconds;
  const stateReference = database.doc(analyticsSchemaStatePath);
  const stateSnapshot = await stateReference.get();
  const state = normalizedAnalyticsSchemaState(stateSnapshot.data());
  if (state?.generation !== generation || state.status !== "prepared") {
    throw new Error("matching prepared analytics schema state is required");
  }
  if (analyticsCutoverDayID(options.now) !== state.cutoverDay ||
    analyticsCutoverDayID(deployedAt) !== state.cutoverDay) {
    throw new Error(
      "prepare, backend deployment, and finalize must finish in one Vienna calendar day"
    );
  }
  const preparedAt = timestampDate(stateSnapshot.data()?.preparedAt);
  if (preparedAt === undefined ||
    deployedAt.getTime() < preparedAt.getTime() ||
    deployedAt.getTime() > options.now.getTime()) {
    throw new Error(
      "deployed-at must be at or after the server-recorded prepare time and not in the future"
    );
  }
  if (!isDrainWindowSatisfied(
    options.now,
    deployedAt,
    minimumDrainSeconds
  )) {
    throw new Error("legacy invocation drain window has not elapsed");
  }

  const archiveReference = database
    .collection(analyticsSchemaArchiveCollection)
    .doc(generation);
  const preflightCapture = await captureLegacyAnalytics(
    database,
    archiveReference,
    "final",
    state.cutoverDay,
    {...options, apply: false}
  );
  assertLegacyTodayRollover(preflightCapture, state.cutoverDay);
  assertQuiescentAnalyticsCutoverDay(preflightCapture, stateSnapshot.data());
  const preflightLifecycleBaselines = await buildUserLifecycleBaselinePlan(
    database,
    preflightCapture.userLifecycleDataByDay,
    deployedAt,
    {...options, apply: false}
  );
  const preflightLifecycleBaselineDigest = digestLifecycleBaselinePlan(
    preflightLifecycleBaselines
  );

  if (!options.apply) {
    return {
      cutoverDay: state.cutoverDay,
      deployedCommit,
      deployedAt: deployedAt.toISOString(),
      minimumDrainSeconds,
      capture: preflightCapture.summary,
      captureDigestSha256: preflightCapture.digest,
      legacyDetailDigestSha256: preflightCapture.detailDigest,
      lifecycleBaselineDigestSha256: preflightLifecycleBaselineDigest,
      finalizeAttemptID: null,
      stateAfterPhase: "prepared",
      releaseGatePassed: false,
      nextRequiredStep:
        "Run finalize with --apply only after the exact v2 deploy and drain window.",
    };
  }

  // Claim one server-recorded finalization attempt before writing any final
  // archive or baseline. A concurrent operator can no longer interleave
  // snapshots and produce an internally inconsistent evidence bundle.
  const finalizeAttemptID = randomUUID();
  await database.runTransaction(async (transaction) => {
    const latestSnapshot = await transaction.get(stateReference);
    const latestState = normalizedAnalyticsSchemaState(latestSnapshot.data());
    if (latestState?.status !== "prepared" ||
      latestState.generation !== generation ||
      latestState.cutoverDay !== state.cutoverDay) {
      throw new Error("analytics schema state changed before finalize claim");
    }
    transaction.set(stateReference, {
      status: "finalizing",
      finalizingAttemptID: finalizeAttemptID,
      finalizingBy: options.operator,
      finalizingTicket: options.ticket,
      finalizingAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(archiveReference, {
      phase: "finalizing",
      finalizingAttemptID: finalizeAttemptID,
      finalizingBy: options.operator,
      finalizingTicket: options.ticket,
      finalizingAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  const capture = await captureLegacyAnalytics(
    database,
    archiveReference,
    "final",
    state.cutoverDay,
    options
  );
  assertLegacyTodayRollover(capture, state.cutoverDay);
  assertQuiescentAnalyticsCutoverDay(capture, stateSnapshot.data());
  if (capture.digest !== preflightCapture.digest ||
    capture.detailDigest !== preflightCapture.detailDigest) {
    throw new Error(
      "legacy analytics changed after finalize claim; abort this generation"
    );
  }

  const lifecycleBaselines = await buildUserLifecycleBaselinePlan(
    database,
    capture.userLifecycleDataByDay,
    deployedAt,
    options
  );
  const lifecycleBaselineDigest = digestLifecycleBaselinePlan(lifecycleBaselines);
  if (lifecycleBaselineDigest !== preflightLifecycleBaselineDigest) {
    throw new Error(
      "lifecycle baseline changed after finalize claim; abort this generation"
    );
  }

  const baselineArchiveBatch = database.batch();
  for (const baseline of lifecycleBaselines) {
    baselineArchiveBatch.set(
      archiveReference.collection("finalLifecycleBaselines").doc(baseline.analyticsDay),
      {
        ...baseline,
        capturedAt: FieldValue.serverTimestamp(),
      }
    );
  }
  await baselineArchiveBatch.commit();

  const topContentToday = cutoverTopContentSnapshot(capture, state.cutoverDay);
  const regionStatsToday = cutoverRegionSnapshot(capture, state.cutoverDay);
  const topDatedReference = database
    .collection("analyticsTopContent")
    .doc(state.cutoverDay);
  const regionDatedReference = database
    .collection("analyticsRegionStats")
    .doc(state.cutoverDay);
  await database.runTransaction(async (transaction) => {
    const latestSnapshot = await transaction.get(stateReference);
    const latestState = normalizedAnalyticsSchemaState(latestSnapshot.data());
    if (latestState?.status !== "finalizing" ||
      latestState.generation !== generation ||
      latestState.cutoverDay !== state.cutoverDay ||
      latestSnapshot.data()?.finalizingAttemptID !== finalizeAttemptID) {
      throw new Error("analytics schema state changed during finalize");
    }

    transaction.set(topDatedReference, datedLegacySnapshotData(
      topContentToday,
      state.cutoverDay,
      generation,
      FieldValue.serverTimestamp()
    ));
    transaction.set(regionDatedReference, datedLegacySnapshotData(
      regionStatsToday,
      state.cutoverDay,
      generation,
      FieldValue.serverTimestamp()
    ));
    for (const periodID of fixedPeriodIDs) {
      // v1 user documents use different activity semantics. Removing the
      // fixed read models makes the UI honestly partial until v2 rebuilds
      // them; dated historical copies remain preserved in the archive.
      transaction.delete(database.collection("analyticsUserStats").doc(periodID));
    }
    for (const baseline of lifecycleBaselines) {
      transaction.set(
        database.collection(lifecycleBaselineCollection).doc(baseline.analyticsDay),
        {
          schemaVersion: analyticsSchemaVersion,
          analyticsDay: baseline.analyticsDay,
          newRegistrations: baseline.newRegistrations,
          deletedAccounts: baseline.deletedAccounts,
          sourceLegacyNewRegistrations: baseline.sourceLegacyNewRegistrations,
          sourceCurrentUserFallback: baseline.sourceCurrentUserFallback,
          sourceLegacyDeletedAccountsCumulative:
            baseline.sourceLegacyDeletedAccountsCumulative,
          sourceLegacyPreviousDeletedAccountsCumulative:
            baseline.sourceLegacyPreviousDeletedAccountsCumulative,
          coveredThrough: baseline.coveredThrough,
          cutoverGeneration: generation,
          expiresAt: Timestamp.fromDate(
            new Date(options.now.getTime() + 60 * 24 * 60 * 60 * 1_000)
          ),
          updatedAt: FieldValue.serverTimestamp(),
        }
      );
    }
    transaction.set(stateReference, {
      schemaVersion: analyticsSchemaVersion,
      status: "complete",
      generation,
      cutoverDay: state.cutoverDay,
      finalizingAttemptID: finalizeAttemptID,
      finalDigest: capture.digest,
      finalDetailDigest: capture.detailDigest,
      deployedCommit,
      deployedAt: Timestamp.fromDate(deployedAt),
      minimumDrainSeconds,
      lifecycleBaselineDigest,
      maintenanceProof: options.maintenance,
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(archiveReference, {
      phase: "finalized",
      finalizingAttemptID: finalizeAttemptID,
      finalDigest: capture.digest,
      finalDetailDigest: capture.detailDigest,
      finalSummary: capture.summary,
      deployedCommit,
      deployedAt: Timestamp.fromDate(deployedAt),
      minimumDrainSeconds,
      lifecycleBaselineDigest,
      maintenanceProof: options.maintenance,
      finalizedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });

  return {
    cutoverDay: state.cutoverDay,
    deployedCommit,
    deployedAt: deployedAt.toISOString(),
    minimumDrainSeconds,
    capture: capture.summary,
    captureDigestSha256: capture.digest,
    legacyDetailDigestSha256: capture.detailDigest,
    lifecycleBaselineDigestSha256: lifecycleBaselineDigest,
    finalizeAttemptID,
    stateAfterPhase: "complete",
    releaseGatePassed: false,
    nextRequiredStep:
      "Wait for v2 hourly materialization, then run verify until every read model is newer than completion.",
  };
}

export async function abortAnalyticsSchemaCutover(database, options) {
  const generation = assertSafeAnalyticsCutoverGeneration(options.generation);
  if (typeof options.reason !== "string" || options.reason.trim().length < 8 ||
    options.reason.trim().length > 500) {
    throw new Error("abort reason must contain 8-500 characters");
  }
  const stateReference = database.doc(analyticsSchemaStatePath);
  const archiveReference = database
    .collection(analyticsSchemaArchiveCollection)
    .doc(generation);
  const stateSnapshot = await stateReference.get();
  const state = normalizedAnalyticsSchemaState(stateSnapshot.data());
  if ((state?.status !== "prepared" && state?.status !== "finalizing") ||
    state.generation !== generation) {
    throw new Error(
      "matching prepared or finalizing analytics schema state is required to abort"
    );
  }

  if (options.apply) {
    await database.runTransaction(async (transaction) => {
      const latestSnapshot = await transaction.get(stateReference);
      const latestState = normalizedAnalyticsSchemaState(latestSnapshot.data());
      if ((latestState?.status !== "prepared" && latestState?.status !== "finalizing") ||
        latestState.generation !== generation) {
        throw new Error("analytics schema state changed during abort");
      }
      transaction.set(stateReference, {
        status: "aborted",
        abortReason: options.reason.trim(),
        abortedBy: options.operator,
        abortTicket: options.ticket,
        abortedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(archiveReference, {
        phase: "aborted",
        abortReason: options.reason.trim(),
        abortedBy: options.operator,
        abortTicket: options.ticket,
        abortedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
  }

  return {
    cutoverDay: state.cutoverDay,
    stateAfterPhase: options.apply ? "aborted" : state.status,
    releaseGatePassed: false,
    nextRequiredStep: options.apply ?
      "Analytics remains paused. Start a new prepare generation, or redeploy the recorded legacy rollback before resuming traffic." :
      "Run abort with --apply only when finalize cannot be repaired safely.",
  };
}

export async function verifyAnalyticsSchemaCutover(database, options) {
  const generation = assertSafeAnalyticsCutoverGeneration(options.generation);
  const stateSnapshot = await database.doc(analyticsSchemaStatePath).get();
  const stateData = stateSnapshot.data();
  const state = normalizedAnalyticsSchemaState(stateData);
  const issues = [];
  if (state?.status !== "complete" || state.generation !== generation) {
    issues.push("schema-state-not-complete");
  }
  const completedAt = timestampDate(stateData?.completedAt);
  if (completedAt === undefined) {
    issues.push("completion-timestamp-missing");
  }

  const archiveSnapshot = await database
    .collection(analyticsSchemaArchiveCollection)
    .doc(generation)
    .get();
  const archiveData = archiveSnapshot.data();
  if (!archiveSnapshot.exists ||
    typeof archiveData?.prepareDigest !== "string" ||
    typeof archiveData?.finalDigest !== "string") {
    issues.push("cutover-archive-incomplete");
  }
  const archivedPrepare = archiveSnapshot.exists ?
    await recomputeArchivedCapture(
      archiveSnapshot.ref,
      "prepare",
      state?.cutoverDay,
      options
    ) : undefined;
  const archivedFinal = archiveSnapshot.exists ?
    await recomputeArchivedCapture(
      archiveSnapshot.ref,
      "final",
      state?.cutoverDay,
      options
    ) : undefined;
  if (archivedPrepare?.digest !== archiveData?.prepareDigest ||
    archivedPrepare?.detailDigest !== archiveData?.prepareDetailDigest) {
    issues.push("prepare-archive-content-digest-mismatch");
  }
  if (archivedFinal?.digest !== archiveData?.finalDigest ||
    archivedFinal?.detailDigest !== archiveData?.finalDetailDigest) {
    issues.push("final-archive-content-digest-mismatch");
  }
  if (typeof stateData?.prepareDigest !== "string" ||
    stateData?.prepareDigest !== archiveData?.prepareDigest) {
    issues.push("prepare-digest-mismatch");
  }
  if (typeof stateData?.finalDigest !== "string" ||
    stateData?.finalDigest !== archiveData?.finalDigest) {
    issues.push("final-digest-mismatch");
  }
  if (typeof stateData?.prepareDetailDigest !== "string" ||
    stateData?.prepareDetailDigest !== archiveData?.prepareDetailDigest ||
    typeof stateData?.finalDetailDigest !== "string" ||
    stateData?.finalDetailDigest !== archiveData?.finalDetailDigest ||
    stateData?.prepareDetailDigest !== stateData?.finalDetailDigest) {
    issues.push("legacy-detail-digest-mismatch");
  }
  const lifecycleBaselineDigests = await recomputeLifecycleBaselineDigests(
    database,
    archiveSnapshot.ref,
    options
  );
  if (typeof stateData?.lifecycleBaselineDigest !== "string" ||
    stateData.lifecycleBaselineDigest !== archiveData?.lifecycleBaselineDigest ||
    stateData.lifecycleBaselineDigest !== lifecycleBaselineDigests.archiveDigest ||
    stateData.lifecycleBaselineDigest !== lifecycleBaselineDigests.liveDigest) {
    issues.push("lifecycle-baseline-digest-mismatch");
  }

  if (state !== undefined) {
    for (const collection of ["analyticsTopContent", "analyticsRegionStats"]) {
      const dated = await database.collection(collection).doc(state.cutoverDay).get();
      if (!dated.exists || dated.get("cutoverGeneration") !== generation) {
        issues.push(`${collection}-dated-cutover-snapshot-missing`);
      }
      for (const periodID of fixedPeriodIDs) {
        const snapshot = await database.collection(collection).doc(periodID).get();
        if (!isFreshAfter(snapshot.data()?.updatedAt, completedAt)) {
          issues.push(`${collection}-${periodID}-not-rematerialized`);
        }
      }
    }

    for (const periodID of fixedPeriodIDs) {
      const userSnapshot = await database
        .collection("analyticsUserStats")
        .doc(periodID)
        .get();
      const userData = userSnapshot.data();
      if (!isFreshAfter(userData?.generatedAt, completedAt)) {
        issues.push(`analyticsUserStats-${periodID}-not-rematerialized`);
      }
      if (!isValidAnalyticsDetailCoverage({
        periodId: userData?.period,
        sourceDocumentIDs: userData?.sourceDocumentIDs,
        coverageStartDay: userData?.lifecycleCoverageStartDay,
        coveredSourceDocumentIDs: userData?.coveredLifecycleSourceDocumentIDs,
        isPartialCoverage: userData?.isLifecyclePartialCoverage,
      }, periodID, detailPeriodSourceCounts[periodID], state.cutoverDay)) {
        issues.push(`analyticsUserStats-${periodID}-lifecycle-coverage-invalid`);
      }
    }

    for (const collection of ["analyticsContentStats", "analyticsOrganizationStats"]) {
      for (const periodID of fixedPeriodIDs) {
        const root = await database.collection(collection).doc(periodID).get();
        const data = root.data();
        if (typeof data?.rollupGeneration !== "string" ||
          data.rollupGeneration.length === 0 ||
          data.rollupInProgressGeneration !== null &&
            data.rollupInProgressGeneration !== undefined ||
          !isFreshAfter(data?.updatedAt, completedAt)) {
          issues.push(`${collection}-${periodID}-not-rematerialized`);
        }
        if (!isValidAnalyticsDetailCoverage(
          data,
          periodID,
          detailPeriodSourceCounts[periodID],
          state.cutoverDay
        )) {
          issues.push(`${collection}-${periodID}-coverage-invalid`);
        }
      }
    }
  }

  const deployedCommit = options.deployedCommit === undefined ?
    undefined : assertDeployedCommit(options.deployedCommit);
  if (deployedCommit !== undefined && stateData?.deployedCommit !== deployedCommit) {
    issues.push("deployed-commit-mismatch");
  }

  return {
    cutoverDay: state?.cutoverDay ?? null,
    deployedCommit: stateData?.deployedCommit ?? null,
    issueCount: issues.length,
    issues,
    releaseGatePassed: issues.length === 0,
    nextRequiredStep: issues.length === 0 ?
      "Retain this report with deploy evidence and continue staging/device validation." :
      "Do not release; wait for or repair the listed materializations, then verify again.",
  };
}

async function captureLegacyAnalytics(
  database,
  archiveReference,
  phase,
  cutoverDay,
  options
) {
  const digest = createHash("sha256");
  const detailDigest = createHash("sha256");
  const rootDataByID = new Map();
  const userLifecycleDataByDay = new Map();
  let existingRoots = 0;
  const detailCounts = {};

  for (const definition of rootSnapshots) {
    const path = definition.path ?? `${definition.collection}/${cutoverDay}`;
    const snapshot = await database.doc(path).get();
    const data = snapshot.data();
    rootDataByID.set(definition.id, data);
    updateDigest(digest, path, data ?? null);
    if (snapshot.exists) {
      existingRoots += 1;
    }
    if (options.apply) {
      await archiveReference.collection(`${phase}Roots`).doc(definition.id).set({
        sourcePath: path,
        exists: snapshot.exists,
        ...(data === undefined ? {} : {payload: data}),
        capturedAt: FieldValue.serverTimestamp(),
      });
    }
  }

  for (const dayID of analyticsCutoverWindowDayIDs(lifecycleCaptureDays, options.now)) {
    const path = `analyticsUserStats/${dayID}`;
    const snapshot = await database.doc(path).get();
    const data = snapshot.data();
    userLifecycleDataByDay.set(dayID, data);
    updateDigest(digest, path, data ?? null);
    if (options.apply) {
      await archiveReference.collection(`${phase}UserLifecycle`).doc(dayID).set({
        sourcePath: path,
        exists: snapshot.exists,
        ...(data === undefined ? {} : {payload: data}),
        capturedAt: FieldValue.serverTimestamp(),
      });
    }
  }

  for (const definition of legacyDetailSnapshots) {
    let cursor;
    let count = 0;
    while (true) {
      let query = database
        .collection(definition.sourcePath)
        .orderBy(FieldPath.documentId())
        .limit(options.pageSize ?? defaultPageSize);
      if (cursor !== undefined) {
        query = query.startAfter(cursor);
      }
      const snapshot = await query.get();
      if (snapshot.empty) {
        break;
      }
      count += snapshot.size;
      if (count > maximumLegacyDetailDocuments) {
        throw new Error(
          `${definition.sourcePath} exceeds the ${maximumLegacyDetailDocuments} document safety limit`
        );
      }
      const batch = options.apply ? database.batch() : undefined;
      for (const document of snapshot.docs) {
        const path = `${definition.sourcePath}/${document.id}`;
        updateDigest(digest, path, document.data());
        updateDigest(detailDigest, path, document.data());
        batch?.set(
          archiveReference.collection(`${phase}-${definition.id}`).doc(document.id),
          {
            sourcePath: path,
            payload: document.data(),
            capturedAt: FieldValue.serverTimestamp(),
          }
        );
      }
      if (batch !== undefined) {
        await batch.commit();
      }
      cursor = snapshot.docs.at(-1)?.id;
      if (snapshot.size < (options.pageSize ?? defaultPageSize) || cursor === undefined) {
        break;
      }
    }
    detailCounts[definition.id] = count;
  }

  return {
    digest: digest.digest("hex"),
    detailDigest: detailDigest.digest("hex"),
    rootDataByID,
    userLifecycleDataByDay,
    summary: {
      rootDocumentsExpected: rootSnapshots.length,
      rootDocumentsFound: existingRoots,
      userLifecycleDaysCaptured: userLifecycleDataByDay.size,
      legacyDetailDocuments: detailCounts,
    },
  };
}

function cutoverTopContentSnapshot(capture, cutoverDay) {
  const today = capture.rootDataByID.get("topContentToday");
  if (today?.dateDocumentID !== cutoverDay) {
    throw new Error("legacy top-content today snapshot has not rolled to cutover day");
  }
  return today;
}

function cutoverRegionSnapshot(capture, cutoverDay) {
  const today = capture.rootDataByID.get("regionStatsToday");
  if (today?.dateDocumentID !== cutoverDay) {
    throw new Error("legacy region today snapshot has not rolled to cutover day");
  }
  return today;
}

function assertLegacyTodayRollover(capture, cutoverDay) {
  cutoverTopContentSnapshot(capture, cutoverDay);
  cutoverRegionSnapshot(capture, cutoverDay);
}

function assertQuiescentAnalyticsCutoverDay(capture, preparedStateData) {
  const prepareDetailDigest = preparedStateData?.prepareDetailDigest;
  if (typeof prepareDetailDigest !== "string" ||
    prepareDetailDigest !== capture.detailDigest) {
    throw new Error(
      "legacy detail changed between prepare and finalize; choose a zero-traffic cutover day"
    );
  }

  for (const rootID of ["topContentToday", "topContentDated"]) {
    const data = capture.rootDataByID.get(rootID);
    if (hasTopContentActivity(data)) {
      throw new Error(
        `${rootID} contains cutover-day views; choose a zero-traffic cutover day`
      );
    }
  }
  for (const rootID of ["regionStatsToday", "regionStatsDated"]) {
    const data = capture.rootDataByID.get(rootID);
    if (hasRegionActivity(data)) {
      throw new Error(
        `${rootID} contains cutover-day views; choose a zero-traffic cutover day`
      );
    }
  }
  const dailyData = capture.rootDataByID.get("dailyStatsDated");
  if (hasNumericActivity(dailyData?.metrics) ||
    hasTruthyMapValue(dailyData?.activeRegionKeys)) {
    throw new Error(
      "daily analytics contains cutover-day views/actions; choose a zero-traffic cutover day"
    );
  }
}

function hasTopContentActivity(data) {
  if (Array.isArray(data?.items) && data.items.length > 0) {
    return true;
  }
  const itemsByKey = plainObject(data?.itemsByKey);
  return itemsByKey !== undefined && Object.keys(itemsByKey).length > 0;
}

function hasRegionActivity(data) {
  if (Array.isArray(data?.regions) && data.regions.length > 0) {
    return true;
  }
  const regionsByKey = plainObject(data?.regionsByKey);
  return regionsByKey !== undefined && Object.keys(regionsByKey).length > 0;
}

function hasNumericActivity(value) {
  const record = plainObject(value);
  if (record === undefined) {
    return false;
  }
  return Object.values(record).some((metric) =>
    typeof metric === "number" && Number.isFinite(metric) && metric !== 0
  );
}

function hasTruthyMapValue(value) {
  const record = plainObject(value);
  return record !== undefined && Object.values(record).some((entry) => entry === true);
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) ?
    value : undefined;
}

function updateDigest(hash, path, data) {
  hash.update(path);
  hash.update("\0");
  hash.update(stableJSONString(data));
  hash.update("\n");
}

async function recomputeArchivedCapture(
  archiveReference,
  phase,
  cutoverDay,
  options
) {
  const digest = createHash("sha256");
  const detailDigest = createHash("sha256");
  for (const definition of rootSnapshots) {
    const snapshot = await archiveReference
      .collection(`${phase}Roots`)
      .doc(definition.id)
      .get();
    if (!snapshot.exists || typeof snapshot.get("sourcePath") !== "string") {
      updateDigest(digest, `missing:${definition.id}`, null);
      continue;
    }
    updateDigest(
      digest,
      snapshot.get("sourcePath"),
      snapshot.get("exists") === true ? snapshot.get("payload") : null
    );
  }
  if (typeof cutoverDay !== "string") {
    updateDigest(digest, "missing:cutover-day", null);
  } else {
    for (const dayID of analyticsCutoverWindowDayIDs(
      lifecycleCaptureDays,
      dateForAnalyticsDayID(cutoverDay)
    )) {
      const snapshot = await archiveReference
        .collection(`${phase}UserLifecycle`)
        .doc(dayID)
        .get();
      if (!snapshot.exists || typeof snapshot.get("sourcePath") !== "string") {
        updateDigest(digest, `missing:user-lifecycle:${dayID}`, null);
        continue;
      }
      updateDigest(
        digest,
        snapshot.get("sourcePath"),
        snapshot.get("exists") === true ? snapshot.get("payload") : null
      );
    }
  }
  for (const definition of legacyDetailSnapshots) {
    let cursor;
    let count = 0;
    while (true) {
      let query = archiveReference
        .collection(`${phase}-${definition.id}`)
        .orderBy(FieldPath.documentId())
        .limit(options.pageSize ?? defaultPageSize);
      if (cursor !== undefined) {
        query = query.startAfter(cursor);
      }
      const snapshot = await query.get();
      if (snapshot.empty) {
        break;
      }
      count += snapshot.size;
      if (count > maximumLegacyDetailDocuments) {
        throw new Error("archived detail exceeds the verification safety limit");
      }
      for (const document of snapshot.docs) {
        const sourcePath = document.get("sourcePath");
        if (typeof sourcePath !== "string") {
          updateDigest(digest, `missing:${definition.id}:${document.id}`, null);
          updateDigest(detailDigest, `missing:${definition.id}:${document.id}`, null);
          continue;
        }
        const payload = document.get("payload");
        updateDigest(digest, sourcePath, payload);
        updateDigest(detailDigest, sourcePath, payload);
      }
      cursor = snapshot.docs.at(-1)?.id;
      if (snapshot.size < (options.pageSize ?? defaultPageSize) || cursor === undefined) {
        break;
      }
    }
  }
  return {
    digest: digest.digest("hex"),
    detailDigest: detailDigest.digest("hex"),
  };
}

async function buildUserLifecycleBaselinePlan(
  database,
  finalLifecycleDataByDay,
  coveredThrough,
  options
) {
  const dayIDs = analyticsCutoverWindowDayIDs(lifecycleBaselineDays, options.now);
  const captureDayIDs = analyticsCutoverWindowDayIDs(lifecycleCaptureDays, options.now);
  const dayIDSet = new Set(dayIDs);
  const cumulativeDeletedAccountsNewestFirst = captureDayIDs.map((analyticsDay) => {
    const data = finalLifecycleDataByDay.get(analyticsDay);
    const metrics = plainObject(data?.metrics);
    if (data === undefined || metrics === undefined ||
      metrics.deletedAccounts === undefined) {
      throw new Error(
        `final analyticsUserStats/${analyticsDay}.metrics.deletedAccounts is required ` +
        "to normalize the v1 cumulative series"
      );
    }
    return safeNonNegativeInteger(
      metrics.deletedAccounts,
      `final analyticsUserStats/${analyticsDay}.metrics.deletedAccounts`
    );
  });
  const cumulativeDeletedAccountsOldestFirst = [
    ...cumulativeDeletedAccountsNewestFirst,
  ].reverse();
  const dailyDeletedAccountsOldestFirst = analyticsDailyDeltasFromCumulative(
    cumulativeDeletedAccountsOldestFirst
  );
  const dailyDeletedAccountsByDay = new Map(
    [...captureDayIDs].reverse().slice(1).map((analyticsDay, index) => [
      analyticsDay,
      {
        daily: dailyDeletedAccountsOldestFirst[index],
        cumulative: cumulativeDeletedAccountsOldestFirst[index + 1],
        previousCumulative: cumulativeDeletedAccountsOldestFirst[index],
      },
    ])
  );
  const currentCoveredUsersByDay = new Map();
  let cursor;
  let scannedUsers = 0;
  while (true) {
    let query = database
      .collection("users")
      .select("createdAt")
      .orderBy(FieldPath.documentId())
      .limit(options.pageSize ?? defaultPageSize);
    if (cursor !== undefined) {
      query = query.startAfter(cursor);
    }
    const snapshot = await query.get();
    if (snapshot.empty) {
      break;
    }
    scannedUsers += snapshot.size;
    if (scannedUsers > maximumUserProfiles) {
      throw new Error(`user profile scan exceeds the ${maximumUserProfiles} safety limit`);
    }
    for (const document of snapshot.docs) {
      const createdAt = timestampDate(document.data().createdAt);
      if (createdAt === undefined || createdAt.getTime() > coveredThrough.getTime()) {
        continue;
      }
      const dayID = analyticsCutoverDayID(createdAt);
      if (dayIDSet.has(dayID)) {
        currentCoveredUsersByDay.set(
          dayID,
          (currentCoveredUsersByDay.get(dayID) ?? 0) + 1
        );
      }
    }
    cursor = snapshot.docs.at(-1)?.id;
    if (snapshot.size < (options.pageSize ?? defaultPageSize) || cursor === undefined) {
      break;
    }
  }

  return dayIDs.map((analyticsDay) => {
    const finalMetrics = plainObject(
      finalLifecycleDataByDay.get(analyticsDay)?.metrics
    );
    const sourceLegacyNewRegistrations = safeNonNegativeInteger(
      finalMetrics?.newRegistrations,
      `final analyticsUserStats/${analyticsDay}.metrics.newRegistrations`
    );
    const deletion = dailyDeletedAccountsByDay.get(analyticsDay);
    if (deletion === undefined) {
      throw new Error(`normalized deletion baseline is missing for ${analyticsDay}`);
    }
    const sourceCurrentUserFallback = currentCoveredUsersByDay.get(analyticsDay) ?? 0;
    return {
      analyticsDay,
      newRegistrations: Math.max(
        sourceLegacyNewRegistrations,
        sourceCurrentUserFallback
      ),
      deletedAccounts: deletion.daily,
      sourceLegacyNewRegistrations,
      sourceCurrentUserFallback,
      sourceLegacyDeletedAccountsCumulative: deletion.cumulative,
      sourceLegacyPreviousDeletedAccountsCumulative: deletion.previousCumulative,
      coveredThrough: Timestamp.fromDate(coveredThrough),
    };
  });
}

function digestLifecycleBaselinePlan(plan) {
  return createHash("sha256")
    .update(stableJSONString([...plan].sort((left, right) =>
      left.analyticsDay.localeCompare(right.analyticsDay)
    )))
    .digest("hex");
}

async function recomputeLifecycleBaselineDigests(database, archiveReference) {
  const archiveSnapshot = await archiveReference
    .collection("finalLifecycleBaselines")
    .orderBy(FieldPath.documentId())
    .get();
  const archivePlan = archiveSnapshot.docs.map((document) => ({
    analyticsDay: document.id,
    newRegistrations: document.get("newRegistrations"),
    deletedAccounts: document.get("deletedAccounts"),
    sourceLegacyNewRegistrations: document.get("sourceLegacyNewRegistrations"),
    sourceCurrentUserFallback: document.get("sourceCurrentUserFallback"),
    sourceLegacyDeletedAccountsCumulative: document.get(
      "sourceLegacyDeletedAccountsCumulative"
    ),
    sourceLegacyPreviousDeletedAccountsCumulative: document.get(
      "sourceLegacyPreviousDeletedAccountsCumulative"
    ),
    coveredThrough: document.get("coveredThrough"),
  }));
  const liveSnapshots = archivePlan.length === 0 ? [] : await database.getAll(
    ...archivePlan.map((baseline) => database
      .collection(lifecycleBaselineCollection)
      .doc(baseline.analyticsDay))
  );
  const livePlan = liveSnapshots.map((snapshot) => ({
    analyticsDay: snapshot.id,
    newRegistrations: snapshot.data()?.newRegistrations,
    deletedAccounts: snapshot.data()?.deletedAccounts,
    sourceLegacyNewRegistrations: snapshot.data()?.sourceLegacyNewRegistrations,
    sourceCurrentUserFallback: snapshot.data()?.sourceCurrentUserFallback,
    sourceLegacyDeletedAccountsCumulative:
      snapshot.data()?.sourceLegacyDeletedAccountsCumulative,
    sourceLegacyPreviousDeletedAccountsCumulative:
      snapshot.data()?.sourceLegacyPreviousDeletedAccountsCumulative,
    coveredThrough: snapshot.data()?.coveredThrough,
  }));
  if (archivePlan.length !== lifecycleBaselineDays ||
    liveSnapshots.some((snapshot) => !snapshot.exists)) {
    return {archiveDigest: "incomplete", liveDigest: "incomplete"};
  }
  return {
    archiveDigest: digestLifecycleBaselinePlan(archivePlan),
    liveDigest: digestLifecycleBaselinePlan(livePlan),
  };
}

function safeNonNegativeInteger(value, field) {
  if (value === undefined) {
    return 0;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative safe integer`);
  }
  return value;
}

function dateForAnalyticsDayID(dayID) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dayID)) {
    throw new Error("analytics day ID is malformed");
  }
  const date = new Date(`${dayID}T12:00:00.000Z`);
  if (!Number.isFinite(date.getTime())) {
    throw new Error("analytics day ID is invalid");
  }
  return date;
}

function timestampDate(value) {
  if (value instanceof Date) {
    return value;
  }
  if (typeof value?.toDate === "function") {
    const date = value.toDate();
    return Number.isFinite(date.getTime()) ? date : undefined;
  }
  return undefined;
}

function isFreshAfter(value, threshold) {
  const date = timestampDate(value);
  return date !== undefined && threshold !== undefined &&
    date.getTime() >= threshold.getTime();
}

function requiredDate(value, name) {
  const date = new Date(value);
  if (typeof value !== "string" || !Number.isFinite(date.getTime())) {
    throw new Error(`${name} must be an RFC 3339 timestamp`);
  }
  return date;
}

function parseArguments(argumentsList) {
  const values = {};
  const flags = new Set();
  for (const argument of argumentsList) {
    if (argument === "--apply") {
      flags.add("apply");
      continue;
    }
    const match = /^--([a-z-]+)=(.*)$/.exec(argument);
    if (match === null) {
      throw new Error(`unsupported argument ${argument}`);
    }
    values[match[1]] = match[2];
  }

  const phase = values.phase;
  if (!new Set(["prepare", "finalize", "verify", "abort"]).has(phase)) {
    throw new Error("phase must be prepare, finalize, verify, or abort");
  }
  const projectId = requiredNonEmpty(values.project, "project");
  const generation = requiredNonEmpty(values.generation, "generation");
  const apply = flags.has("apply");
  if (apply && values["confirm-project"] !== projectId) {
    throw new Error("--confirm-project must exactly match --project for apply mode");
  }
  if (apply && (values.operator === undefined || values.ticket === undefined)) {
    throw new Error("apply mode requires --operator and --ticket");
  }
  if (apply && (phase === "prepare" || phase === "finalize") &&
    values.maintenance !== "confirmed") {
    throw new Error("prepare/finalize apply mode requires --maintenance=confirmed");
  }
  if (apply && values["report-file"] === undefined) {
    throw new Error("apply mode requires --report-file for retained evidence");
  }
  if (phase === "finalize" &&
    (values["deployed-at"] === undefined || values["deployed-commit"] === undefined)) {
    throw new Error("finalize requires --deployed-at and --deployed-commit");
  }
  if (phase === "verify" && values["deployed-commit"] === undefined) {
    throw new Error("verify requires --deployed-commit");
  }
  if (phase === "verify" && apply) {
    throw new Error("verify is read-only and does not accept --apply");
  }
  if (phase === "abort" && values.reason === undefined) {
    throw new Error("abort requires --reason");
  }

  const pageSize = integerOption(values["page-size"], defaultPageSize, 1, 400);
  const minimumDrainSeconds = integerOption(
    values["minimum-drain-seconds"],
    defaultMinimumDrainSeconds,
    defaultMinimumDrainSeconds,
    3_600
  );
  return {
    phase,
    projectId,
    generation,
    apply,
    operator: values.operator,
    ticket: values.ticket,
    reportFile: values["report-file"],
    deployedAt: values["deployed-at"],
    deployedCommit: values["deployed-commit"],
    reason: values.reason,
    maintenance: values.maintenance,
    pageSize,
    minimumDrainSeconds,
  };
}

function requiredNonEmpty(value, name) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`--${name} is required`);
  }
  return value.trim();
}

function integerOption(value, fallback, minimum, maximum) {
  if (value === undefined) {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`integer option must be between ${minimum} and ${maximum}`);
  }
  return parsed;
}

function assertMaintenanceConfirmed(options) {
  if (options.apply && options.maintenance !== "confirmed") {
    throw new Error("apply mode requires confirmed account/content write maintenance");
  }
}

export function assertProductionFirestoreEndpoint(environment = process.env) {
  if (typeof environment.FIRESTORE_EMULATOR_HOST === "string" &&
    environment.FIRESTORE_EMULATOR_HOST.trim().length > 0) {
    throw new Error(
      "cutover CLI refuses FIRESTORE_EMULATOR_HOST; production evidence must use the production endpoint"
    );
  }
}

export async function immutableAtomicWrite(path, contents) {
  const destination = resolve(path);
  await mkdir(dirname(destination), {recursive: true});
  const temporary = `${destination}.tmp-${process.pid}-${Date.now()}`;
  await writeFile(temporary, contents, {
    encoding: "utf8",
    mode: 0o600,
    flag: "wx",
  });
  try {
    // A hard link is an atomic create-if-absent operation. Unlike rename(), it
    // cannot silently replace evidence from an earlier production phase.
    await link(temporary, destination);
  } finally {
    await unlink(temporary).catch(() => undefined);
  }
}

function isMainModule() {
  return process.argv[1] !== undefined &&
    import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
}
