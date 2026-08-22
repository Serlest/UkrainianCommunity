import {countGuideAnalyticsMarkers} from "./removedGuideAuditMarkers.mjs";

const options = parseArguments(process.argv.slice(2));

if (!options.projectId) {
  throw new Error(
    "Missing Firebase project ID. Pass --project=<project-id>."
  );
}

const [appModule, firestoreModule, storageModule] = await Promise.all([
  import("firebase-admin/app"),
  import("firebase-admin/firestore"),
  import("firebase-admin/storage"),
]);
const { applicationDefault, initializeApp } = appModule;
const { getFirestore } = firestoreModule;
const { getStorage } = storageModule;

const app = initializeApp({
  credential: applicationDefault(),
  projectId: options.projectId,
  ...(options.storageBucket ? { storageBucket: options.storageBucket } : {}),
}, "removed-guide-data-audit");

const db = getFirestore(app);
const legacyUserData = await auditLegacyUserData();
const legacyFeaturedBanners = await auditLegacyFeaturedBanners();
const legacyFeaturedBannerAliases = await auditFeaturedBannerAliases();

const removableData = {
  guideNodes: await countQuery(db.collection("guideNodes")),
  guideMaterials: await countQuery(db.collection("guideMaterials")),
  guideMaterialBookmarks: legacyUserData.guideMaterialBookmarks,
  guideRecentViews: legacyUserData.guideRecentViews,
  ...legacyUserData.notifications,
  featuredBanners: legacyFeaturedBanners,
  guideBannerConfig: Number((await db.collection("appConfig").doc("guideBanner").get()).exists),
  users: legacyUserData.users,
  analytics: await countAnalyticsGuideMarkers(),
  storageGuideAssets: await auditStorageGuideAssets(legacyFeaturedBanners.documentIDs),
};

const retainedHistory = {
  systemLogs: await auditHistoricalSystemLogs(),
  auditLogs: await countQuery(
    db.collection("auditLogs").where(
      "actionType",
      "in",
      ["guideEditorAssigned", "guideEditorRemoved"]
    )
  ),
};

const migrationPrerequisites = {
  featuredBannerActionAliases: legacyFeaturedBannerAliases,
};

console.log(JSON.stringify({
  mode: "read-only",
  projectId: options.projectId,
  generatedAt: new Date().toISOString(),
  removableData,
  migrationPrerequisites,
  retainedHistory,
  notes: [
    "Counts can overlap when one notification or banner matches more than one criterion.",
    "Nested user checks include missing parent documents and read only the relevant subcollections and fields.",
    "Historical systemLogs and auditLogs are reported separately and must follow retention policy.",
    "This script performs no writes or deletes.",
  ],
}, null, 2));

async function countQuery(query) {
  const snapshot = await query.count().get();
  return snapshot.data().count;
}

async function auditLegacyFeaturedBanners() {
  const definitions = [
    ["actionType", db.collection("featuredBanners").where("actionType", "==", "guide")],
    ["targetType", db.collection("featuredBanners").where("targetType", "==", "guide")],
    ["visibleSections", db.collection("featuredBanners")
      .where("visibleSections", "array-contains", "guide")],
  ];
  const snapshots = await Promise.all(
    definitions.map(([, query]) => query.select().get())
  );
  const documentIDs = new Set();
  const matchedBy = {};

  snapshots.forEach((snapshot, index) => {
    const field = definitions[index][0];
    matchedBy[field] = snapshot.size;
    snapshot.docs.forEach((document) => documentIDs.add(document.id));
  });

  return {
    uniqueDocuments: documentIDs.size,
    matchedBy,
    documentIDs: Array.from(documentIDs).sort(),
  };
}

async function auditFeaturedBannerAliases() {
  const snapshot = await db.collection("featuredBanners")
    .where("actionType", "in", ["announcement", "emergency", "partner"])
    .select()
    .get();

  return {
    documents: snapshot.size,
    documentIDs: snapshot.docs.map((document) => document.id).sort(),
  };
}

async function auditHistoricalSystemLogs() {
  const definitions = {
    guideTarget: db.collection("systemLogs")
      .where("targetType", "in", ["guideArticle", "guideMaterial"]),
    guideOperation: db.collection("systemLogs")
      .where("operationName", "in", ["assignGuideEditor", "removeGuideEditor"]),
    guideActorRole: db.collection("systemLogs")
      .where("actorRole", "==", "guideEditor"),
  };
  const entries = await Promise.all(
    Object.entries(definitions).map(async ([name, query]) => [name, await countQuery(query)])
  );
  return Object.fromEntries(entries);
}

async function auditLegacyUserData() {
  const userReferences = await db.collection("users").listDocuments();
  const result = {
    guideMaterialBookmarks: 0,
    guideRecentViews: 0,
    notifications: emptyLegacyNotificationCounts(),
    users: { present: 0, enabled: 0 },
  };

  const batchSize = 10;
  for (let index = 0; index < userReferences.length; index += batchSize) {
    const batch = await Promise.all(
      userReferences
        .slice(index, index + batchSize)
        .map(auditLegacyUserReference)
    );

    for (const userResult of batch) {
      result.guideMaterialBookmarks += userResult.guideMaterialBookmarks;
      result.guideRecentViews += userResult.guideRecentViews;
      result.users.present += userResult.users.present;
      result.users.enabled += userResult.users.enabled;
      for (const key of Object.keys(result.notifications)) {
        result.notifications[key] += userResult.notifications[key];
      }
    }
  }

  return result;
}

async function auditLegacyUserReference(userReference) {
  const [userSnapshot, bookmarksSnapshot, recentViewsSnapshot, notificationsSnapshot] =
    await Promise.all([
      userReference.get(),
      userReference.collection("guideMaterialBookmarks").count().get(),
      userReference.collection("recentViews").select("itemType").get(),
      userReference
        .collection("notificationInbox")
        .select("type", "actionType", "sourceType")
        .get(),
    ]);

  const userData = userSnapshot.data();
  const notifications = emptyLegacyNotificationCounts();
  for (const document of notificationsSnapshot.docs) {
    if (document.get("type") === "guideMaterialUpdated") {
      notifications.notificationType += 1;
    }
    if (document.get("actionType") === "openGuideMaterial") {
      notifications.notificationActionMaterial += 1;
    }
    if (document.get("actionType") === "openGuideReport") {
      notifications.notificationActionReport += 1;
    }
    if (["guide", "guideMaterial", "guideReport"].includes(document.get("sourceType"))) {
      notifications.notificationSource += 1;
    }
  }

  return {
    guideMaterialBookmarks: bookmarksSnapshot.data().count,
    guideRecentViews: recentViewsSnapshot.docs.filter(
      (document) => document.get("itemType") === "guide"
    ).length,
    notifications,
    users: {
      present: Number(userData !== undefined && Object.hasOwn(userData, "canManageGuide")),
      enabled: Number(userData?.canManageGuide === true),
    },
  };
}

function emptyLegacyNotificationCounts() {
  return {
    notificationType: 0,
    notificationActionMaterial: 0,
    notificationActionReport: 0,
    notificationSource: 0,
  };
}

async function countAnalyticsGuideMarkers() {
  const collectionDefinitions = [
    { name: "analyticsDailyStats" },
    { name: "analyticsContentStats", nestedCollection: "items" },
    { name: "analyticsTopContent" },
    { name: "analyticsRegionStats" },
    { name: "analyticsOrganizationStats", nestedCollection: "organizations" },
  ];
  const result = {};

  for (const definition of collectionDefinitions) {
    const snapshot = await db.collection(definition.name).get();
    let documents = 0;
    let markers = 0;
    let nestedDocuments = 0;
    let nestedMarkers = 0;
    let untypedActiveRegionDocuments = 0;

    for (const document of snapshot.docs) {
      const data = document.data();
      const documentMarkers = countGuideAnalyticsMarkers(document.id)
        + countGuideAnalyticsMarkers(data);
      if (documentMarkers > 0) {
        documents += 1;
        markers += documentMarkers;
      }
      if (definition.name === "analyticsDailyStats"
        && isRecordWithKeys(data.activeRegionKeys)) {
        untypedActiveRegionDocuments += 1;
      }

      if (definition.nestedCollection) {
        const nestedSnapshot = await document.ref.collection(definition.nestedCollection).get();
        nestedSnapshot.docs.forEach((nestedDocument) => {
          const documentNestedMarkers = countGuideAnalyticsMarkers(nestedDocument.id)
            + countGuideAnalyticsMarkers(nestedDocument.data());
          if (documentNestedMarkers > 0) {
            nestedDocuments += 1;
            nestedMarkers += documentNestedMarkers;
          }
        });
      }
    }

    result[definition.name] = {
      documents,
      markers,
      nestedDocuments,
      nestedMarkers,
      ...(definition.name === "analyticsDailyStats"
        ? { untypedActiveRegionDocuments }
        : {}),
    };
  }

  return result;
}

function isRecordWithKeys(value) {
  return value !== null
    && typeof value === "object"
    && !Array.isArray(value)
    && Object.keys(value).length > 0;
}

async function auditStorageGuideAssets(legacyBannerIDs) {
  if (!options.storageBucket) {
    return {
      checked: false,
      reason: "Pass --storage-bucket=<bucket-name> to include Storage inventory.",
    };
  }

  const bucket = getStorage(app).bucket(options.storageBucket);
  const objectPaths = [
    "appConfig/guideBanner/banner.jpg",
    ...legacyBannerIDs.map((bannerID) => `featuredBanners/${bannerID}/hero.jpg`),
  ];
  const existingObjectPaths = [];
  const batchSize = 20;
  for (let index = 0; index < objectPaths.length; index += batchSize) {
    const batchPaths = objectPaths.slice(index, index + batchSize);
    const results = await Promise.all(
      batchPaths.map(async (objectPath) => ({
        objectPath,
        exists: (await bucket.file(objectPath).exists())[0],
      }))
    );
    existingObjectPaths.push(
      ...results.filter((result) => result.exists).map((result) => result.objectPath)
    );
  }

  return {
    checked: true,
    checkedObjectCount: objectPaths.length,
    existingObjectPaths,
  };
}

function parseArguments(argumentsList) {
  const parsed = {
    projectId: undefined,
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET,
  };

  for (const argument of argumentsList) {
    if (argument === "--execute" || argument.startsWith("--confirm=")) {
      throw new Error("This inventory script is read-only and does not support execution.");
    }

    if (argument.startsWith("--project=")) {
      parsed.projectId = requiredOptionValue(argument, "--project=");
      continue;
    }

    if (argument.startsWith("--storage-bucket=")) {
      parsed.storageBucket = requiredOptionValue(argument, "--storage-bucket=");
      continue;
    }

    throw new Error(`Unsupported argument: ${argument}`);
  }

  return parsed;
}

function requiredOptionValue(argument, prefix) {
  const value = argument.slice(prefix.length).trim();
  if (!value) {
    throw new Error(`Missing value for ${prefix.slice(0, -1)}.`);
  }
  return value;
}
