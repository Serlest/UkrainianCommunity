import {execFileSync} from "node:child_process";
import {createRequire} from "node:module";
import {join} from "node:path";

const args = new Set(process.argv.slice(2));
const projectArgument = process.argv.find((value) => value.startsWith("--project="));
const projectId = projectArgument?.slice("--project=".length);
const apply = args.has("--apply");

if (!projectId) {
  throw new Error("Use --project=<firebase-project-id>. Dry-run is the default; add --apply to write.");
}

const accessToken = await firebaseAccessToken();
const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`;
const users = await listDocuments("users", 2_000);
let unreadScanned = 0;
let changeCount = 0;

for (const userDocument of users) {
  const userId = userDocument.name.split("/").at(-1);
  const notifications = await listDocuments(`users/${userId}/notificationInbox`, 2_000);
  for (const document of notifications) {
    const data = decodeMap(document.fields ?? {});
    if (data.isRead !== false) continue;
    unreadScanned++;
    const documentId = document.name.split("/").at(-1);
    const patch = canonicalPatch(data, userId, documentId);
    if (Object.keys(patch).length === 0) continue;
    changeCount++;
    if (apply) await patchDocument(document.name, patch);
  }
}

console.log(JSON.stringify({
  projectId,
  usersScanned: users.length,
  unreadScanned,
  changes: changeCount,
  apply,
}));

function canonicalPatch(data, userId, documentId) {
  const archivedAt = data.archivedAt;
  const deletedAt = data.deletedAt;
  const isArchivedOrDeleted = archivedAt != null || deletedAt != null;
  const metadata = typeof data.metadata === "object" && data.metadata !== null
    ? data.metadata
    : {};
  const patch = {};
  if (!("archivedAt" in data)) patch.archivedAt = null;
  if (!("deletedAt" in data)) patch.deletedAt = null;
  if (!("readAt" in data)) patch.readAt = null;
  if (!("popupPresentedAt" in data)) patch.popupPresentedAt = null;
  if (!("expiresAt" in data)) patch.expiresAt = null;
  if (!("requiresPopup" in data)) patch.requiresPopup = false;
  if (!("recipientUserId" in data)) patch.recipientUserId = data.userId ?? userId;
  if (!("payload" in data)) patch.payload = metadata;

  // Diagnostic pushes intentionally have no durable inbox lifecycle. If an
  // older diagnostic document exists, keep it for audit evidence but exclude
  // it from unread counters and the visible inbox.
  if (documentId.startsWith("contentDraftPushDiagnostic_")) {
    const now = new Date().toISOString();
    patch.isRead = true;
    patch.readAt = now;
    patch.archivedAt = now;
  }

  if (isArchivedOrDeleted) {
    patch.isRead = true;
    patch.readAt = deletedAt ?? archivedAt ?? new Date().toISOString();
  }
  return patch;
}

async function firebaseAccessToken() {
  const output = execFileSync("firebase", ["login:list", "--json"], {encoding: "utf8"});
  const parsed = JSON.parse(output);
  const refreshToken = parsed?.result?.[0]?.tokens?.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length < 20) {
    throw new Error("Firebase CLI is not authenticated.");
  }
  const require = createRequire(import.meta.url);
  const globalNodeModules = execFileSync("npm", ["root", "--global"], {encoding: "utf8"}).trim();
  const auth = require(join(globalNodeModules, "firebase-tools/lib/auth.js"));
  const refreshed = await auth.getAccessToken(refreshToken, []);
  const token = refreshed?.access_token;
  if (typeof token !== "string" || token.length < 20) {
    throw new Error("Firebase CLI access token is unavailable.");
  }
  return token;
}

async function listDocuments(collectionPath, maximum) {
  const separator = collectionPath.lastIndexOf("/");
  const parent = separator < 0 ? "" : `/${collectionPath.slice(0, separator)}`;
  const collectionId = separator < 0 ? collectionPath : collectionPath.slice(separator + 1);
  let pageToken;
  const documents = [];
  do {
    const url = new URL(`${firestoreBase}/documents${parent}/${collectionId}`);
    url.searchParams.set("pageSize", String(Math.min(500, maximum - documents.length)));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await authorizedFetch(url);
    if (!response.ok) throw new Error(`Firestore list failed (${response.status}): ${await response.text()}`);
    const payload = await response.json();
    documents.push(...(payload.documents ?? []));
    pageToken = payload.nextPageToken;
  } while (pageToken && documents.length < maximum);
  return documents;
}

async function patchDocument(documentName, patch) {
  const url = new URL(`https://firestore.googleapis.com/v1/${documentName}`);
  for (const fieldPath of Object.keys(patch)) {
    url.searchParams.append("updateMask.fieldPaths", fieldPath);
  }
  const response = await authorizedFetch(url, {
    method: "PATCH",
    body: JSON.stringify({name: documentName, fields: encodeMap(patch)}),
  });
  if (!response.ok) throw new Error(`Firestore patch failed (${response.status}): ${await response.text()}`);
}

async function authorizedFetch(url, options = {}) {
  const headers = new Headers(options.headers ?? {});
  headers.set("Authorization", `Bearer ${accessToken}`);
  if (options.body) headers.set("Content-Type", "application/json");
  return fetch(url, {...options, headers});
}

function encodeMap(value) {
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encodeValue(item)]));
}

function encodeValue(value) {
  if (value === null || value === undefined) return {nullValue: null};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number") return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  if (typeof value === "string") {
    return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)
      ? {timestampValue: value}
      : {stringValue: value};
  }
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encodeValue)}};
  if (typeof value === "object") return {mapValue: {fields: encodeMap(value)}};
  throw new Error("Unsupported Firestore value.");
}

function decodeMap(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]));
}

function decodeValue(value) {
  if (!value) return undefined;
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeMap(value.mapValue.fields ?? {});
  return undefined;
}
