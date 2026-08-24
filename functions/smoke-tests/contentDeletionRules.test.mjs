import {after, before, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, Timestamp} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "demo-ukrainian-community-content-deletion";
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
      setDoc(doc(db, "users", "owner"), user("owner", "owner")),
      setDoc(doc(db, "users", "org-owner"), user("org-owner", "user")),
      setDoc(doc(db, "organizations", "organization-1"), {
        id: "organization-1",
        ownerId: "org-owner",
        adminIds: [],
        moderatorIds: [],
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "news", "news-1"), {
        id: "news-1",
        sourceType: "organization",
        organizationId: "organization-1",
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "events", "event-1"), {
        id: "event-1",
        sourceType: "organization",
        organizationId: "organization-1",
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "organizations", "organization-1", "photos", "photo-1"), {
        id: "photo-1",
        organizationId: "organization-1",
        imageURL: "https://example.com/photo-1.jpg",
        caption: null,
        uploadedBy: "org-owner",
        createdAt: Timestamp.now(),
        updatedAt: null,
      }),
    ]);
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function user(id, globalRole) {
  return {
    id,
    globalRole,
    accountStatus: "active",
    blockState: "active",
  };
}

function database(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  }).firestore();
}

describe("trusted content deletion boundary", () => {
  test("denies direct news and event deletion to organization owners", async () => {
    const db = database("org-owner");

    await assertFails(deleteDoc(doc(db, "news", "news-1")));
    await assertFails(deleteDoc(doc(db, "events", "event-1")));
  });

  test("denies direct content and organization deletion to the app owner", async () => {
    const db = database("owner");

    await assertFails(deleteDoc(doc(db, "news", "news-1")));
    await assertFails(deleteDoc(doc(db, "events", "event-1")));
    await assertFails(deleteDoc(doc(db, "organizations", "organization-1")));
  });

  test("keeps organization photo metadata readable but server-managed", async () => {
    const ownerDb = database("org-owner");
    const appOwnerDb = database("owner");
    const existingPhoto = doc(ownerDb, "organizations", "organization-1", "photos", "photo-1");
    const newPhoto = doc(ownerDb, "organizations", "organization-1", "photos", "photo-2");

    await assertSucceeds(getDoc(existingPhoto));
    await assertFails(setDoc(newPhoto, {
      id: "photo-2",
      organizationId: "organization-1",
      imageURL: "https://example.com/photo-2.jpg",
      caption: null,
      uploadedBy: "org-owner",
      createdAt: Timestamp.now(),
      updatedAt: null,
    }));
    await assertFails(deleteDoc(existingPhoto));
    await assertFails(deleteDoc(doc(
      appOwnerDb,
      "organizations",
      "organization-1",
      "photos",
      "photo-1"
    )));
  });
});
