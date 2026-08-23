import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-organization-region-scope-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const APPROVED_ORGANIZATION_ID = "approved-organization";
const REQUEST_ORGANIZATION_ID = "request-organization";

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

function user(uid) {
  return {
    id: uid,
    globalRole: "user",
    accountStatus: "active",
    blockState: "active",
  };
}

function organizationRequest(id, regionScope) {
  const request = {
    id,
    name: "Requested Organization",
    description: "Requested organization",
    city: "Wien",
    federalState: "wien",
    ownerId: "",
    adminIds: [],
    moderatorIds: [],
    subscriberCount: 0,
    eventsHeldCount: 0,
    volunteersCount: 0,
    helpedPeopleCount: 0,
    likeCount: 0,
    likeState: "notLiked",
    moderationStatus: "pendingReview",
    submittedByUserId: "request-submitter",
    submittedAt: new Date("2026-08-01T10:00:00Z"),
    createdAt: new Date("2026-08-01T10:00:00Z"),
    updatedAt: new Date("2026-08-01T10:00:00Z"),
  };

  if (regionScope !== undefined) {
    request.regionScope = regionScope;
  }

  return request;
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await Promise.all([
      "organization-owner",
      "organization-admin",
      "organization-moderator",
      "request-submitter",
      "unrelated-user",
    ].map((uid) => setDoc(doc(db, "users", uid), user(uid))));

    await setDoc(doc(db, "organizations", APPROVED_ORGANIZATION_ID), {
      id: APPROVED_ORGANIZATION_ID,
      name: "Approved Organization",
      description: "Approved organization",
      city: "Innsbruck",
      federalState: "tirol",
      ownerId: "organization-owner",
      adminIds: ["organization-admin"],
      moderatorIds: ["organization-moderator"],
      moderationStatus: "approved",
      createdAt: new Date("2026-08-01T10:00:00Z"),
      updatedAt: new Date("2026-08-01T10:00:00Z"),
    });

    await setDoc(
      doc(db, "organizations", REQUEST_ORGANIZATION_ID),
      organizationRequest(REQUEST_ORGANIZATION_ID)
    );
  });
}

describe("organization region scope updates", () => {
  test("request creation accepts only supported region scopes", async () => {
    const db = auth("request-submitter");
    const validId = "valid-region-request";
    const invalidId = "invalid-region-request";

    await assertSucceeds(setDoc(
      doc(db, "organizations", validId),
      organizationRequest(validId, "federalState")
    ));
    await assertFails(setDoc(
      doc(db, "organizations", invalidId),
      organizationRequest(invalidId, "europe")
    ));
  });

  test("organization owner and admin can persist a valid region scope", async () => {
    await assertSucceeds(updateDoc(
      doc(auth("organization-owner"), "organizations", APPROVED_ORGANIZATION_ID),
      {regionScope: "federalState"}
    ));
    await assertSucceeds(updateDoc(
      doc(auth("organization-admin"), "organizations", APPROVED_ORGANIZATION_ID),
      {regionScope: "austria"}
    ));
  });

  test("request submitter can persist a valid region scope", async () => {
    await assertSucceeds(updateDoc(
      doc(auth("request-submitter"), "organizations", REQUEST_ORGANIZATION_ID),
      {regionScope: "city"}
    ));
  });

  test("unsupported region scopes are rejected", async () => {
    await assertFails(updateDoc(
      doc(auth("organization-owner"), "organizations", APPROVED_ORGANIZATION_ID),
      {regionScope: "europe"}
    ));
    await assertFails(updateDoc(
      doc(auth("request-submitter"), "organizations", REQUEST_ORGANIZATION_ID),
      {regionScope: "europe"}
    ));
  });

  test("moderator and unrelated user cannot change organization region scope", async () => {
    await assertFails(updateDoc(
      doc(auth("organization-moderator"), "organizations", APPROVED_ORGANIZATION_ID),
      {regionScope: "federalState"}
    ));
    await assertFails(updateDoc(
      doc(auth("unrelated-user"), "organizations", APPROVED_ORGANIZATION_ID),
      {regionScope: "federalState"}
    ));
  });
});
