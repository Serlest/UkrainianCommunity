import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc} from "firebase/firestore";
import {
  deleteObject,
  getBytes,
  ref,
  uploadBytes,
} from "firebase/storage";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-storage-rules";
const FIRESTORE_RULES_PATH = "../../Firebase/firestore.rules";
const STORAGE_RULES_PATH = "../../Firebase/storage.rules";
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL(FIRESTORE_RULES_PATH, import.meta.url), "utf8"),
    },
    storage: {
      rules: readFileSync(new URL(STORAGE_RULES_PATH, import.meta.url), "utf8"),
    },
  });

  await seedFirestore();
});

beforeEach(async () => {
  await testEnv.clearStorage();
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function storage(uid, emailVerified = true) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
  }).storage();
}

function guestStorage() {
  return testEnv.unauthenticatedContext().storage();
}

function imageUpload(storageInstance, path, options = {}) {
  const {
    bytes = JPEG,
    contentType = "image/jpeg",
  } = options;

  return uploadBytes(ref(storageInstance, path), bytes, {contentType});
}

async function seedFirestore() {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await Promise.all([
      setDoc(doc(db, "users", "owner"), user("owner", {globalRole: "owner"})),
      setDoc(doc(db, "users", "blocked-owner"), user("blocked-owner", {
        globalRole: "owner",
        accountStatus: "suspended",
        blockState: "suspended",
      })),
      setDoc(doc(db, "users", "org-owner"), user("org-owner")),
      setDoc(doc(db, "users", "org-admin"), user("org-admin")),
      setDoc(doc(db, "users", "org-moderator"), user("org-moderator")),
      setDoc(doc(db, "users", "requester"), user("requester")),
      setDoc(doc(db, "users", "outsider"), user("outsider")),
      setDoc(doc(db, "users", "profile-user"), user("profile-user")),
      setDoc(doc(db, "organizations", "approved-org"), {
        id: "approved-org",
        ownerId: "org-owner",
        adminIds: ["org-admin"],
        moderatorIds: ["org-moderator"],
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "organizations", "pending-org"), {
        id: "pending-org",
        ownerId: "",
        adminIds: [],
        moderatorIds: [],
        submittedByUserId: "requester",
        moderationStatus: "pendingReview",
      }),
      setDoc(doc(db, "news", "org-news"), {
        id: "org-news",
        sourceType: "organization",
        organizationId: "approved-org",
      }),
      setDoc(doc(db, "events", "org-event"), {
        id: "org-event",
        sourceType: "organization",
        organizationId: "approved-org",
      }),
    ]);
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

describe("Storage upload validation", () => {
  test("accepts JPEG below the path limit and rejects unsafe content", async () => {
    const ownerStorage = storage("owner");

    await assertSucceeds(imageUpload(ownerStorage, "featuredBanners/banner-1/hero.jpg"));
    await assertFails(imageUpload(ownerStorage, "featuredBanners/banner-2/hero.jpg", {
      contentType: "image/svg+xml",
    }));
    await assertFails(imageUpload(ownerStorage, "featuredBanners/banner-3/hero.jpg", {
      bytes: new Uint8Array(5 * 1024 * 1024),
    }));
    await assertFails(imageUpload(ownerStorage, "news/org-news/cover.jpg", {
      bytes: new Uint8Array(3 * 1024 * 1024),
    }));
  });

  test("does not let the news wildcard bypass cover validation", async () => {
    const ownerStorage = storage("owner");

    await assertFails(imageUpload(ownerStorage, "news/org-news/cover.jpg", {
      contentType: "image/svg+xml",
    }));
    await assertFails(imageUpload(ownerStorage, "news/arbitrary/file.jpg"));
  });
});

describe("account state enforcement", () => {
  test("requires verified email for privileged and self uploads", async () => {
    await assertFails(imageUpload(storage("owner", false), "appConfig/homeBanner/banner.jpg"));
    await assertFails(imageUpload(
      storage("profile-user", false),
      "profileImages/profile-user/avatar.jpg",
    ));
  });

  test("rejects blocked users even when a privileged role remains in Firestore", async () => {
    await assertFails(imageUpload(
      storage("blocked-owner"),
      "appConfig/homeBanner/banner.jpg",
    ));
  });
});

describe("organization media permissions", () => {
  test("allows active organization roles to manage expected JPEG paths", async () => {
    await assertSucceeds(imageUpload(
      storage("org-owner"),
      "organizations/approved-org/logo.jpg",
    ));
    await assertSucceeds(imageUpload(
      storage("org-admin"),
      "organizations/approved-org/draftUploads/news/org-news_cover.jpg",
    ));
    await assertSucceeds(imageUpload(
      storage("org-moderator"),
      "organizations/approved-org/photos/photo-1.jpg",
    ));
  });

  test("rejects outsiders and malformed draft file names", async () => {
    await assertFails(imageUpload(
      storage("outsider"),
      "organizations/approved-org/logo.jpg",
    ));
    await assertFails(imageUpload(
      storage("org-owner"),
      "organizations/approved-org/draftUploads/news/not-a-cover.jpg",
    ));
  });

  test("limits request creators to the pending organization logo", async () => {
    await assertSucceeds(imageUpload(
      storage("requester"),
      "organizations/pending-org/logo.jpg",
    ));
    await assertFails(imageUpload(
      storage("requester"),
      "organizations/pending-org/photos/photo-1.jpg",
    ));
  });

  test("allows organization roles to manage linked news and event covers", async () => {
    await assertSucceeds(imageUpload(storage("org-moderator"), "news/org-news/cover.jpg"));
    await assertSucceeds(imageUpload(storage("org-admin"), "events/org-event/cover.jpg"));
    await assertFails(imageUpload(storage("outsider"), "news/org-news/cover.jpg"));
    await assertFails(imageUpload(storage("outsider"), "events/org-event/cover.jpg"));
  });
});

describe("profile and public read boundaries", () => {
  test("allows only the verified user or owner to manage the fixed avatar path", async () => {
    const profileStorage = storage("profile-user");

    await assertSucceeds(imageUpload(profileStorage, "profileImages/profile-user/avatar.jpg"));
    await assertFails(imageUpload(profileStorage, "profileImages/outsider/avatar.jpg"));
    await assertFails(imageUpload(profileStorage, "profileImages/profile-user/extra.jpg"));
    await assertSucceeds(deleteObject(
      ref(profileStorage, "profileImages/profile-user/avatar.jpg"),
    ));
  });

  test("keeps intended public media readable and pending organization media private", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await imageUpload(context.storage(), "profileImages/profile-user/avatar.jpg");
      await imageUpload(context.storage(), "organizations/approved-org/logo.jpg");
      await imageUpload(context.storage(), "organizations/pending-org/logo.jpg");
    });

    const guest = guestStorage();
    await assertSucceeds(getBytes(ref(guest, "profileImages/profile-user/avatar.jpg")));
    await assertSucceeds(getBytes(ref(guest, "organizations/approved-org/logo.jpg")));
    await assertFails(getBytes(ref(guest, "organizations/pending-org/logo.jpg")));
  });

  test("denies unknown paths to every client", async () => {
    await assertFails(imageUpload(storage("owner"), "unknown/file.jpg"));
    await assertFails(imageUpload(storage("outsider"), "unknown/file.jpg"));
    await assertFails(imageUpload(guestStorage(), "unknown/file.jpg"));
  });
});
