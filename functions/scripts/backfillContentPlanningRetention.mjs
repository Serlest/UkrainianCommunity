import {applicationDefault, deleteApp, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";

import {
  assertContentPlanningRetentionExpectations,
  classifyContentPlanningRetentionDraft,
  parseContentPlanningRetentionBackfillOptions,
  summarizeContentPlanningRetention,
} from "./contentPlanningRetentionBackfillCore.mjs";

const options = parseContentPlanningRetentionBackfillOptions(process.argv.slice(2));
const app = initializeApp(
  {credential: applicationDefault(), projectId: options.projectId},
  `content-planning-retention-${Date.now()}`
);

try {
  const database = getFirestore(app);
  const snapshot = await database.collectionGroup("contentPlanningDrafts").get();
  const classifications = snapshot.docs.map((document) => ({
    reference: document.ref,
    draft: {id: document.id, path: document.ref.path, data: document.data()},
    result: classifyContentPlanningRetentionDraft({
      id: document.id,
      path: document.ref.path,
      data: document.data(),
    }),
  }));
  const summary = summarizeContentPlanningRetention(classifications);
  assertContentPlanningRetentionExpectations(summary, options.expectations);

  if (options.apply) {
    await applyRetentionBackfill(database, classifications);
    await verifyReadBack(database, classifications);
  }

  console.log(JSON.stringify({
    projectId: options.projectId,
    mode: options.apply ? "apply" : "dry-run",
    summary,
    records: classifications.map(({draft, result}) => ({
      path: draft.path,
      status: result.status,
      category: result.category,
      reason: result.reason,
      retentionExpiresAt: result.retentionExpiresAtMilliseconds === undefined
        ? undefined
        : new Date(result.retentionExpiresAtMilliseconds).toISOString(),
      mediaCleanupStatus: result.mediaCleanupStatus,
    })),
  }, null, 2));
} finally {
  await deleteApp(app);
}

async function applyRetentionBackfill(database, classifications) {
  const updates = classifications.filter((item) => item.result.status === "update");
  for (const group of chunks(updates, 400)) {
    const batch = database.batch();
    for (const item of group) {
      const patch = {
        retentionExpiresAt: Timestamp.fromMillis(item.result.retentionExpiresAtMilliseconds),
        retentionPolicy: "contentPlanningReceipt6Months",
      };
      if (!nonEmptyString(item.draft.data.draftMediaCleanupStatus)) {
        patch.draftMediaCleanupStatus = item.result.mediaCleanupStatus;
        if (item.result.requestsMediaCleanup) {
          patch.draftMediaCleanupRequestedAt = FieldValue.serverTimestamp();
        }
      }
      batch.update(item.reference, patch);
    }
    await batch.commit();
  }
}

async function verifyReadBack(database, classifications) {
  const updates = classifications.filter((item) => item.result.status === "update");
  for (const group of chunks(updates, 100)) {
    const snapshots = await database.getAll(...group.map((item) => item.reference));
    for (let index = 0; index < snapshots.length; index += 1) {
      const snapshot = snapshots[index];
      const expected = group[index].result;
      const retentionExpiresAt = snapshot.get("retentionExpiresAt");
      const cleanupStatus = nonEmptyString(snapshot.get("draftMediaCleanupStatus"));
      if (!snapshot.exists || !(retentionExpiresAt instanceof Timestamp) ||
          retentionExpiresAt.toMillis() !== expected.retentionExpiresAtMilliseconds ||
          snapshot.get("retentionPolicy") !== "contentPlanningReceipt6Months" ||
          !cleanupStatus) {
        throw new Error(`Retention read-back failed for ${group[index].draft.path}.`);
      }
    }
  }
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function nonEmptyString(value) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}
