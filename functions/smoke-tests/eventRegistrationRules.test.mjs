import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-event-registration-rules";
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
  await testEnv.cleanup();
});

function auth(uid) {
  return testEnv.authenticatedContext(uid, {email_verified: true}).firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "registered-user"), user("registered-user"));
    await setDoc(doc(db, "users", "other-user"), user("other-user"));
    await setDoc(doc(db, "users", "org-owner"), user("org-owner"));
    await setDoc(doc(db, "users", "platform-owner"), user("platform-owner", {
      globalRole: "owner",
    }));
    await setDoc(doc(db, "organizations", "org-1"), {
      id: "org-1",
      ownerId: "org-owner",
      adminIds: [],
      moderatorIds: [],
      moderationStatus: "approved",
    });
    await setDoc(doc(db, "events", "event-1"), event());
    await setDoc(
      doc(db, "registrations", "event_event-1_registered-user"),
      registration("registered-user")
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

function event() {
  return {
    id: "event-1",
    title: "Server registration test",
    summary: "Summary",
    details: "Details",
    sourceType: "organization",
    organizationId: "org-1",
    organizationName: "Organization",
    city: "Vienna",
    venue: "Community hall",
    startDate: new Date("2027-01-15T10:00:00Z"),
    endDate: new Date("2027-01-15T12:00:00Z"),
    createdAt: new Date("2026-06-01T10:00:00Z"),
    updatedAt: new Date("2026-06-01T10:00:00Z"),
    requiresRegistration: true,
    capacity: 10,
    registeredCount: 1,
    moderationStatus: "approved",
    registrationState: "notRegistered",
    cancellationState: "active",
    likeCount: 0,
    commentCount: 0,
    viewCount: 0,
    category: "meetups",
    tags: [],
    visibility: "public",
    isAllDay: false,
  };
}

function registration(userId) {
  return {
    id: `event_event-1_${userId}`,
    eventId: "event-1",
    userId,
    registeredAt: new Date("2026-08-24T10:00:00Z"),
    createdAt: new Date("2026-08-24T10:00:00Z"),
    counterManagedAtomically: true,
    counterOperationId: "operation-1",
  };
}

describe("server-owned event registration invariant", () => {
  test("a user can read only their own registration", async () => {
    await assertSucceeds(getDoc(doc(
      auth("registered-user"),
      "registrations",
      "event_event-1_registered-user"
    )));
    await assertFails(getDoc(doc(
      auth("other-user"),
      "registrations",
      "event_event-1_registered-user"
    )));
  });

  test("verified users and platform owners cannot directly create registrations", async () => {
    for (const uid of ["other-user", "platform-owner"]) {
      await assertFails(setDoc(
        doc(auth(uid), "registrations", `event_event-1_${uid}`),
        registration(uid)
      ));
    }
  });

  test("users and platform owners cannot directly update or delete registrations", async () => {
    const registrationPath = "event_event-1_registered-user";
    await assertFails(updateDoc(
      doc(auth("registered-user"), "registrations", registrationPath),
      {registeredAt: new Date("2026-08-24T11:00:00Z")}
    ));
    await assertFails(deleteDoc(doc(
      auth("registered-user"),
      "registrations",
      registrationPath
    )));
    await assertFails(deleteDoc(doc(
      auth("platform-owner"),
      "registrations",
      registrationPath
    )));
  });

  test("an organization owner cannot forge registeredCount", async () => {
    await assertFails(updateDoc(doc(auth("org-owner"), "events", "event-1"), {
      registeredCount: 9,
      updatedAt: new Date("2026-08-24T12:00:00Z"),
    }));
  });
});
