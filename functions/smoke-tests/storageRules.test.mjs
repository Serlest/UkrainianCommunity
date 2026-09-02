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

const PROJECT_ID = "demo-ukrainian-community-rules";
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

function storage(uid, emailVerified = true, usesTOTP = false) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
    ...(usesTOTP ? {firebase: {sign_in_second_factor: "totp"}} : {}),
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
      setDoc(doc(db, "users", "protected-owner"), user("protected-owner", {
        globalRole: "owner",
        requiresMultiFactorAuth: true,
      })),
      setDoc(doc(db, "users", "app-admin"), user("app-admin", {globalRole: "admin"})),
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
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "events", "org-event"), {
        id: "org-event",
        sourceType: "organization",
        organizationId: "approved-org",
        moderationStatus: "approved",
      }),
      setDoc(doc(db, "news", "pending-news"), {
        id: "pending-news",
        sourceType: "organization",
        organizationId: "approved-org",
        moderationStatus: "pendingReview",
      }),
      setDoc(doc(db, "events", "pending-event"), {
        id: "pending-event",
        sourceType: "organization",
        organizationId: "approved-org",
        moderationStatus: "pendingReview",
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
    await assertSucceeds(imageUpload(
      ownerStorage,
      "featuredBanners/banner-1/hero-123e4567-e89b-12d3-a456-426614174000.jpg",
    ));
    await assertFails(imageUpload(ownerStorage, "featuredBanners/banner-1/random.jpg"));
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

describe("removed Guide storage paths", () => {
  test("denies the retired appConfig Guide banner path to every client", async () => {
    const path = "appConfig/guideBanner/banner.jpg";

    await assertFails(imageUpload(storage("owner"), path));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await imageUpload(context.storage(), path);
    });

    await assertFails(getBytes(ref(guestStorage(), path)));
    await assertFails(deleteObject(ref(storage("owner"), path)));
  });
});

describe("account state enforcement", () => {
  test("requires verified email for privileged and self uploads", async () => {
    await assertFails(imageUpload(
      storage("owner", false),
      "featuredBanners/banner-unverified/hero.jpg",
    ));
    await assertFails(imageUpload(
      storage("profile-user", false),
      "profileImages/profile-user/avatar.jpg",
    ));
  });

  test("rejects blocked users even when a privileged role remains in Firestore", async () => {
    await assertFails(imageUpload(
      storage("blocked-owner"),
      "featuredBanners/banner-blocked/hero.jpg",
    ));
  });

  test("requires a TOTP session only for opted-in privileged accounts", async () => {
    await assertFails(imageUpload(
      storage("protected-owner"),
      "featuredBanners/protected-owner/hero.jpg",
    ));
    await assertSucceeds(imageUpload(
      storage("protected-owner", true, true),
      "featuredBanners/protected-owner/hero.jpg",
    ));
    await assertSucceeds(imageUpload(
      storage("owner"),
      "featuredBanners/unprotected-owner/hero.jpg",
    ));
  });
});

describe("organization media permissions", () => {
  test("rejects logo uploads before the organization document exists", async () => {
    await assertFails(imageUpload(
      storage("requester"),
      "organizations/new-requester-org/logo.jpg",
    ));
    await assertFails(imageUpload(
      storage("app-admin"),
      "organizations/new-requester-org/logo.jpg",
    ));
    await assertFails(imageUpload(
      storage("requester"),
      "organizations/missing-proof/logo.jpg",
    ));
  });

  test("allows active organization roles to manage expected JPEG paths", async () => {
    await assertSucceeds(imageUpload(
      storage("org-owner"),
      "organizations/approved-org/logo.jpg",
    ));
    await assertSucceeds(imageUpload(
      storage("org-moderator"),
      "organizations/approved-org/photos/photo-1.jpg",
    ));
  });

  test("rejects outsiders and retired draft upload paths", async () => {
    await assertFails(imageUpload(
      storage("outsider"),
      "organizations/approved-org/logo.jpg",
    ));
    await assertFails(imageUpload(
      storage("org-owner"),
      "organizations/approved-org/draftUploads/news/org-news_cover.jpg",
    ));
    await assertFails(imageUpload(
      storage("org-admin"),
      "organizations/approved-org/draftUploads/events/org-event_cover.jpg",
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
    await assertFails(deleteObject(ref(storage("owner"), "news/org-news/cover.jpg")));
    await assertFails(deleteObject(ref(storage("org-owner"), "events/org-event/cover.jpg")));
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
      await imageUpload(context.storage(), "featuredBanners/banner-1/hero-version-1.jpg");
      await imageUpload(context.storage(), "featuredBanners/banner-1/private.jpg");
      await imageUpload(context.storage(), "news/org-news/cover.jpg");
      await imageUpload(context.storage(), "events/org-event/cover.jpg");
      await imageUpload(context.storage(), "news/pending-news/cover.jpg");
      await imageUpload(context.storage(), "events/pending-event/cover.jpg");
    });

    const guest = guestStorage();
    await assertSucceeds(getBytes(ref(guest, "profileImages/profile-user/avatar.jpg")));
    await assertSucceeds(getBytes(ref(guest, "organizations/approved-org/logo.jpg")));
    await assertSucceeds(getBytes(ref(guest, "featuredBanners/banner-1/hero-version-1.jpg")));
    await assertFails(getBytes(ref(guest, "featuredBanners/banner-1/private.jpg")));
    await assertFails(getBytes(ref(guest, "organizations/pending-org/logo.jpg")));
    await assertSucceeds(getBytes(ref(guest, "news/org-news/cover.jpg")));
    await assertSucceeds(getBytes(ref(guest, "events/org-event/cover.jpg")));
    await assertFails(getBytes(ref(guest, "news/pending-news/cover.jpg")));
    await assertFails(getBytes(ref(guest, "events/pending-event/cover.jpg")));
    await assertSucceeds(getBytes(ref(storage("app-admin"), "news/pending-news/cover.jpg")));
    await assertSucceeds(getBytes(ref(storage("app-admin"), "events/pending-event/cover.jpg")));
    await assertSucceeds(getBytes(ref(storage("org-owner"), "news/pending-news/cover.jpg")));
    await assertSucceeds(getBytes(ref(storage("org-admin"), "events/pending-event/cover.jpg")));
  });

  test("denies unknown paths to every client", async () => {
    await assertFails(imageUpload(storage("owner"), "unknown/file.jpg"));
    await assertFails(imageUpload(storage("outsider"), "unknown/file.jpg"));
    await assertFails(imageUpload(guestStorage(), "unknown/file.jpg"));
  });
});
