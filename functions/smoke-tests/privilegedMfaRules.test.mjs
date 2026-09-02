import {after, before, test} from "node:test";
import {readFileSync} from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";

const PROJECT_ID = "demo-ukrainian-community-rules";
const FIRESTORE_RULES_PATH = "../../Firebase/firestore.rules";

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL(FIRESTORE_RULES_PATH, import.meta.url), "utf8"),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users", "owner"), user("owner", false)),
      setDoc(doc(db, "users", "protected-owner"), {
        ...profileUser("protected-owner"),
        globalRole: "owner",
        requiresMultiFactorAuth: true,
      }),
      setDoc(doc(db, "users", "protected-user"), {
        ...user("protected-user", true),
        globalRole: "user",
      }),
      setDoc(doc(db, "users", "profile-user"), profileUser("profile-user")),
      setDoc(doc(db, "users", "owner", "contentPlanningDrafts", "draft"), {id: "draft"}),
      setDoc(doc(
        db,
        "users",
        "protected-owner",
        "contentPlanningDrafts",
        "draft",
      ), {id: "draft"}),
    ]);
  });
});

after(async () => {
  await testEnv?.cleanup();
});

function user(uid, requiresMultiFactorAuth) {
  return {
    id: uid,
    globalRole: "owner",
    accountStatus: "active",
    blockState: "active",
    requiresMultiFactorAuth,
  };
}

function profileUser(uid) {
  return {
    ...user(uid, false),
    fullName: "Profile User",
    displayName: "Profile User",
    city: "Vienna",
    email: `${uid}@example.com`,
    bio: "",
    selectedFederalState: "Vienna",
    isBlocked: false,
    warningCount: 0,
    communityMemberships: [],
    createdAt: new Date("2026-09-01T10:00:00Z"),
    updatedAt: new Date("2026-09-01T10:00:00Z"),
  };
}

function firestore(uid, usesTOTP = false) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
    ...(usesTOTP ? {firebase: {sign_in_second_factor: "totp"}} : {}),
  }).firestore();
}

test("keeps existing privileged accounts working until their rollout flag is set", async () => {
  await assertSucceeds(getDoc(doc(
    firestore("owner"),
    "users",
    "owner",
    "contentPlanningDrafts",
    "draft",
  )));
});

test("requires TOTP for an opted-in owner and accepts a TOTP-authenticated token", async () => {
  await assertFails(getDoc(doc(
    firestore("protected-owner"),
    "users",
    "protected-owner",
    "contentPlanningDrafts",
    "draft",
  )));
  await assertSucceeds(getDoc(doc(
    firestore("protected-owner", true),
    "users",
    "protected-owner",
    "contentPlanningDrafts",
    "draft",
  )));
});

test("does not let a client disable its own MFA requirement", async () => {
  await assertFails(updateDoc(
    doc(firestore("protected-owner", true), "users", "protected-owner"),
    {requiresMultiFactorAuth: false},
  ));
});

test("preserves normal self-service profile updates", async () => {
  await assertSucceeds(updateDoc(
    doc(firestore("profile-user"), "users", "profile-user"),
    {
      displayName: "Updated Profile User",
      updatedAt: new Date("2026-09-02T10:00:00Z"),
    },
  ));
});

test("ignores a stale requirement flag on a non-privileged account", async () => {
  await assertSucceeds(getDoc(doc(
    firestore("protected-user"),
    "users",
    "protected-user",
  )));
});
