import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-cancelled-event-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const cancelledEventId = "cancelled-event";
const approvedEventId = "approved-event";

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
  await testEnv.cleanup();
});

function auth(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, "users", "registered-user"), user("registered-user"));
    await setDoc(doc(db, "users", "other-user"), user("other-user"));
    await setDoc(doc(db, "users", "org-owner"), user("org-owner"));
    await setDoc(doc(db, "users", "suspended-user"), user("suspended-user", {
      accountStatus: "suspendedUntil",
      blockState: "suspendedUntil",
    }));

    await setDoc(doc(db, "organizations", "org-1"), {
      id: "org-1",
      ownerId: "org-owner",
      adminIds: [],
      moderatorIds: [],
      moderationStatus: "approved",
    });

    await setDoc(doc(db, "events", cancelledEventId), event({
      id: cancelledEventId,
      moderationStatus: "archived",
      cancellationState: "cancelled",
    }));
    await setDoc(doc(db, "events", approvedEventId), event({
      id: approvedEventId,
      moderationStatus: "approved",
    }));

    await setDoc(
      doc(db, "registrations", `event_${cancelledEventId}_registered-user`),
      registration(cancelledEventId, "registered-user")
    );
    await setDoc(
      doc(db, "registrations", `event_${cancelledEventId}_suspended-user`),
      registration(cancelledEventId, "suspended-user")
    );
  });
}

function user(uid, overrides = {}) {
  return {
    id: uid,
    globalRole: "user",
    accountStatus: "active",
    blockState: "active",
    ...overrides,
  };
}

function event(overrides = {}) {
  return {
    id: overrides.id,
    title: "Community event",
    summary: "Summary",
    details: "Details",
    sourceType: "organization",
    organizationId: "org-1",
    organizationName: "Organization",
    city: "Vienna",
    venue: "Community hall",
    startDate: new Date("2026-07-01T10:00:00Z"),
    endDate: new Date("2026-07-01T12:00:00Z"),
    createdAt: new Date("2026-06-01T10:00:00Z"),
    updatedAt: new Date("2026-06-10T10:00:00Z"),
    requiresRegistration: true,
    price: 0,
    registeredCount: 1,
    moderationStatus: "approved",
    registrationState: "notRegistered",
    likeCount: 0,
    viewCount: 0,
    category: "meetups",
    tags: [],
    visibility: "public",
    isAllDay: false,
    ...overrides,
  };
}

function registration(eventId, userId) {
  return {
    id: `event_${eventId}_${userId}`,
    eventId,
    userId,
    registeredAt: new Date("2026-06-05T10:00:00Z"),
    createdAt: new Date("2026-06-05T10:00:00Z"),
  };
}

describe("cancelled event read access", () => {
  test("registered active user can read archived cancelled event", async () => {
    const db = auth("registered-user");
    await assertSucceeds(getDoc(doc(db, "events", cancelledEventId)));
  });

  test("non-registered user cannot read archived cancelled event", async () => {
    const db = auth("other-user");
    await assertFails(getDoc(doc(db, "events", cancelledEventId)));
  });

  test("guest cannot read archived cancelled event", async () => {
    const db = unauthenticated();
    await assertFails(getDoc(doc(db, "events", cancelledEventId)));
  });

  test("suspended registered user cannot read archived cancelled event", async () => {
    const db = auth("suspended-user");
    await assertFails(getDoc(doc(db, "events", cancelledEventId)));
  });

  test("organization owner can read archived cancelled event", async () => {
    const db = auth("org-owner");
    await assertSucceeds(getDoc(doc(db, "events", cancelledEventId)));
  });

  test("approved public event remains readable", async () => {
    const db = auth("other-user");
    await assertSucceeds(getDoc(doc(db, "events", approvedEventId)));
  });

  test("approved event list query excludes archived cancelled events", async () => {
    const db = auth("registered-user");
    await assertSucceeds(getDocs(query(
      collection(db, "events"),
      where("moderationStatus", "==", "approved")
    )));
  });
});
