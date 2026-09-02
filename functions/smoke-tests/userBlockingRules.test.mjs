import {after, before, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {collection, deleteDoc, doc, getDoc, getDocs, setDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "demo-ukrainian-community-user-blocking";
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
    await setDoc(
      doc(context.firestore(), "users", "user-1", "blockedUsers", "user-2"),
      blockedUser("user-2")
    );
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function database(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  }).firestore();
}

function blockedUser(targetUserId) {
  return {
    id: targetUserId,
    targetUserId,
    displayName: "Blocked user",
    avatarURL: null,
    blockedAt: new Date("2026-08-23T10:00:00Z"),
    updatedAt: new Date("2026-08-23T10:00:00Z"),
  };
}

describe("private server-owned user blocks", () => {
  test("organization blocks remain inaccessible to direct clients without changing existing Rules", async () => {
    for (const uid of ["user-1", "user-2"]) {
      const reference = doc(database(uid), "users", "user-1", "blockedOrganizations", "org-a");
      await assertFails(getDoc(reference));
      await assertFails(setDoc(reference, {organizationId: "org-a", name: "Org", blockedAt: new Date()}));
      await assertFails(deleteDoc(reference));
    }
  });
  test("owner can read their blocked users collection", async () => {
    const db = database("user-1");
    await assertSucceeds(getDoc(doc(db, "users", "user-1", "blockedUsers", "user-2")));
    await assertSucceeds(getDocs(collection(db, "users", "user-1", "blockedUsers")));
  });

  test("other users and guests cannot read block relationships", async () => {
    await assertFails(getDoc(doc(
      database("user-2"),
      "users",
      "user-1",
      "blockedUsers",
      "user-2"
    )));
    const guest = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(guest, "users", "user-1", "blockedUsers")));
  });

  test("clients cannot forge, update, or delete block relationships", async () => {
    const reference = doc(database("user-1"), "users", "user-1", "blockedUsers", "user-3");
    await assertFails(setDoc(reference, blockedUser("user-3")));
    await assertFails(deleteDoc(doc(
      database("user-1"),
      "users",
      "user-1",
      "blockedUsers",
      "user-2"
    )));
  });
});
