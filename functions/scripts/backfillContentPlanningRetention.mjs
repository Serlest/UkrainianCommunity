import {
  assertContentPlanningRetentionExpectations,
  classifyContentPlanningRetentionDraft,
  parseContentPlanningRetentionBackfillOptions,
  summarizeContentPlanningRetention,
} from "./contentPlanningRetentionBackfillCore.mjs";
import {firebaseCliCredential} from "./firebaseCliCredential.mjs";
import {
  buildContentPlanningRetentionWrite,
  decodeFirestoreDocument,
  verifyContentPlanningRetentionReadBack,
} from "./contentPlanningRetentionRest.mjs";

const options = parseContentPlanningRetentionBackfillOptions(process.argv.slice(2));
const credential = await firebaseCliCredential();
const firestoreBase = `https://firestore.googleapis.com/v1/projects/${options.projectId}` +
  "/databases/(default)";

const documents = await listContentPlanningDrafts();
const classifications = documents.map((draft) => ({
  draft,
  result: classifyContentPlanningRetentionDraft({
    path: draft.path,
    data: draft.data,
  }),
}));
const summary = summarizeContentPlanningRetention(classifications);
assertContentPlanningRetentionExpectations(summary, options.expectations);

if (options.apply) {
  await applyRetentionBackfill(classifications);
  await verifyReadBack(classifications);
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

async function listContentPlanningDrafts() {
  const rows = await firestoreRequest("/documents:runQuery", {
    method: "POST",
    body: JSON.stringify({structuredQuery: {
      from: [{collectionId: "contentPlanningDrafts", allDescendants: true}],
    }}),
  });
  return rows.flatMap((row) => row.document
    ? [decodeFirestoreDocument(row.document)]
    : []);
}

async function applyRetentionBackfill(classifications) {
  const updates = classifications.filter((item) => item.result.status === "update");
  for (const group of chunks(updates, 400)) {
    await firestoreRequest("/documents:commit", {
      method: "POST",
      body: JSON.stringify({writes: group.map(buildContentPlanningRetentionWrite)}),
    });
  }
}

async function verifyReadBack(classifications) {
  const updates = classifications.filter((item) => item.result.status === "update");
  for (const group of chunks(updates, 20)) {
    const documents = await Promise.all(group.map((item) => firestoreRequest(
      documentRestPath(item.draft.name)
    )));
    for (let index = 0; index < documents.length; index += 1) {
      if (!verifyContentPlanningRetentionReadBack(documents[index], group[index].result)) {
        throw new Error(`Retention read-back failed for ${group[index].draft.path}.`);
      }
    }
  }
}

async function firestoreRequest(path, settings = {}) {
  const token = await credential.getAccessToken();
  const headers = new Headers(settings.headers ?? {});
  headers.set("Authorization", `Bearer ${token.access_token}`);
  if (settings.body) headers.set("Content-Type", "application/json");
  const response = await fetch(`${firestoreBase}${path}`, {...settings, headers});
  if (!response.ok) {
    throw new Error(`Firestore request failed (${response.status}): ${await response.text()}`);
  }
  return response.json();
}

function documentRestPath(documentName) {
  const expectedPrefix = `projects/${options.projectId}/databases/(default)/documents/`;
  if (typeof documentName !== "string" || !documentName.startsWith(expectedPrefix)) {
    throw new Error("Firestore returned a document outside the confirmed project.");
  }
  return `/documents/${documentName.slice(expectedPrefix.length)}`;
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}
