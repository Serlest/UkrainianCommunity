#!/usr/bin/env node

import {createHash, randomUUID} from "node:crypto";
import {execFileSync} from "node:child_process";
import {createRequire} from "node:module";
import {readFile} from "node:fs/promises";
import {extname, join, resolve} from "node:path";

const projectId = process.env.UAC_FIREBASE_PROJECT_ID ?? "ukrainiancommunity-dbd5f";
const storageBucket = process.env.UAC_FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`;
const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`;

const [command, argument] = process.argv.slice(2);
if (!command || !["list", "save"].includes(command)) {
  fail("Usage: node scripts/contentPlanningLocalBridge.mjs list|save [manifest.json]");
}

const accessToken = await firebaseAccessToken();
const owner = await resolveOwner();

if (command === "list") {
  const [drafts, news, events] = await Promise.all([
    listDocuments(`users/${owner.id}/contentPlanningDrafts`, 500),
    listDocuments("news", 500),
    listDocuments("events", 500),
  ]);
  console.log(JSON.stringify({
    owner: {id: owner.id, email: owner.email},
    drafts: drafts.map(contentSummary),
    news: news.map(contentSummary),
    events: events.map(contentSummary),
  }, null, 2));
  process.exit(0);
}

if (!argument) fail("The save command requires a manifest JSON path.");
const manifest = JSON.parse(await readFile(resolve(argument), "utf8"));
const items = Array.isArray(manifest) ? manifest : [manifest];
const results = [];
for (const item of items) results.push(await saveDraft(owner.id, item));
console.log(JSON.stringify({owner: {id: owner.id, email: owner.email}, results}, null, 2));

async function firebaseAccessToken() {
  const output = execFileSync("firebase", ["login:list", "--json"], {encoding: "utf8"});
  const parsed = JSON.parse(output);
  const refreshToken = parsed?.result?.[0]?.tokens?.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length < 20) fail("Firebase CLI is not authenticated.");
  const require = createRequire(import.meta.url);
  const globalNodeModules = execFileSync("npm", ["root", "--global"], {encoding: "utf8"}).trim();
  const auth = require(join(globalNodeModules, "firebase-tools/lib/auth.js"));
  const refreshed = await auth.getAccessToken(refreshToken, []);
  const token = refreshed?.access_token;
  if (typeof token !== "string" || token.length < 20) fail("Firebase CLI is not authenticated.");
  return token;
}

async function resolveOwner() {
  const response = await authorizedFetch(`${firestoreBase}/documents:runQuery`, {
    method: "POST",
    body: JSON.stringify({structuredQuery: {
      from: [{collectionId: "users"}],
      where: {fieldFilter: {
        field: {fieldPath: "globalRole"},
        op: "EQUAL",
        value: {stringValue: "owner"},
      }},
      limit: 2,
    }}),
  });
  const rows = await response.json();
  let documents = rows.flatMap((row) => row.document ? [row.document] : []);
  if (documents.length === 0) {
    const users = await listDocuments("users", 500);
    documents = users.filter((document) => {
      const role = decodeValue(document.fields?.globalRole) ?? decodeValue(document.fields?.role);
      return role === "owner" || role === "appOwner";
    });
  }
  if (documents.length !== 1) fail(`Expected exactly one app owner, found ${documents.length}.`);
  return {id: documents[0].name.split("/").at(-1), email: decodeValue(documents[0].fields?.email)};
}

async function listDocuments(collectionPath, pageSize) {
  const separator = collectionPath.lastIndexOf("/");
  const parent = separator < 0 ? "" : `/${collectionPath.slice(0, separator)}`;
  const collectionId = separator < 0 ? collectionPath : collectionPath.slice(separator + 1);
  let pageToken;
  const documents = [];
  do {
    const url = new URL(`${firestoreBase}/documents${parent}/${collectionId}`);
    url.searchParams.set("pageSize", String(Math.min(pageSize, 500)));
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await authorizedFetch(url);
    const payload = await response.json();
    documents.push(...(payload.documents ?? []));
    pageToken = payload.nextPageToken;
  } while (pageToken && documents.length < pageSize);
  return documents.slice(0, pageSize);
}

function contentSummary(document) {
  const fields = Object.fromEntries(Object.entries(document.fields ?? {}).map(([key, value]) => [key, decodeValue(value)]));
  const payload = fields.payload && typeof fields.payload === "object" ? fields.payload : {};
  return {
    id: document.name.split("/").at(-1),
    kind: fields.kind,
    state: fields.state ?? fields.moderationStatus,
    title: fields.title ?? payload.title,
    sourceURL: fields.sourceURL ?? payload.sourceInput,
    startDate: fields.startDate ?? payload.startDate,
  };
}

async function saveDraft(ownerUserId, item) {
  validateDraft(item);
  const draftId = createHash("sha256")
    .update(`${ownerUserId}:${item.idempotencyKey}`)
    .digest("hex").slice(0, 40);
  const documentName = `projects/${projectId}/databases/(default)/documents/users/${ownerUserId}/contentPlanningDrafts/${draftId}`;
  const existing = await fetch(`https://firestore.googleapis.com/v1/${documentName}`, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  if (existing.ok) return {draftId, created: false, title: item.payload.title};
  if (existing.status !== 404) throw new Error(`Draft lookup failed (${existing.status}).`);

  const generatedImage = item.imagePath
    ? await uploadGeneratedImage(ownerUserId, draftId, item.imagePath, item.imageAlternativeText)
    : item.generatedImage;
  const payload = {...item.payload};
  if (generatedImage?.url) {
    payload.generatedImageURL = generatedImage.url;
    if (item.kind === "news") {
      payload.imageAlternativeText ??= generatedImage.alternativeText ?? null;
      payload.imageCredit ??= generatedImage.credit ?? "Зображення створене ШІ";
    }
  }
  const now = new Date().toISOString();
  const state = item.state ?? ((item.missingFields?.length ?? 0) > 0 ? "needsAttention" : "readyForReview");
  const draftFields = {
    id: draftId,
    schemaVersion: 2,
    ownerUserId,
    kind: item.kind,
    state,
    title: item.payload.title,
    payload,
    sources: item.sources,
    verificationNotes: item.verificationNotes ?? [],
    missingFields: item.missingFields ?? [],
    createdAt: now,
    updatedAt: now,
    scheduledAt: payload.publicationMode === "scheduled" ? payload.scheduledAt ?? null : null,
    completedAt: null,
    failureMessage: null,
    generatedImage: generatedImage ?? null,
  };
  const notificationId = `contentDraftReady_${draftId}`;
  const notificationName = `projects/${projectId}/databases/(default)/documents/users/${ownerUserId}/notificationInbox/${notificationId}`;
  const notificationFields = {
    id: notificationId,
    userId: ownerUserId,
    type: "contentDraftReady",
    title: item.kind === "news" ? "Нова чернетка новини" : "Нова чернетка події",
    message: item.payload.title,
    severity: state === "needsAttention" ? "warning" : "info",
    actionType: "openContentPlanning",
    actionTargetId: draftId,
    sourceType: "contentDraft",
    sourceId: draftId,
    dedupeKey: `contentDraftReady:${draftId}`,
    isRead: false,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
    metadata: {kind: item.kind, state},
  };
  const response = await authorizedFetch(`${firestoreBase}/documents:commit`, {
    method: "POST",
    body: JSON.stringify({writes: [
      {update: {name: documentName, fields: encodeMap(draftFields)}, currentDocument: {exists: false}},
      {update: {name: notificationName, fields: encodeMap(notificationFields)}, currentDocument: {exists: false}},
    ]}),
  });
  if (!response.ok) throw new Error(`Draft commit failed (${response.status}): ${await response.text()}`);
  return {draftId, created: true, title: item.payload.title, generatedImage: Boolean(generatedImage)};
}

function validateDraft(item) {
  if (!item || !["news", "event"].includes(item.kind)) fail("Each draft requires kind news or event.");
  if (typeof item.idempotencyKey !== "string" || !item.idempotencyKey.trim()) fail("Each draft requires idempotencyKey.");
  if (!item.payload || typeof item.payload.title !== "string" || !item.payload.title.trim()) fail("Each draft requires payload.title.");
  if (!Array.isArray(item.sources) || item.sources.filter((source) => source.isPrimary).length !== 1) {
    fail("Each draft requires sources with exactly one primary source.");
  }
  if ((item.payload.additionalCategories?.length ?? 0) > 2) fail("additionalCategories supports at most two values.");
}

async function uploadGeneratedImage(ownerUserId, draftId, imagePath, alternativeText) {
  const absolutePath = resolve(imagePath);
  const bytes = await readFile(absolutePath);
  if (bytes.length > 15_000_000) fail(`Image is larger than 15 MB: ${absolutePath}`);
  const extension = extname(absolutePath).toLowerCase();
  const contentType = extension === ".png" ? "image/png" : extension === ".webp" ? "image/webp" : "image/jpeg";
  const storagePath = `users/${ownerUserId}/contentPlanningDraftImages/${draftId}/cover${extension || ".jpg"}`;
  const token = randomUUID();
  const uploadURL = new URL(`https://storage.googleapis.com/upload/storage/v1/b/${storageBucket}/o`);
  uploadURL.searchParams.set("uploadType", "media");
  uploadURL.searchParams.set("name", storagePath);
  const response = await fetch(uploadURL, {
    method: "POST",
    headers: {Authorization: `Bearer ${accessToken}`, "Content-Type": contentType},
    body: bytes,
  });
  if (!response.ok) throw new Error(`Image upload failed (${response.status}): ${await response.text()}`);
  const objectURL = `https://storage.googleapis.com/storage/v1/b/${storageBucket}/o/${encodeURIComponent(storagePath)}`;
  const metadataResponse = await fetch(objectURL, {
    method: "PATCH",
    headers: {Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json"},
    body: JSON.stringify({metadata: {firebaseStorageDownloadTokens: token}}),
  });
  if (!metadataResponse.ok) {
    throw new Error(`Image metadata update failed (${metadataResponse.status}): ${await metadataResponse.text()}`);
  }
  const url = `https://firebasestorage.googleapis.com/v0/b/${storageBucket}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
  return {url, storagePath, alternativeText: alternativeText ?? null, credit: "Зображення створене ШІ"};
}

async function authorizedFetch(url, options = {}) {
  const headers = new Headers(options.headers ?? {});
  headers.set("Authorization", `Bearer ${accessToken}`);
  if (options.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
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
    return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)
      ? {timestampValue: value}
      : {stringValue: value};
  }
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encodeValue)}};
  if (typeof value === "object") return {mapValue: {fields: encodeMap(value)}};
  fail("Unsupported Firestore value.");
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
  if ("mapValue" in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decodeValue(item)]));
  return undefined;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
