import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  writeBatch,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-analytics-rules";
const RULES_PATH = "../../Firebase/firestore.rules";

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL(RULES_PATH, import.meta.url), "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function auth(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  }).firestore();
}

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}

function user(uid, globalRole) {
  return {
    id: uid,
    globalRole,
    accountStatus: "active",
    blockState: "active",
  };
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await Promise.all([
      setDoc(doc(database, "users", "owner"), user("owner", "owner")),
      setDoc(doc(database, "users", "admin"), user("admin", "admin")),
      setDoc(doc(database, "users", "user"), user("user", "user")),
      setDoc(doc(database, "news", "approved-news"), {moderationStatus: "approved"}),
      setDoc(doc(database, "events", "approved-event"), {moderationStatus: "approved"}),
      setDoc(doc(database, "news", "pending-news"), {moderationStatus: "pendingReview"}),
      setDoc(doc(database, "events", "pending-event"), {moderationStatus: "pendingReview"}),
      setDoc(doc(database, "analyticsDailyStats", "2026-08-24"), {metrics: {newsViews: 1}}),
      setDoc(doc(database, "analyticsTopContent", "seven_days"), {items: []}),
      setDoc(doc(database, "analyticsRegionStats", "seven_days"), {regions: []}),
      setDoc(doc(database, "analyticsUserStats", "seven_days"), {metrics: {totalUsers: 3}}),
      setDoc(doc(database, "analyticsContentStats", "seven_days"), {periodId: "seven_days"}),
      setDoc(
        doc(database, "analyticsContentStats", "seven_days", "items", "news_news__1"),
        {contentID: "news_1", contentType: "news", metrics: {views: 1}}
      ),
      setDoc(doc(database, "analyticsOrganizationStats", "seven_days"), {periodId: "seven_days"}),
      setDoc(
        doc(database, "analyticsOrganizationStats", "seven_days", "organizations", "org-1"),
        {organizationID: "org-1", metrics: {profileViews: 1}}
      ),
      setDoc(doc(database, "analyticsUserActivity", "user"), {expiresAt: new Date("2026-10-01")}),
      setDoc(doc(database, "analyticsDeletedUserEvents", "event-1"), {analyticsDay: "2026-08-24"}),
      setDoc(doc(database, "analyticsUserRegistrationEvents", "event-1"), {analyticsDay: "2026-08-24"}),
      setDoc(doc(database, "analyticsUserLifecycleBaselines", "2026-08-24"), {
        analyticsDay: "2026-08-24",
        newRegistrations: 1,
        deletedAccounts: 0,
      }),
      setDoc(doc(database, "analyticsSchemaState", "current"), {
        schemaVersion: 2,
        status: "prepared",
      }),
      setDoc(doc(database, "analyticsSchemaCutoverArchives", "generation-1"), {
        schemaVersion: 2,
      }),
    ]);
  });
}

function aggregateReferences(database) {
  return [
    doc(database, "analyticsDailyStats", "2026-08-24"),
    doc(database, "analyticsTopContent", "seven_days"),
    doc(database, "analyticsRegionStats", "seven_days"),
    doc(database, "analyticsUserStats", "seven_days"),
    doc(database, "analyticsContentStats", "seven_days"),
    doc(database, "analyticsContentStats", "seven_days", "items", "news_news__1"),
    doc(database, "analyticsOrganizationStats", "seven_days"),
    doc(database, "analyticsOrganizationStats", "seven_days", "organizations", "org-1"),
  ];
}

function markerReferences(database) {
  return [
    doc(database, "analyticsUserActivity", "user"),
    doc(database, "analyticsDeletedUserEvents", "event-1"),
    doc(database, "analyticsUserRegistrationEvents", "event-1"),
    doc(database, "analyticsUserLifecycleBaselines", "2026-08-24"),
    doc(database, "analyticsSchemaState", "current"),
    doc(database, "analyticsSchemaCutoverArchives", "generation-1"),
  ];
}

describe("analytics access contract", () => {
  test("only the active platform owner can read every aggregate and detail document", async () => {
    const ownerDatabase = auth("owner");
    for (const reference of aggregateReferences(ownerDatabase)) {
      await assertSucceeds(getDoc(reference));
    }

    for (const database of [auth("admin"), auth("user"), unauthenticated()]) {
      for (const reference of aggregateReferences(database)) {
        await assertFails(getDoc(reference));
      }
    }
  });

  test("aggregate writes and lifecycle marker access are denied to every client role", async () => {
    for (const database of [auth("owner"), auth("admin"), auth("user"), unauthenticated()]) {
      await assertFails(setDoc(
        doc(database, "analyticsDailyStats", "forged"),
        {metrics: {newsViews: 999}}
      ));
      await assertFails(setDoc(
        doc(database, "analyticsContentStats", "seven_days", "items", "forged"),
        {contentID: "forged", contentType: "news", metrics: {views: 999}}
      ));

      for (const reference of markerReferences(database)) {
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, {
          analyticsDay: "2026-08-24",
          expiresAt: new Date("2026-10-01"),
        }));
      }
    }
  });

  test("approved content view markers are immutable and cannot be recreated", async () => {
    const database = auth("user");
    const newsView = doc(database, "users", "user", "newsViews", "approved-news");
    const eventView = doc(database, "users", "user", "eventViews", "approved-event");

    await assertSucceeds(setDoc(newsView, {
      id: "approved-news",
      newsId: "approved-news",
      userId: "user",
      createdAt: serverTimestamp(),
    }));
    await assertSucceeds(setDoc(eventView, {
      id: "approved-event",
      eventId: "approved-event",
      userId: "user",
      createdAt: serverTimestamp(),
    }));

    await assertFails(deleteDoc(newsView));
    await assertFails(deleteDoc(eventView));
    await assertFails(setDoc(newsView, {
      id: "approved-news",
      newsId: "approved-news",
      userId: "user",
      createdAt: serverTimestamp(),
    }));
    await assertFails(setDoc(eventView, {
      id: "approved-event",
      eventId: "approved-event",
      userId: "user",
      createdAt: serverTimestamp(),
    }));
  });

  test("view marker creation rejects extra fields and non-approved targets", async () => {
    const database = auth("user");

    for (const [contentType, contentId, foreignKey] of [
      ["news", "approved-news", "newsId"],
      ["events", "approved-event", "eventId"],
    ]) {
      const collectionName = contentType === "news" ? "newsViews" : "eventViews";
      await assertFails(setDoc(
        doc(database, "users", "user", collectionName, contentId),
        {
          id: contentId,
          [foreignKey]: contentId,
          userId: "user",
          createdAt: serverTimestamp(),
          forged: true,
        }
      ));
    }

    for (const [collectionName, contentId, foreignKey] of [
      ["newsViews", "missing-news", "newsId"],
      ["eventViews", "missing-event", "eventId"],
      ["newsViews", "pending-news", "newsId"],
      ["eventViews", "pending-event", "eventId"],
    ]) {
      await assertFails(setDoc(
        doc(database, "users", "user", collectionName, contentId),
        {
          id: contentId,
          [foreignKey]: contentId,
          userId: "user",
          createdAt: serverTimestamp(),
        }
      ));
    }
  });

  test("action proofs are private and must be created atomically with the action", async () => {
    const database = auth("user");
    const proofID = "123e4567-e89b-42d3-a456-426614174000";
    const proofReference = doc(database, "analyticsActionProofs", proofID);
    const proof = {
      proofId: proofID,
      eventName: "news_like",
      contentId: "approved-news",
      actorBinding: "a".repeat(64),
      sessionBinding: "b".repeat(64),
      createdAt: serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 48 * 60 * 60 * 1_000),
    };

    await assertFails(setDoc(proofReference, proof));

    const batch = writeBatch(database);
    batch.set(doc(database, "likes", "approved-news_user"), {
      id: "approved-news_user",
      newsId: "approved-news",
      userId: "user",
      createdAt: serverTimestamp(),
    });
    batch.set(proofReference, proof);
    await assertSucceeds(batch.commit());

    await assertFails(getDoc(proofReference));
    await assertFails(deleteDoc(proofReference));
  });
});
