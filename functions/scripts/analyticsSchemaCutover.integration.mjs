import {strict as assert} from "node:assert";
import {test} from "node:test";

import {initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";

import {
  analyticsCutoverDayID,
  analyticsCutoverWindowDayIDs,
} from "./analyticsSchemaCutoverCore.mjs";
import {
  abortAnalyticsSchemaCutover,
  finalizeAnalyticsSchemaCutover,
  prepareAnalyticsSchemaCutover,
  verifyAnalyticsSchemaCutover,
} from "./migrateAnalyticsSchemaV2.mjs";
import {
  rollupAnalyticsPeriods,
  rollupUserAnalyticsStats,
} from "../lib/analytics/trackAnalyticsEvent.js";
import {analyticsRegistrationUserKey} from "../lib/analytics/analyticsEventGuard.js";

const projectId = "demo-ukrainian-community-analytics-cutover";
const generation = "analytics-v2-integration";
const app = initializeApp({projectId}, `analytics-cutover-test-${Date.now()}`);
const database = getFirestore(app);
const deployedCommit = "abcdef1234567890abcdef1234567890abcdef12";

test("gated cutover rejects traffic, archives lifetime detail, and rematerializes cleanly", async () => {
  // Keep the synthetic boundary safely in the past so the real materializer's
  // own clock accepts post-boundary profiles instead of rejecting future data.
  const prepareTime = new Date(Date.now() - 24 * 60 * 60 * 1_000);
  const deployedAt = new Date(prepareTime.getTime() + 60_000);
  const finalizeTime = new Date(deployedAt.getTime() + 11 * 60_000);
  const cutoverDay = analyticsCutoverDayID(prepareTime);
  await seedLegacyFixture(prepareTime, new Date(prepareTime.getTime() - 60_000));

  const abandonedGeneration = `${generation}-aborted`;
  await prepareAnalyticsSchemaCutover(database, {
    generation: abandonedGeneration,
    now: prepareTime,
    apply: true,
    operator: "integration-test",
    ticket: "ANALYTICS-CUTOVER-TEST",
    maintenance: "confirmed",
    pageSize: 1,
  });
  await database.doc("analyticsSchemaState/current").update({
    status: "finalizing",
    finalizingAttemptID: "interrupted-integration-attempt",
  });
  const aborted = await abortAnalyticsSchemaCutover(database, {
    generation: abandonedGeneration,
    now: prepareTime,
    apply: true,
    operator: "integration-test",
    ticket: "ANALYTICS-CUTOVER-TEST",
    reason: "Integration recovery exercise",
  });
  assert.equal(aborted.stateAfterPhase, "aborted");
  assert.equal(
    (await database.doc("analyticsSchemaState/current").get()).get("status"),
    "aborted"
  );
  await assert.rejects(
    prepareAnalyticsSchemaCutover(database, {
      generation: abandonedGeneration,
      now: prepareTime,
      apply: true,
      operator: "integration-test",
      ticket: "ANALYTICS-CUTOVER-TEST",
      maintenance: "confirmed",
      pageSize: 1,
    }),
    /cannot be reused|already exists/
  );

  const prepared = await prepareAnalyticsSchemaCutover(database, {
    generation,
    now: prepareTime,
    apply: true,
    operator: "integration-test",
    ticket: "ANALYTICS-CUTOVER-TEST",
    maintenance: "confirmed",
    pageSize: 1,
  });
  assert.equal(prepared.stateAfterPhase, "prepared");
  assert.deepEqual(prepared.capture.legacyDetailDocuments, {
    contentItems: 2,
    organizations: 1,
  });
  assert.equal(prepared.capture.userLifecycleDaysCaptured, 31);
  const preparedState = await database.doc("analyticsSchemaState/current").get();
  assert.equal(preparedState.get("status"), "prepared");
  // Production uses the server-recorded prepare time. The integration keeps
  // its boundary one day in the past so the real materializer can run, then
  // mirrors that server timestamp explicitly inside the isolated emulator.
  await preparedState.ref.update({
    preparedAt: Timestamp.fromDate(prepareTime),
  });

  // An old v1 action completing between prepare and deploy changes lifetime
  // detail and daily totals even though top-content views remain empty. The
  // finalizer must fail closed instead of mislabeling lifetime detail as Today.
  await Promise.all([
    database.doc(`analyticsDailyStats/${cutoverDay}`).set({
      metrics: {newsLikes: 1, totalActions: 1},
      updatedAt: Timestamp.fromDate(new Date("2026-08-24T09:06:00Z")),
    }),
    database.doc("analyticsContentStats/today/items/news_a").set({
      metrics: {likes: FieldValue.increment(1)},
      updatedAt: Timestamp.fromDate(new Date("2026-08-24T09:06:00Z")),
    }, {merge: true}),
  ]);

  await assert.rejects(
    finalizeAnalyticsSchemaCutover(database, {
      generation,
      now: finalizeTime,
      deployedAt: deployedAt.toISOString(),
      deployedCommit,
      minimumDrainSeconds: 600,
      apply: true,
      operator: "integration-test",
      ticket: "ANALYTICS-CUTOVER-TEST",
      maintenance: "confirmed",
      pageSize: 1,
    }),
    /zero-traffic cutover day|legacy detail changed/
  );
  await Promise.all([
    database.doc(`analyticsDailyStats/${cutoverDay}`).delete(),
    database.doc("analyticsContentStats/today/items/news_a").set({
      contentID: "a",
      metrics: {views: 8},
      updatedAt: Timestamp.fromDate(new Date("2026-08-24T08:55:00Z")),
    }),
  ]);

  await Promise.all([
    database.doc("analyticsUserRegistrationEvents/covered-boundary").set({
      analyticsDay: cutoverDay,
      userKey: "covered-user",
      registeredAt: Timestamp.fromDate(deployedAt),
    }),
    database.doc("analyticsDeletedUserEvents/post-boundary").set({
      analyticsDay: cutoverDay,
      deletedAt: Timestamp.fromDate(new Date(deployedAt.getTime() + 1)),
    }),
    database.doc("users/post-boundary-user").set({
      createdAt: Timestamp.fromDate(new Date(deployedAt.getTime() + 1)),
    }),
    database.doc("analyticsUserRegistrationEvents/post-boundary").set({
      analyticsDay: cutoverDay,
      userKey: analyticsRegistrationUserKey("post-boundary-user"),
      registeredAt: Timestamp.fromDate(new Date(deployedAt.getTime() + 1)),
    }),
  ]);

  const finalized = await finalizeAnalyticsSchemaCutover(database, {
    generation,
    now: finalizeTime,
    deployedAt: deployedAt.toISOString(),
    deployedCommit,
    minimumDrainSeconds: 600,
    apply: true,
    operator: "integration-test",
    ticket: "ANALYTICS-CUTOVER-TEST",
    maintenance: "confirmed",
    pageSize: 1,
  });
  assert.equal(finalized.stateAfterPhase, "complete");
  assert.match(finalized.finalizeAttemptID, /^[a-f0-9-]{36}$/);
  const datedTop = await database.doc(`analyticsTopContent/${cutoverDay}`).get();
  assert.deepEqual(datedTop.get("itemsByKey"), {});
  assert.equal(datedTop.get("cutoverGeneration"), generation);
  const datedRegion = await database.doc(`analyticsRegionStats/${cutoverDay}`).get();
  assert.deepEqual(datedRegion.get("regionsByKey"), {});
  assert.equal(datedRegion.get("cutoverGeneration"), generation);
  const lifecycleBaseline = await database
    .doc(`analyticsUserLifecycleBaselines/${cutoverDay}`)
    .get();
  assert.equal(lifecycleBaseline.get("newRegistrations"), 2);
  assert.equal(lifecycleBaseline.get("deletedAccounts"), 1);
  assert.equal(
    lifecycleBaseline.get("coveredThrough").toDate().toISOString(),
    deployedAt.toISOString()
  );
  for (const periodID of ["today", "seven_days", "thirty_days"]) {
    assert.equal((await database.doc(`analyticsUserStats/${periodID}`).get()).exists, false);
  }
  const finalContentArchive = await database
    .collection(`${"analyticsSchemaCutoverArchives"}/${generation}/final-contentItems`)
    .get();
  assert.equal(finalContentArchive.size, 2);

  await rollupUserAnalyticsStats.run({scheduleTime: finalizeTime.toISOString()});
  const materializedThirtyDays = await database
    .doc("analyticsUserStats/thirty_days")
    .get();
  assert.equal(materializedThirtyDays.get("metrics.totalUsers"), 2);
  assert.equal(materializedThirtyDays.get("metrics.newRegistrations"), 3);
  assert.equal(materializedThirtyDays.get("metrics.deletedAccounts"), 2);
  assert.equal(materializedThirtyDays.get("lifecycleCoverageStartDay"), cutoverDay);
  assert.equal(materializedThirtyDays.get("isLifecyclePartialCoverage"), true);

  const incompleteVerification = await verifyAnalyticsSchemaCutover(database, {
    generation,
    now: finalizeTime,
    deployedCommit,
  });
  assert.equal(incompleteVerification.releaseGatePassed, false);
  assert.ok(incompleteVerification.issues.includes(
    "analyticsTopContent-today-not-rematerialized"
  ));

  const completeState = await database.doc("analyticsSchemaState/current").get();
  const completedAt = completeState.get("completedAt").toDate();
  await rollupAnalyticsPeriods.run({scheduleTime: completedAt.toISOString()});
  const contentThirtyDays = await database
    .doc("analyticsContentStats/thirty_days")
    .get();
  assert.equal(contentThirtyDays.get("coverageStartDay"), cutoverDay);
  assert.equal(contentThirtyDays.get("isPartialCoverage"), true);
  assert.ok(contentThirtyDays.get("coveredSourceDocumentIDs").includes(cutoverDay));

  const prepareTopArchiveReference = database.doc(
    `analyticsSchemaCutoverArchives/${generation}/prepareRoots/topContentToday`
  );
  const originalPrepareTopArchive = (await prepareTopArchiveReference.get()).data();
  assert.ok(originalPrepareTopArchive);
  await prepareTopArchiveReference.set({
    ...originalPrepareTopArchive,
    payload: {
      ...originalPrepareTopArchive.payload,
      dateDocumentID: "tampered-day",
    },
  });
  const tamperedVerification = await verifyAnalyticsSchemaCutover(database, {
    generation,
    now: new Date(completedAt.getTime() + 2_000),
    deployedCommit,
  });
  assert.equal(tamperedVerification.releaseGatePassed, false);
  assert.ok(tamperedVerification.issues.includes(
    "prepare-archive-content-digest-mismatch"
  ));
  await prepareTopArchiveReference.set(originalPrepareTopArchive);

  const verification = await verifyAnalyticsSchemaCutover(database, {
    generation,
    now: new Date(completedAt.getTime() + 2_000),
    deployedCommit,
  });
  assert.deepEqual(verification.issues, []);
  assert.equal(verification.releaseGatePassed, true);
});

async function seedLegacyFixture(anchor, currentUserCreatedAt) {
  const cutoverDay = analyticsCutoverDayID(anchor);
  const timestamp = Timestamp.fromDate(new Date("2026-08-24T08:55:00Z"));
  await Promise.all([
    database.doc("analyticsTopContent/today").set({
      dateDocumentID: cutoverDay,
      items: [],
      itemsByKey: {},
      updatedAt: timestamp,
    }),
    database.doc(`analyticsTopContent/${cutoverDay}`).set({
      dateDocumentID: cutoverDay,
      items: [],
      itemsByKey: {},
      updatedAt: timestamp,
    }),
    database.doc("analyticsRegionStats/today").set({
      dateDocumentID: cutoverDay,
      regions: [],
      regionsByKey: {},
      updatedAt: timestamp,
    }),
    database.doc(`analyticsRegionStats/${cutoverDay}`).set({
      dateDocumentID: cutoverDay,
      regions: [],
      regionsByKey: {},
      updatedAt: timestamp,
    }),
    database.doc("analyticsUserStats/today").set({
      period: "today",
      metrics: {totalUsers: 10},
      generatedAt: timestamp,
    }),
    database.doc("analyticsUserStats/seven_days").set({
      period: "seven_days",
      metrics: {totalUsers: 10},
      generatedAt: timestamp,
    }),
    database.doc("analyticsUserStats/thirty_days").set({
      period: "thirty_days",
      metrics: {totalUsers: 10},
      generatedAt: timestamp,
    }),
    ...analyticsCutoverWindowDayIDs(31, anchor).map((analyticsDay, index) =>
      database.doc(`analyticsUserStats/${analyticsDay}`).set({
        period: analyticsDay,
        metrics: {
          totalUsers: 10,
          newRegistrations: index === 0 ? 2 : 0,
          // v1 leaked its cumulative deletion total into each dated document.
          // One cutover-day deletion is therefore 0...0,1 chronologically.
          deletedAccounts: index === 0 ? 1 : 0,
        },
        generatedAt: timestamp,
      })
    ),
    database.doc("users/current-user").set({
      createdAt: Timestamp.fromDate(currentUserCreatedAt),
    }),
    database.doc("analyticsContentStats/today/items/news_a").set({
      contentID: "a",
      metrics: {views: 8},
      updatedAt: timestamp,
    }),
    database.doc("analyticsContentStats/today/items/event_b").set({
      contentID: "b",
      metrics: {views: 4},
      updatedAt: timestamp,
    }),
    database.doc("analyticsOrganizationStats/today/organizations/org_a").set({
      organizationID: "org-a",
      metrics: {profileViews: 2},
      updatedAt: timestamp,
    }),
  ]);
}
