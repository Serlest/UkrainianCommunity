import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-removed-guide-rules";
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
  await seedLegacyGuideData();
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

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
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

async function seedLegacyGuideData() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await Promise.all([
      setDoc(doc(db, "users", "owner"), user("owner", {globalRole: "owner"})),
      setDoc(doc(db, "users", "former-editor"), user("former-editor", {
        canManageGuide: true,
      })),
      setDoc(doc(db, "users", "normal-user"), user("normal-user")),
      setDoc(doc(db, "guideNodes", "legacy-node"), {
        id: "legacy-node",
        title: "Legacy node",
        moderationStatus: "approved",
        publishedAt: new Date("2026-06-01T10:00:00Z"),
      }),
      setDoc(doc(db, "guideMaterials", "legacy-material"), {
        id: "legacy-material",
        title: "Legacy material",
        moderationStatus: "approved",
        publishedAt: new Date("2026-06-01T10:00:00Z"),
      }),
      setDoc(doc(db, "appConfig", "guideBanner"), {
        imageURL: "https://example.com/legacy-guide-banner.jpg",
      }),
      setDoc(doc(db, "featuredBanners", "legacy-guide-banner"), featuredBanner(
        "legacy-guide-banner",
        {
          actionType: "guide",
          actionTargetID: "legacy-material",
          visibleSections: ["guide"],
        },
      )),
      setDoc(doc(db, "featuredBanners", "legacy-guide-delete"), featuredBanner(
        "legacy-guide-delete",
        {
          actionType: "guide",
          actionTargetID: "legacy-material",
          visibleSections: ["guide"],
        },
      )),
      setDoc(doc(db, "featuredBanners", "legacy-mixed-sections"), featuredBanner(
        "legacy-mixed-sections",
        {visibleSections: ["home", "guide"]},
      )),
      setDoc(doc(db, "featuredBanners", "malformed-deactivate"), {
        imageURL: "https://example.com/malformed-deactivate.jpg",
        actionType: "none",
        regionScope: "allAustria",
        visibleSections: ["home"],
        displayDurationSeconds: 6,
        priority: 1,
        isActive: true,
        updatedAt: new Date("2026-08-22T10:00:00Z"),
      }),
      setDoc(doc(db, "featuredBanners", "malformed-repair"), {
        ...featuredBanner("wrong-document-id"),
        createdBy: "",
      }),
    ]);
  });
}

function featuredBanner(id, overrides = {}) {
  return {
    id,
    imageURL: "https://example.com/banner.jpg",
    actionType: "none",
    regionScope: "allAustria",
    visibleSections: ["home"],
    displayDurationSeconds: 6,
    priority: 10,
    isActive: true,
    createdAt: new Date("2026-08-22T10:00:00Z"),
    updatedAt: new Date("2026-08-22T10:00:00Z"),
    createdBy: "owner",
    ...overrides,
  };
}

function profileBootstrap(uid) {
  return {
    id: uid,
    fullName: "New User",
    displayName: "New User",
    city: "Vienna",
    email: `${uid}@example.com`,
    bio: "",
    isBlocked: false,
    blockState: "active",
    globalRole: "user",
    selectedFederalState: "Vienna",
    accountStatus: "active",
    warningCount: 0,
    acceptedTermsAt: new Date("2026-08-22T10:00:00Z"),
    acceptedPrivacyAt: new Date("2026-08-22T10:00:00Z"),
    acceptedTermsVersion: "1",
    acceptedPrivacyVersion: "1",
    termsVersion: "1",
    privacyVersion: "1",
    communityMemberships: [],
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };
}

function guideAuditLog(id, targetType) {
  return {
    id,
    createdAt: new Date("2026-08-22T10:00:00Z"),
    category: "audit",
    severity: "info",
    severityRank: 1,
    eventType: "contentCreated",
    actorUserId: "owner",
    actorRole: "owner",
    targetType,
    targetId: "legacy-material",
    targetTitle: "Legacy material",
    summary: "Legacy Guide material created",
    moduleName: "Guide",
    operationName: "createGuideMaterial",
    outcome: "success",
    isReviewed: false,
    metadata: {},
    retentionPolicy: "normalAudit",
  };
}

describe("removed Guide collections", () => {
  test("legacy published data is denied to guests, users, former editors, and owners", async () => {
    const contexts = [
      unauthenticated(),
      auth("normal-user"),
      auth("former-editor"),
      auth("owner"),
    ];

    for (const db of contexts) {
      await assertFails(getDoc(doc(db, "guideNodes", "legacy-node")));
      await assertFails(getDoc(doc(db, "guideMaterials", "legacy-material")));
    }
  });

  test("retired editor flag and owner role cannot write legacy collections", async () => {
    for (const db of [auth("former-editor"), auth("owner")]) {
      await assertFails(setDoc(doc(db, "guideNodes", "new-node"), {
        id: "new-node",
        title: "New node",
      }));
      await assertFails(updateDoc(doc(db, "guideMaterials", "legacy-material"), {
        title: "Changed legacy material",
      }));
      await assertFails(deleteDoc(doc(db, "guideNodes", "legacy-node")));
    }
  });
});

describe("removed Guide interaction values", () => {
  test("Guide bookmarks and recent views are rejected", async () => {
    const db = auth("former-editor");

    await assertFails(setDoc(
      doc(db, "users", "former-editor", "guideMaterialBookmarks", "legacy-material"),
      {
        id: "legacy-material",
        materialId: "legacy-material",
        userId: "former-editor",
      },
    ));

    await assertFails(setDoc(
      doc(db, "users", "former-editor", "recentViews", "guide_legacy-material"),
      {
        itemId: "legacy-material",
        itemType: "guide",
        title: "Legacy material",
        viewedAt: new Date("2026-08-22T10:00:00Z"),
      },
    ));
  });

  test("new user bootstrap no longer requires the retired capability field", async () => {
    const db = auth("new-user");
    await assertSucceeds(setDoc(doc(db, "users", "new-user"), profileBootstrap("new-user")));
  });

  test("new user bootstrap rejects the retired capability field for every value", async () => {
    for (const canManageGuide of [false, true]) {
      const uid = canManageGuide ? "legacy-true-user" : "legacy-false-user";
      const db = auth(uid);

      await assertFails(setDoc(doc(db, "users", uid), {
        ...profileBootstrap(uid),
        canManageGuide,
      }));
    }
  });
});

describe("removed Guide management values", () => {
  test("legacy Guide banners are hidden from clients but remain visible to the owner", async () => {
    const bannerPath = ["featuredBanners", "legacy-guide-banner"];

    await assertFails(getDoc(doc(unauthenticated(), ...bannerPath)));
    await assertFails(getDoc(doc(auth("normal-user"), ...bannerPath)));
    await assertSucceeds(getDoc(doc(auth("owner"), ...bannerPath)));
  });

  test("a supported banner remains readable while its retired section is awaiting migration", async () => {
    const bannerPath = ["featuredBanners", "legacy-mixed-sections"];

    await assertSucceeds(getDoc(doc(unauthenticated(), ...bannerPath)));
    await assertSucceeds(getDoc(doc(auth("normal-user"), ...bannerPath)));
  });

  test("the public repository query returns supported Home banners without legacy actions", async () => {
    const publicQuery = query(
      collection(unauthenticated(), "featuredBanners"),
      where("isActive", "==", true),
      where("actionType", "in", ["none", "news", "event", "organization", "externalURL"]),
      where("visibleSections", "array-contains", "home"),
    );

    const snapshot = await assertSucceeds(getDocs(publicQuery));
    const ids = snapshot.docs.map((document) => document.id);
    if (!ids.includes("legacy-mixed-sections") || ids.includes("legacy-guide-banner")) {
      throw new Error(`Unexpected public featured-banner query result: ${ids.join(", ")}`);
    }
  });

  test("Guide app configuration and featured-banner values are rejected", async () => {
    const db = auth("owner");

    await assertFails(getDoc(doc(db, "appConfig", "guideBanner")));
    await assertFails(setDoc(doc(db, "appConfig", "guideBanner"), {
      imageURL: "https://example.com/new-guide-banner.jpg",
    }));
    await assertFails(setDoc(
      doc(db, "featuredBanners", "guide-action"),
      featuredBanner("guide-action", {
        actionType: "guide",
        actionTargetID: "legacy-material",
      }),
    ));
    await assertFails(setDoc(
      doc(db, "featuredBanners", "guide-section"),
      featuredBanner("guide-section", {visibleSections: ["guide"]}),
    ));
  });

  test("owner can deactivate, migrate, and reactivate a legacy Guide banner", async () => {
    const db = auth("owner");
    const bannerRef = doc(db, "featuredBanners", "legacy-guide-banner");

    await assertSucceeds(updateDoc(bannerRef, {
      isActive: false,
      updatedAt: new Date("2026-08-22T11:00:00Z"),
      updatedBy: "owner",
    }));

    await assertFails(updateDoc(bannerRef, {
      isActive: true,
      updatedAt: new Date("2026-08-22T11:02:00Z"),
      updatedBy: "owner",
    }));

    await assertSucceeds(updateDoc(bannerRef, {
      actionType: "none",
      visibleSections: ["home"],
      updatedAt: new Date("2026-08-22T11:10:00Z"),
      updatedBy: "owner",
    }));

    await assertSucceeds(updateDoc(bannerRef, {
      isActive: true,
      updatedAt: new Date("2026-08-22T11:12:00Z"),
      updatedBy: "owner",
    }));

    await assertSucceeds(deleteDoc(
      doc(db, "featuredBanners", "legacy-guide-delete"),
    ));
  });

  test("owner can deactivate and fully repair malformed banner documents", async () => {
    const db = auth("owner");
    const deactivateRef = doc(db, "featuredBanners", "malformed-deactivate");
    const repairRef = doc(db, "featuredBanners", "malformed-repair");

    await assertSucceeds(updateDoc(deactivateRef, {
      isActive: false,
      updatedAt: new Date("2026-08-22T11:30:00Z"),
      updatedBy: "owner",
    }));

    await assertSucceeds(setDoc(
      repairRef,
      featuredBanner("malformed-repair", {
        updatedAt: new Date("2026-08-22T11:35:00Z"),
        updatedBy: "owner",
      }),
    ));

    await assertSucceeds(getDoc(doc(unauthenticated(), "featuredBanners", "malformed-repair")));
  });

  test("non-owners cannot migrate or delete legacy featured banners", async () => {
    const db = auth("normal-user");
    const bannerRef = doc(db, "featuredBanners", "legacy-guide-delete");

    await assertFails(updateDoc(bannerRef, {
      actionType: "none",
      visibleSections: ["home"],
      updatedAt: new Date("2026-08-22T11:20:00Z"),
      updatedBy: "normal-user",
    }));
    await assertFails(deleteDoc(bannerRef));
  });

  test("clients cannot create new system logs with retired Guide target types", async () => {
    const db = auth("owner");

    for (const targetType of ["guideArticle", "guideMaterial"]) {
      const id = `guide-audit-${targetType}`;
      await assertFails(setDoc(
        doc(db, "systemLogs", id),
        guideAuditLog(id, targetType),
      ));
    }
  });
});
