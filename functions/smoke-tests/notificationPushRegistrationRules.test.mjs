import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, serverTimestamp, setDoc } from "firebase/firestore";
import { readFileSync } from "node:fs";

const PROJECT_ID = "ukrainian-community-push-registration-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const FIREBASE_INSTALLATION_ID = "a123456789012345678901";

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
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users", "verified-user"), {
      id: "verified-user",
      accountStatus: "active",
      blockState: "active",
    });
  });
});

after(async () => {
  await testEnv?.cleanup();
});

function authenticated(emailVerified = true) {
  return testEnv.authenticatedContext("verified-user", {
    email: "verified-user@example.com",
    email_verified: emailVerified,
  }).firestore();
}

function registration(overrides = {}) {
  return {
    id: "registration-doc",
    token: "registration-identifier",
    platform: "ios",
    appVersion: "1.0",
    updatedAt: serverTimestamp(),
    ...overrides,
  };
}

describe("push registration schema compatibility", () => {
  test("accepts legacy token documents without a registration type", async () => {
    const db = authenticated();
    await assertSucceeds(setDoc(
      doc(db, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration()
    ));
  });

  test("accepts explicit Firebase Installation ID registrations", async () => {
    const db = authenticated();
    await assertSucceeds(setDoc(
      doc(db, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({
        token: FIREBASE_INSTALLATION_ID,
        registrationType: "fid",
      })
    ));
  });

  test("accepts an explicit legacy token during the migration", async () => {
    const db = authenticated();
    await assertSucceeds(setDoc(
      doc(db, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({ registrationType: "token" })
    ));
  });

  test("rejects malformed Firebase Installation IDs", async () => {
    const db = authenticated();
    await assertFails(setDoc(
      doc(db, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({ token: "too-short", registrationType: "fid" })
    ));
    await assertFails(setDoc(
      doc(db, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({ token: "a12345678901234567890!", registrationType: "fid" })
    ));
  });

  test("rejects unknown registration types and unverified writers", async () => {
    const verifiedDb = authenticated();
    await assertFails(setDoc(
      doc(verifiedDb, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({ registrationType: "future-type" })
    ));

    const unverifiedDb = authenticated(false);
    await assertFails(setDoc(
      doc(unverifiedDb, "users", "verified-user", "notificationPushTokens", "registration-doc"),
      registration({ registrationType: "fid" })
    ));
  });

  test("keeps registration documents private to server delivery code", async () => {
    const db = authenticated();
    const reference = doc(
      db,
      "users",
      "verified-user",
      "notificationPushTokens",
      "registration-doc"
    );
    await assertSucceeds(setDoc(reference, registration({
      token: FIREBASE_INSTALLATION_ID,
      registrationType: "fid",
    })));
    await assertFails(getDoc(reference));
    assert.ok(true);
  });
});


test("delivery receipts are server-only, including for the inbox owner", async () => {
  const db = authenticated();
  const ref = doc(db, "users", "verified-user", "notificationInbox", "notice", "privateDelivery", "push");
  await assertFails(getDoc(ref));
  await assertFails(setDoc(ref, {status: "complete"}));
});
