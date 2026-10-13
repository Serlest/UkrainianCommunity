/* global console, process */

import {documents, buildPayload, pathsFor} from "./seedLegalDocuments.mjs";
import {firebaseCliCredential} from "./firebaseCliCredential.mjs";

const projectId = "uac-android-test-20260903";
const root = `projects/${projectId}/databases/(default)/documents`;
const endpoint = `https://firestore.googleapis.com/v1/${root}`;
const mode = process.argv[2] ?? "--check";
if (!["--check", "--write"].includes(mode) || process.argv.length > 3) {
  throw new Error("Usage: node scripts/seedLegalDocumentsStaging.mjs [--check|--write]");
}

function firestoreValue(value) {
  if (value === null) return {nullValue: null};
  if (typeof value === "string") return {stringValue: value};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return {integerValue: String(value)};
  }
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (value && typeof value === "object") {
    return {mapValue: {fields: firestoreFields(value)}};
  }
  throw new Error("Unsupported legal document value");
}

function firestoreFields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [key, firestoreValue(value)]));
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  }
  return value;
}

function expectedDocuments() {
  return documents.flatMap((document) => {
    const {pointer, version} = buildPayload(document);
    const paths = pathsFor(document.type);
    const {updatedAt: pointerUpdated, publishedAt: pointerPublished, ...pointerFields} = pointer;
    const {createdAt: versionCreated, updatedAt: versionUpdated,
      publishedAt: versionPublished, ...versionFields} = version;
    if (!pointerUpdated || !pointerPublished || !versionCreated || !versionUpdated || !versionPublished) {
      throw new Error("Legal publication timestamps are missing");
    }
    return [
      {path: paths.pointer, fields: pointerFields,
        timestamps: ["updatedAt", "publishedAt"]},
      {path: paths.version, fields: versionFields,
        timestamps: ["createdAt", "updatedAt", "publishedAt"]},
    ];
  });
}

const credential = await firebaseCliCredential();
const token = (await credential.getAccessToken()).access_token;
const headers = {
  Authorization: `Bearer ${token}`,
  "x-goog-user-project": projectId,
  "Content-Type": "application/json",
};
async function getDocument(path) {
  const response = await fetch(`${endpoint}/${path}`, {headers});
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`Firestore read failed for ${path}: HTTP ${response.status}`);
  return response.json();
}

const expected = expectedDocuments();
const existing = await Promise.all(expected.map((item) => getDocument(item.path)));
const present = existing.filter(Boolean).length;
if (present > 0 && present !== expected.length) {
  throw new Error(`Partial staging legal publication: ${present}/${expected.length} documents. No write attempted.`);
}
if (present === 0 && mode === "--write") {
  const writes = expected.map((item) => ({
    update: {name: `${root}/${item.path}`, fields: firestoreFields(item.fields)},
    currentDocument: {exists: false},
    updateTransforms: item.timestamps.map((fieldPath) => ({fieldPath, setToServerValue: "REQUEST_TIME"})),
  }));
  const response = await fetch(`https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`, {
    method: "POST", headers, body: JSON.stringify({writes}),
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(`Staging legal publication failed: HTTP ${response.status} ${body.error?.message ?? ""}`);
  }
  console.log(`Published ${writes.length} legal documents atomically in ${projectId}.`);
} else if (present === 0) {
  console.log(`Staging has no legal documents. --write would create ${expected.length} documents.`);
  process.exit(0);
}

for (const item of expected) {
  const remote = await getDocument(item.path);
  if (!remote) throw new Error(`Missing staging legal document: ${item.path}`);
  const fields = firestoreFields(item.fields);
  for (const [key, value] of Object.entries(fields)) {
    if (JSON.stringify(canonical(remote.fields?.[key])) !== JSON.stringify(canonical(value))) {
      throw new Error(`Staging legal document differs: ${item.path}.${key}`);
    }
  }
  for (const field of item.timestamps) {
    if (!remote.fields?.[field]?.timestampValue) {
      throw new Error(`Missing server timestamp: ${item.path}.${field}`);
    }
  }
  console.log(`Verified ${item.path}${item.fields.contentHash ? ` (${item.fields.contentHash})` : ""}.`);
}
