import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-organization-creation-proof-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: readFileSync(new URL(RULES_PATH, import.meta.url), "utf8")},
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "creator"), {
      id: "creator",
      globalRole: "user",
      accountStatus: "active",
      blockState: "active",
    });
    await setDoc(doc(db, "legalDocuments", "organizationRules"), {
      activeVersion: "2026.10",
      requiresAcceptance: true,
    });
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

function creatorDb() {
  return testEnv.authenticatedContext("creator", {
    email: "creator@example.com",
    email_verified: true,
  }).firestore();
}

function request(id, name = "Ukrainian Shop") {
  return {
    id,
    name,
    description: "A verified organization request",
    city: "Innsbruck",
    federalState: "tirol",
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
    submittedByUserId: "creator",
    submittedAt: new Date(),
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

async function seedProof(id, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "organizationCreationProofs", id), {
      organizationId: id,
      organizationName: "Ukrainian Shop",
      userId: "creator",
      documentType: "organizationRules",
      version: "2026.10",
      acceptedAt: new Date(),
      expiresAt: new Date("2099-01-01T00:00:00Z"),
      ...overrides,
    });
  });
}

describe("organization creation rules evidence", () => {
  test("requires a current organization-bound proof", async () => {
    const db = creatorDb();
    await assertFails(setDoc(doc(db, "organizations", "missing-proof"), request("missing-proof")));

    await seedProof("wrong-version", {version: "2026.9"});
    await assertFails(setDoc(doc(db, "organizations", "wrong-version"), request("wrong-version")));

    await seedProof("wrong-name");
    await assertFails(setDoc(
      doc(db, "organizations", "wrong-name"),
      request("wrong-name", "Changed name")
    ));

    await seedProof("valid-proof");
    await assertSucceeds(setDoc(doc(db, "organizations", "valid-proof"), request("valid-proof")));
  });

  test("does not expose creation proofs to clients", async () => {
    await seedProof("private-proof");
    await assertFails(getDoc(doc(creatorDb(), "organizationCreationProofs", "private-proof")));
  });
});
