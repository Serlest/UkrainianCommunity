import {execFileSync} from "node:child_process";
import {realpathSync} from "node:fs";
import {createRequire} from "node:module";
import {dirname, join} from "node:path";

const options = parseOptions(process.argv.slice(2));
const accessToken = await firebaseAccessToken();
const firestoreBase =
  `https://firestore.googleapis.com/v1/projects/${options.projectId}/databases/(default)`;

const [newsDocuments, eventDocuments, bannerDocuments, userDocuments] = await Promise.all([
  listDocuments("news"),
  listDocuments("events"),
  listDocuments("featuredBanners"),
  listDocuments("users", {showMissing: true}),
]);
const live = {
  news: new Set(newsDocuments.map(documentID)),
  event: new Set(eventDocuments.map(documentID)),
};
const candidates = {
  recentViews: [],
  activityLog: [],
  notifications: [],
  banners: staleBanners(bannerDocuments, live),
};

for (const group of chunks(userDocuments, 20)) {
  const results = await Promise.all(group.map((document) =>
    staleUserReferences(documentID(document), live)
  ));
  for (const result of results) {
    candidates.recentViews.push(...result.recentViews);
    candidates.activityLog.push(...result.activityLog);
    candidates.notifications.push(...result.notifications);
  }
}

const summary = Object.fromEntries(
  Object.entries(candidates).map(([key, values]) => [key, values.length])
);
assertExpectedSummary(summary, options);

if (options.apply) {
  await applyReconciliation(candidates);
  await verifyReadBack(candidates);
}

console.log(JSON.stringify({
  projectId: options.projectId,
  mode: options.apply ? "apply" : "dry-run",
  generatedAt: new Date().toISOString(),
  liveContent: {news: live.news.size, events: live.event.size},
  usersScanned: userDocuments.length,
  summary,
  paths: Object.fromEntries(Object.entries(candidates).map(([key, values]) => [
    key,
    values.map((item) => item.name).sort(),
  ])),
  retainedByDesign: [
    "auditLogs",
    "systemLogs",
    "dsaCases and feedback evidence",
    "aggregated analytics",
    "contentPublishingIdentityLocks",
    "completed contentPlanningDrafts",
  ],
}, null, 2));

async function staleUserReferences(userId, liveContent) {
  const [recentViews, activityLog, notifications] = await Promise.all([
    listDocuments(`users/${userId}/recentViews`),
    listDocuments(`users/${userId}/activityLog`),
    listDocuments(`users/${userId}/notificationInbox`),
  ]);

  return {
    recentViews: recentViews.filter((document) => {
      const data = decodeMap(document.fields ?? {});
      const kind = contentKind(data.itemType);
      const id = nonEmptyString(data.itemId);
      return kind && id ? !liveContent[kind].has(id) : false;
    }),
    activityLog: activityLog.filter((document) => {
      const data = decodeMap(document.fields ?? {});
      const kind = contentKind(data.targetType);
      const id = nonEmptyString(data.targetId);
      return kind && id ? !liveContent[kind].has(id) : false;
    }),
    notifications: notifications.filter((document) => {
      const data = decodeMap(document.fields ?? {});
      const kind = notificationKind(data.actionType);
      const id = nonEmptyString(data.actionTargetId);
      return kind && id ? !liveContent[kind].has(id) : false;
    }),
  };
}

function staleBanners(documents, liveContent) {
  return documents.filter((document) => {
    const data = decodeMap(document.fields ?? {});
    const kind = contentKind(data.actionType);
    const id = nonEmptyString(data.actionTargetID);
    return kind && id ? !liveContent[kind].has(id) : false;
  });
}

async function applyReconciliation(values) {
  const deletions = [
    ...values.recentViews,
    ...values.activityLog,
    ...values.notifications,
  ];
  for (const group of chunks(deletions, 400)) {
    await commitWrites(group.map((document) => ({delete: document.name})));
  }

  const updatedAt = new Date().toISOString();
  for (const banner of values.banners) {
    await retireBanner(banner.name, updatedAt);
  }
}

async function verifyReadBack(values) {
  const deleted = [
    ...values.recentViews,
    ...values.activityLog,
    ...values.notifications,
  ];
  for (const group of chunks(deleted, 40)) {
    const existence = await Promise.all(group.map((document) => documentExists(document.name)));
    if (existence.some(Boolean)) {
      throw new Error("Read-back failed: at least one stale user reference still exists.");
    }
  }
  for (const banner of values.banners) {
    const document = await getDocument(banner.name);
    const data = decodeMap(document.fields ?? {});
    if (data.isActive !== false || data.actionType !== "none" ||
        Object.hasOwn(data, "actionTargetID")) {
      throw new Error(`Read-back failed for ${banner.name}.`);
    }
  }
}

async function retireBanner(documentName, updatedAt) {
  const url = new URL(`https://firestore.googleapis.com/v1/${documentName}`);
  for (const fieldPath of [
    "isActive",
    "actionType",
    "actionTargetID",
    "updatedAt",
    "updatedBy",
  ]) {
    url.searchParams.append("updateMask.fieldPaths", fieldPath);
  }
  url.searchParams.set("currentDocument.exists", "true");
  const response = await authorizedFetch(url, {
    method: "PATCH",
    body: JSON.stringify({
      name: documentName,
      fields: encodeMap({
        isActive: false,
        actionType: "none",
        updatedAt,
        updatedBy: "system-content-lifecycle-reconciliation",
      }),
    }),
  });
  if (!response.ok) {
    throw new Error(`Firestore banner patch failed (${response.status}): ${await response.text()}`);
  }
}

async function commitWrites(writes) {
  if (writes.length === 0) return;
  const response = await authorizedFetch(`${firestoreBase}/documents:commit`, {
    method: "POST",
    body: JSON.stringify({writes}),
  });
  if (!response.ok) {
    throw new Error(`Firestore commit failed (${response.status}): ${await response.text()}`);
  }
}

async function listDocuments(collectionPath, settings = {}) {
  const maximum = settings.maximum ?? 10_000;
  const separator = collectionPath.lastIndexOf("/");
  const parent = separator < 0 ? "" : `/${collectionPath.slice(0, separator)}`;
  const collectionId = separator < 0 ? collectionPath : collectionPath.slice(separator + 1);
  let pageToken;
  const documents = [];
  do {
    const url = new URL(`${firestoreBase}/documents${parent}/${collectionId}`);
    url.searchParams.set("pageSize", String(Math.min(500, maximum - documents.length)));
    if (settings.showMissing) url.searchParams.set("showMissing", "true");
    if (pageToken) url.searchParams.set("pageToken", pageToken);
    const response = await authorizedFetch(url);
    if (!response.ok) {
      throw new Error(`Firestore list failed (${response.status}): ${await response.text()}`);
    }
    const payload = await response.json();
    documents.push(...(payload.documents ?? []));
    pageToken = payload.nextPageToken;
    if (pageToken && documents.length >= maximum) {
      throw new Error(`Firestore list exceeded the safe ${maximum}-document limit: ${collectionPath}.`);
    }
  } while (pageToken);
  return documents;
}

async function getDocument(documentName) {
  const response = await authorizedFetch(`https://firestore.googleapis.com/v1/${documentName}`);
  if (!response.ok) {
    throw new Error(`Firestore get failed (${response.status}): ${await response.text()}`);
  }
  return response.json();
}

async function documentExists(documentName) {
  const response = await authorizedFetch(`https://firestore.googleapis.com/v1/${documentName}`);
  if (response.status === 404) return false;
  if (!response.ok) {
    throw new Error(`Firestore read-back failed (${response.status}): ${await response.text()}`);
  }
  return true;
}

async function authorizedFetch(url, settings = {}) {
  const headers = new Headers(settings.headers ?? {});
  headers.set("Authorization", `Bearer ${accessToken}`);
  if (settings.body) headers.set("Content-Type", "application/json");
  return fetch(url, {...settings, headers});
}

async function firebaseAccessToken() {
  let output;
  try {
    output = execFileSync("firebase", ["login:list", "--json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch {
    throw new Error("Firebase CLI is unavailable or not authenticated.");
  }
  const parsed = JSON.parse(output);
  const refreshToken = parsed?.result?.[0]?.tokens?.refresh_token;
  if (typeof refreshToken !== "string" || refreshToken.length < 20) {
    throw new Error("Firebase CLI is not authenticated.");
  }
  try {
    const require = createRequire(import.meta.url);
    const firebaseExecutable = execFileSync("which", ["firebase"], {
      encoding: "utf8",
    }).trim();
    const firebaseEntrypoint = realpathSync(firebaseExecutable);
    const firebaseLib = dirname(dirname(firebaseEntrypoint));
    const auth = require(join(firebaseLib, "auth.js"));
    const refreshed = await auth.getAccessToken(refreshToken, []);
    if (typeof refreshed?.access_token !== "string" || refreshed.access_token.length < 20) {
      throw new Error("missing access token");
    }
    return refreshed.access_token;
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unknown authentication error";
    throw new Error(`Firebase CLI authentication could not be refreshed: ${reason}`);
  }
}

function contentKind(value) {
  if (value === "news") return "news";
  if (value === "event") return "event";
  return undefined;
}

function notificationKind(value) {
  if (value === "openNews") return "news";
  if (value === "openEvent") return "event";
  return undefined;
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function documentID(document) {
  return document.name.split("/").at(-1);
}

function assertExpectedSummary(summary, settings) {
  if (!settings.apply) return;
  for (const [key, expected] of Object.entries(settings.expected)) {
    if (summary[key] !== expected) {
      throw new Error(
        `Preflight mismatch for ${key}: expected ${expected}, received ${summary[key]}. ` +
        "No writes were made."
      );
    }
  }
}

function parseOptions(argumentsList) {
  const values = new Map();
  let apply = false;
  for (const argument of argumentsList) {
    if (argument === "--apply") apply = true;
    else if (argument.startsWith("--") && argument.includes("=")) {
      const separator = argument.indexOf("=");
      values.set(argument.slice(2, separator), argument.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }
  const projectId = required(values.get("project"), "--project");
  if (apply && values.get("confirm-project") !== projectId) {
    throw new Error("--apply requires --confirm-project to exactly match --project.");
  }
  const expectedKeys = ["recentViews", "activityLog", "notifications", "banners"];
  const expected = Object.fromEntries(expectedKeys.map((key) => {
    const flag = `--expect-${kebabCase(key)}`;
    const value = values.get(`expect-${kebabCase(key)}`);
    if (apply && value === undefined) throw new Error(`--apply requires ${flag}.`);
    return [key, nonNegativeInteger(value ?? "0", flag)];
  }));
  return {projectId, apply, expected};
}

function required(value, flag) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${flag} is required.`);
  return value.trim();
}

function nonNegativeInteger(value, flag) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${flag} must be a non-negative integer.`);
  }
  return parsed;
}

function kebabCase(value) {
  return value.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
}

function chunks(values, size) {
  const result = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}

function encodeMap(value) {
  return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, encodeValue(item)]));
}

function encodeValue(value) {
  if (value === null) return {nullValue: null};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number") {
    return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  }
  if (typeof value === "string") {
    return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)
      ? {timestampValue: value}
      : {stringValue: value};
  }
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encodeValue)}};
  if (typeof value === "object" && value !== null) {
    return {mapValue: {fields: encodeMap(value)}};
  }
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
