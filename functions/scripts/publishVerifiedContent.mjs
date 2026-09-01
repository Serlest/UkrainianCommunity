#!/usr/bin/env node

import {randomUUID} from "node:crypto";
import {execFile, execFileSync} from "node:child_process";
import {createRequire} from "node:module";
import {access, mkdtemp, readFile, rm, stat, unlink} from "node:fs/promises";
import {tmpdir} from "node:os";
import {dirname, extname, join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {promisify} from "node:util";

import {
  buildContentDocument,
  classifyLegacyDuplicate,
  contentIdentityLockClaims,
  deterministicContentId,
  documentsSemanticallyMatch,
  normalizeAndValidateManifestItem,
  normalizePublicationTarget,
  validateOrganization,
} from "./verifiedContentPublisherCore.mjs";
import {
  buildContentPlanningSummary,
  canonicalizeURL,
} from "./contentPlanningBridgeSummary.mjs";

const defaultProjectId = "ukrainiancommunity-dbd5f";
const maximumInputImageBytes = 50_000_000;
const maximumAtomicWrites = 450;
const identityLockCollection = "contentPublishingIdentityLocks";
const supportedImageExtensions = new Set([".jpg", ".jpeg", ".png", ".webp"]);
const runFile = promisify(execFile);

export const MAXIMUM_CANONICAL_COVER_BYTES = 3_000_000;
export const CANONICAL_COVER_CONTENT_TYPE = "image/jpeg";

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const projectId = process.env.UAC_FIREBASE_PROJECT_ID ?? defaultProjectId;
  const storageBucket = process.env.UAC_FIREBASE_STORAGE_BUCKET ?? `${projectId}.firebasestorage.app`;
  const manifestPath = resolve(options.manifestPath);
  const rawManifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const rawItems = Array.isArray(rawManifest)
    ? rawManifest
    : (rawManifest && typeof rawManifest === "object" && Array.isArray(rawManifest.items))
      ? rawManifest.items
      : [rawManifest];
  if (!Array.isArray(rawItems) || rawItems.length === 0) throw new Error("Manifest contains no items.");
  if (rawItems.length > 450) throw new Error("A single atomic publication is limited to 450 items.");

  const target = resolvePublicationTarget(options);
  const items = rawItems.map((item, index) => {
    try {
      return normalizeAndValidateManifestItem(item, target);
    } catch (error) {
      throw new Error(`Manifest item ${index + 1}: ${error instanceof Error ? error.message : String(error)}`);
    }
  });
  const duplicateIds = duplicateContentIds(items, options.organizationId);
  if (duplicateIds.length > 0) throw new Error(`Manifest contains duplicate deterministic ids: ${duplicateIds.join(", ")}.`);

  const accessToken = await firebaseAccessToken();
  const client = firebaseRESTClient({accessToken, projectId, storageBucket});
  const organization = validateOrganization(
    await client.getOrganization(options.organizationId),
    options.organizationId,
    target
  );
  const existingRecords = await client.listExistingContentSummaries(organization.ownerId);
  const duplicatePreflight = items.map((item) => classifyLegacyDuplicate({
    item,
    expectedDocument: buildContentDocument(item, organization, options.organizationId, undefined),
    existingRecords,
  }));
  const duplicateConflicts = duplicatePreflight.flatMap((classification, index) => (
    classification.status === "needsAttention"
      ? [{index, item: items[index], classification}]
      : []
  ));
  if (duplicateConflicts.length > 0) {
    const details = duplicateConflicts.map(({index, item, classification}) => {
      const conflicts = classification.conflicts
        .map((candidate) => `${candidate.existingCollection}/${candidate.existingId}`)
        .join(", ");
      return `item ${index + 1} (${item.title}) conflicts with ${conflicts}`;
    }).join("; ");
    throw new Error(`needsAttention: existing content has the same identity but different semantics: ${details}.`);
  }
  const plan = [];
  for (let index = 0; index < items.length; index += 1) {
    const item = items[index];
    const id = deterministicContentId(item.kind, options.organizationId, item.canonicalURL);
    const collection = item.kind === "event" ? "events" : "news";
    const storagePath = canonicalCoverStoragePath(item.kind, id);
    const expected = buildContentDocument(item, organization, options.organizationId, undefined);
    const duplicate = duplicatePreflight[index];
    const existing = await client.getContent(collection, id);
    if (existing) {
      if (!documentsSemanticallyMatch(existing, expected)) {
        throw new Error(`Deterministic id collision for ${collection}/${id}; existing content is not an exact semantic match.`);
      }
      plan.push({
        id,
        collection,
        item,
        storagePath,
        status: "skippedExisting",
        existingId: id,
        existingCollection: collection,
        matchedBy: "deterministicId",
      });
      continue;
    }
    if (duplicate.status === "skippedExisting") {
      plan.push({
        id,
        collection,
        item,
        storagePath,
        status: "skippedExisting",
        existingId: duplicate.existingId,
        existingCollection: duplicate.existingCollection,
        matchedBy: duplicate.matchedBy,
      });
      continue;
    }
    if (await client.storageObjectExists(storagePath)) {
      throw new Error(`Storage collision for ${storagePath}; no matching Firestore document exists.`);
    }
    const identityClaims = contentIdentityLockClaims(item);
    const existingLocks = (await Promise.all(
      identityClaims.map((claim) => client.getIdentityLock(claim.id))
    )).filter(Boolean);
    if (existingLocks.length > 0) {
      const claimedContent = existingLocks
        .map((lock) => `${lock.contentCollection ?? "content"}/${lock.contentId ?? "unknown"}`)
        .join(", ");
      throw new Error(`needsAttention: global content identity is already claimed by ${claimedContent}.`);
    }
    plan.push({id, collection, item, identityClaims, storagePath, status: "new"});
  }

  const newItems = plan.filter((entry) => entry.status === "new");
  assertUniqueIdentityClaims(newItems);
  const atomicWriteCount = newItems.length
    + newItems.reduce((total, entry) => total + entry.identityClaims.length, 0);
  if (atomicWriteCount > maximumAtomicWrites) {
    throw new Error(`Atomic publication needs ${atomicWriteCount} writes; the safe limit is ${maximumAtomicWrites}.`);
  }
  for (const entry of newItems) {
    entry.image = await prepareImage(entry.item, manifestPath);
  }
  if (options.dryRun) {
    printResult({
      dryRun: true,
      projectId,
      organization: organizationSummary(organization),
      created: 0,
      skipped: plan.length - newItems.length,
      planned: newItems.length,
      items: plan.map(resultSummary),
    });
    return;
  }

  const uploads = [];
  try {
    for (const entry of newItems) {
      const upload = await client.uploadCover(entry.storagePath, entry.image, {
        contentId: entry.id,
        kind: entry.item.kind,
        organizationId: options.organizationId,
      });
      uploads.push(upload);
      entry.imageURL = upload.imageURL;
    }
    const now = new Date();
    const writes = newItems.map((entry) => ({
      collection: entry.collection,
      id: entry.id,
      document: buildContentDocument(entry.item, organization, options.organizationId, entry.imageURL, now),
    }));
    for (const entry of newItems) {
      for (const claim of entry.identityClaims) {
        writes.push({
          collection: identityLockCollection,
          id: claim.id,
          document: buildIdentityLockDocument({claim, entry, organizationId: options.organizationId, now}),
        });
      }
    }
    await client.commitNewDocuments(writes);
  } catch (error) {
    await Promise.allSettled(uploads.map((upload) => client.deleteUploadedObject(upload)));
    throw error;
  }

  for (const entry of newItems) {
    const readback = await client.getContent(entry.collection, entry.id);
    const expected = buildContentDocument(entry.item, organization, options.organizationId, entry.imageURL);
    if (!readback
      || !documentsSemanticallyMatch(readback, expected)
      || readback.imageURL !== entry.imageURL
      || readback.moderationStatus !== "approved") {
      throw new Error(`Readback verification failed for ${entry.collection}/${entry.id}.`);
    }
    const locks = await Promise.all(entry.identityClaims.map((claim) => client.getIdentityLock(claim.id)));
    if (locks.some((lock) => lock?.contentId !== entry.id || lock?.contentCollection !== entry.collection)) {
      throw new Error(`Identity-lock readback verification failed for ${entry.collection}/${entry.id}.`);
    }
  }

  printResult({
    dryRun: false,
    projectId,
    organization: organizationSummary(organization),
    created: newItems.length,
    skipped: plan.length - newItems.length,
    planned: 0,
    items: plan.map((entry) => resultSummary({...entry, status: entry.status === "new" ? "created" : entry.status})),
  });
}

export function assertUniqueIdentityClaims(entries) {
  const owners = new Map();
  for (const entry of entries) {
    for (const claim of entry.identityClaims ?? []) {
      const owner = owners.get(claim.id);
      if (owner && owner !== entry.id) {
        throw new Error(`needsAttention: manifest items ${owner} and ${entry.id} claim the same global content identity.`);
      }
      owners.set(claim.id, entry.id);
    }
  }
}

export function buildIdentityLockDocument({claim, entry, organizationId, now}) {
  return {
    schemaVersion: 1,
    identityAlgorithm: "uacContentIdentity-v1",
    identityType: claim.type,
    identityKeyHash: claim.id,
    contentId: entry.id,
    contentCollection: entry.collection,
    contentKind: entry.item.kind,
    organizationId,
    canonicalURL: entry.item.canonicalURL,
    createdAt: new Date(now),
  };
}

export function parseArguments(argumentsList) {
  let manifestPath;
  let organizationId;
  let federalState;
  let regionScope;
  let dryRun = false;
  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === "--dry-run") {
      dryRun = true;
    } else if (argument === "--manifest") {
      manifestPath = requiredArgument(argumentsList, ++index, "--manifest");
    } else if (argument === "--organization-id") {
      organizationId = requiredArgument(argumentsList, ++index, "--organization-id");
    } else if (argument === "--federal-state") {
      federalState = requiredArgument(argumentsList, ++index, "--federal-state");
    } else if (argument === "--region-scope") {
      regionScope = requiredArgument(argumentsList, ++index, "--region-scope");
    } else if (!argument.startsWith("-") && !manifestPath) {
      manifestPath = argument;
    } else {
      usage(`Unknown argument: ${argument}`);
    }
  }
  if (!manifestPath || !organizationId || (!federalState && !regionScope)) usage();
  if (!/^[A-Za-z0-9_-]{1,150}$/.test(organizationId)) throw new Error("organization id is invalid.");
  return {manifestPath, organizationId, federalState, regionScope, dryRun};
}

export function resolvePublicationTarget(options) {
  if (!options.regionScope) return normalizePublicationTarget(options.federalState);
  const regionScope = options.regionScope === "country" ? "austria" : options.regionScope;
  if (regionScope === "austria") {
    if (options.federalState && options.federalState !== "austria") {
      throw new Error("Nationwide publication cannot specify a federal state.");
    }
    return normalizePublicationTarget("austria");
  }
  if (regionScope === "federalState") {
    if (!options.federalState || options.federalState === "austria") {
      throw new Error("regionScope=federalState requires a real federal state.");
    }
    return normalizePublicationTarget(options.federalState);
  }
  throw new Error("region scope must be country, austria, or federalState.");
}

function requiredArgument(argumentsList, index, flag) {
  const value = argumentsList[index];
  if (!value || value.startsWith("--")) usage(`${flag} requires a value.`);
  return value;
}

function usage(message) {
  const prefix = message ? `${message}\n` : "";
  throw new Error(`${prefix}Usage: node scripts/publishVerifiedContent.mjs <manifest.json> --organization-id <id> (--federal-state <state|austria> | --region-scope <country|austria|federalState>) [--dry-run]`);
}

function duplicateContentIds(items, organizationId) {
  const ids = items.map((item) => deterministicContentId(item.kind, organizationId, item.canonicalURL));
  return [...new Set(ids.filter((id, index) => ids.indexOf(id) !== index))];
}

export function canonicalCoverStoragePath(kind, contentId) {
  const collection = kind === "event" ? "events" : kind === "news" ? "news" : undefined;
  if (!collection) throw new Error("Cover kind must be news or event.");
  if (typeof contentId !== "string" || !/^[A-Za-z0-9_-]{1,150}$/.test(contentId)) {
    throw new Error("Cover content id is invalid.");
  }
  return `${collection}/${contentId}/cover.jpg`;
}

export async function prepareImage(item, manifestPath) {
  const candidates = [
    resolve(item.imagePath),
    resolve(dirname(manifestPath), item.imagePath),
    resolve(dirname(manifestPath), "../../..", item.imagePath),
  ];
  const absolutePath = await firstAccessiblePath([...new Set(candidates)]);
  if (!absolutePath) throw new Error(`Image does not exist: ${item.imagePath}.`);
  const extension = extname(absolutePath).toLowerCase();
  if (!supportedImageExtensions.has(extension)) {
    throw new Error(`Unsupported cover extension for ${item.imagePath}.`);
  }
  const inputStats = await stat(absolutePath);
  if (!inputStats.isFile() || inputStats.size === 0 || inputStats.size > maximumInputImageBytes) {
    throw new Error(`Source cover must be a file between 1 byte and 50 MB: ${item.imagePath}.`);
  }
  const sourceBytes = await readFile(absolutePath);
  verifyImageSignature(sourceBytes, extension, item.imagePath);
  const converted = await convertCoverToCanonicalJPEG(absolutePath);
  return {
    absolutePath,
    extension: ".jpg",
    contentType: CANONICAL_COVER_CONTENT_TYPE,
    bytes: converted.bytes,
    quality: converted.quality,
    maximumDimension: converted.maximumDimension,
  };
}

export async function convertCoverToCanonicalJPEG(absolutePath) {
  const dimensions = await imageDimensions(absolutePath);
  const sourceMaximumDimension = Math.max(dimensions.width, dimensions.height);
  const initialMaximumDimension = Math.min(sourceMaximumDimension, 2400);
  const attempts = uniqueConversionAttempts([
    {maximumDimension: initialMaximumDimension, quality: 82},
    {maximumDimension: initialMaximumDimension, quality: 72},
    {maximumDimension: initialMaximumDimension, quality: 60},
    {maximumDimension: Math.min(initialMaximumDimension, 2000), quality: 70},
    {maximumDimension: Math.min(initialMaximumDimension, 1600), quality: 64},
    {maximumDimension: Math.min(initialMaximumDimension, 1280), quality: 58},
    {maximumDimension: Math.min(initialMaximumDimension, 960), quality: 52},
  ]);
  const temporaryDirectory = await mkdtemp(join(tmpdir(), "uac-content-cover-"));
  const outputPath = join(temporaryDirectory, "cover.jpg");
  try {
    for (const attempt of attempts) {
      await unlink(outputPath).catch(() => undefined);
      const argumentsList = [
        "-s", "format", "jpeg",
        "-s", "formatOptions", String(attempt.quality),
      ];
      if (sourceMaximumDimension > attempt.maximumDimension) {
        argumentsList.push("-Z", String(attempt.maximumDimension));
      }
      argumentsList.push(absolutePath, "--out", outputPath);
      try {
        await runFile("/usr/bin/sips", argumentsList, {maxBuffer: 1_000_000});
      } catch {
        throw new Error(`Cover conversion failed for ${absolutePath}.`);
      }
      const bytes = await readFile(outputPath);
      verifyImageSignature(bytes, ".jpg", outputPath);
      if (bytes.length > 0 && bytes.length < MAXIMUM_CANONICAL_COVER_BYTES) {
        return {...attempt, bytes};
      }
    }
    throw new Error(`Converted cover cannot be reduced below ${MAXIMUM_CANONICAL_COVER_BYTES} bytes.`);
  } finally {
    await rm(temporaryDirectory, {recursive: true, force: true});
  }
}

async function imageDimensions(absolutePath) {
  let stdout;
  try {
    ({stdout} = await runFile("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", absolutePath], {
      encoding: "utf8",
      maxBuffer: 1_000_000,
    }));
  } catch {
    throw new Error(`Cover dimensions cannot be read: ${absolutePath}.`);
  }
  const width = Number(/pixelWidth:\s*(\d+)/.exec(stdout)?.[1]);
  const height = Number(/pixelHeight:\s*(\d+)/.exec(stdout)?.[1]);
  if (!Number.isInteger(width) || width <= 0 || !Number.isInteger(height) || height <= 0) {
    throw new Error(`Cover dimensions are invalid: ${absolutePath}.`);
  }
  return {width, height};
}

function uniqueConversionAttempts(attempts) {
  const seen = new Set();
  return attempts.filter((attempt) => {
    const key = `${attempt.maximumDimension}:${attempt.quality}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

async function firstAccessiblePath(candidates) {
  for (const candidate of candidates) {
    try {
      await access(candidate);
      return candidate;
    } catch {
      // Try the next deterministic resolution root.
    }
  }
  return undefined;
}

function verifyImageSignature(bytes, extension, path) {
  const isJPEG = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPNG = bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const isWebP = bytes.subarray(0, 4).toString("ascii") === "RIFF"
    && bytes.subarray(8, 12).toString("ascii") === "WEBP";
  if (([".jpg", ".jpeg"].includes(extension) && !isJPEG)
    || (extension === ".png" && !isPNG)
    || (extension === ".webp" && !isWebP)) {
    throw new Error(`Cover bytes do not match the extension: ${path}.`);
  }
}

async function firebaseAccessToken() {
  let output;
  try {
    output = execFileSync("firebase", ["login:list", "--json"], {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]});
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
    const globalNodeModules = execFileSync("npm", ["root", "--global"], {encoding: "utf8"}).trim();
    const auth = require(join(globalNodeModules, "firebase-tools/lib/auth.js"));
    const refreshed = await auth.getAccessToken(refreshToken, []);
    if (typeof refreshed?.access_token !== "string" || refreshed.access_token.length < 20) {
      throw new Error("missing access token");
    }
    return refreshed.access_token;
  } catch {
    throw new Error("Firebase CLI authentication could not be refreshed.");
  }
}

function firebaseRESTClient({accessToken, projectId, storageBucket}) {
  const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)`;
  const documentName = (collection, id) => `projects/${projectId}/databases/(default)/documents/${collection}/${id}`;

  async function authorizedFetch(url, options = {}) {
    const headers = new Headers(options.headers ?? {});
    headers.set("Authorization", `Bearer ${accessToken}`);
    if (options.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
    return fetch(url, {...options, headers});
  }

  async function getDocument(collection, id) {
    const response = await authorizedFetch(`${firestoreBase}/documents/${collection}/${encodeURIComponent(id)}`);
    if (response.status === 404) return undefined;
    if (!response.ok) throw new Error(`Firestore read failed for ${collection}/${id} (${response.status}).`);
    const payload = await response.json();
    return decodeMap(payload.fields ?? {});
  }

  async function listDocuments(collectionPath) {
    const encodedPath = collectionPath.split("/").map(encodeURIComponent).join("/");
    const documents = [];
    let pageToken;
    do {
      const url = new URL(`${firestoreBase}/documents/${encodedPath}`);
      url.searchParams.set("pageSize", "500");
      if (pageToken) url.searchParams.set("pageToken", pageToken);
      const response = await authorizedFetch(url);
      if (!response.ok) {
        throw new Error(`Firestore duplicate preflight failed for ${collectionPath} (${response.status}).`);
      }
      const payload = await response.json();
      documents.push(...(payload.documents ?? []));
      pageToken = payload.nextPageToken;
    } while (pageToken);
    return documents;
  }

  function duplicateRecord(document, collection, defaultKind) {
    const id = document.name.split("/").at(-1);
    const fields = decodeMap(document.fields ?? {});
    return buildExistingDuplicateRecord({id, collection, defaultKind, fields});
  }

  return {
    async getOrganization(organizationId) {
      return getDocument("organizations", organizationId);
    },

    async getContent(collection, id) {
      return getDocument(collection, id);
    },

    async getIdentityLock(id) {
      return getDocument(identityLockCollection, id);
    },

    async listExistingContentSummaries(ownerId) {
      const [drafts, news, events] = await Promise.all([
        listDocuments(`users/${ownerId}/contentPlanningDrafts`),
        listDocuments("news"),
        listDocuments("events"),
      ]);
      return [
        ...drafts.map((document) => duplicateRecord(document, "drafts")),
        ...news.map((document) => duplicateRecord(document, "news", "news")),
        ...events.map((document) => duplicateRecord(document, "events", "event")),
      ];
    },

    async storageObjectExists(storagePath) {
      const url = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(storageBucket)}/o/${encodeURIComponent(storagePath)}`;
      const response = await authorizedFetch(url);
      if (response.status === 404) return false;
      if (!response.ok) throw new Error(`Storage preflight failed for ${storagePath} (${response.status}).`);
      return true;
    },

    async uploadCover(storagePath, image, identity) {
      if (!storagePath.endsWith("/cover.jpg")) {
        throw new Error(`Canonical cover path is required: ${storagePath}.`);
      }
      if (image.contentType !== CANONICAL_COVER_CONTENT_TYPE
        || image.bytes.length === 0
        || image.bytes.length >= MAXIMUM_CANONICAL_COVER_BYTES) {
        throw new Error(`Canonical JPEG cover contract failed for ${storagePath}.`);
      }
      verifyImageSignature(image.bytes, ".jpg", storagePath);
      const uploadURL = new URL(`https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(storageBucket)}/o`);
      uploadURL.searchParams.set("uploadType", "media");
      uploadURL.searchParams.set("name", storagePath);
      uploadURL.searchParams.set("ifGenerationMatch", "0");
      const uploadResponse = await authorizedFetch(uploadURL, {
        method: "POST",
        headers: {"Content-Type": CANONICAL_COVER_CONTENT_TYPE},
        body: image.bytes,
      });
      if (!uploadResponse.ok) {
        throw new Error(`Cover upload failed for ${storagePath} (${uploadResponse.status}): ${await uploadResponse.text()}`);
      }
      const uploaded = await uploadResponse.json();
      const token = randomUUID();
      const objectURL = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(storageBucket)}/o/${encodeURIComponent(storagePath)}`;
      const metadataResponse = await authorizedFetch(objectURL, {
        method: "PATCH",
        body: JSON.stringify({
          cacheControl: "public,max-age=3600",
          metadata: {
            firebaseStorageDownloadTokens: token,
            uacContentId: identity.contentId,
            uacContentKind: identity.kind,
            uacOrganizationId: identity.organizationId,
          },
        }),
      });
      if (!metadataResponse.ok) {
        await authorizedFetch(`${objectURL}?ifGenerationMatch=${encodeURIComponent(uploaded.generation)}`, {method: "DELETE"}).catch(() => undefined);
        throw new Error(`Cover metadata update failed for ${storagePath} (${metadataResponse.status}).`);
      }
      return {
        storagePath,
        generation: uploaded.generation,
        imageURL: `https://firebasestorage.googleapis.com/v0/b/${storageBucket}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`,
      };
    },

    async deleteUploadedObject(upload) {
      const objectURL = `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(storageBucket)}/o/${encodeURIComponent(upload.storagePath)}`;
      const url = new URL(objectURL);
      if (upload.generation) url.searchParams.set("ifGenerationMatch", upload.generation);
      const response = await authorizedFetch(url, {method: "DELETE"});
      if (!response.ok && response.status !== 404) {
        throw new Error(`Cover cleanup failed for ${upload.storagePath} (${response.status}).`);
      }
    },

    async commitNewDocuments(writes) {
      if (writes.length === 0) return;
      const response = await authorizedFetch(`${firestoreBase}/documents:commit`, {
        method: "POST",
        body: JSON.stringify({
          writes: writes.map((write) => ({
            update: {name: documentName(write.collection, write.id), fields: encodeMap(write.document)},
            currentDocument: {exists: false},
          })),
        }),
      });
      if (!response.ok) throw new Error(`Atomic Firestore commit failed (${response.status}): ${await response.text()}`);
    },
  };
}

export function buildExistingDuplicateRecord({id, collection, defaultKind, fields}) {
  const payload = recordValue(fields?.payload);
  const verificationSources = Array.isArray(fields?.sources)
    ? fields.sources
    : Array.isArray(payload.sources)
      ? payload.sources
      : fields?.verificationSources;
  const kind = fields?.kind ?? payload.kind ?? defaultKind;
  const summaryFields = {
    ...recordValue(fields),
    sources: verificationSources,
    occurrences: kind === "event" ? normalizedDuplicateOccurrences(fields) : fields?.occurrences,
  };
  const summary = buildContentPlanningSummary({id, defaultKind, fields: summaryFields});
  return {
    id,
    collection,
    fields: recordValue(fields),
    summary: {
      ...summary,
      primaryCanonicalURL: strictPrimaryCanonicalURL(recordValue(fields), verificationSources),
    },
  };
}

function strictPrimaryCanonicalURL(fields, verificationSources) {
  const payload = recordValue(fields.payload);
  const primarySource = Array.isArray(verificationSources)
    ? verificationSources.find((source) => recordValue(source).isPrimary === true)
    : undefined;
  for (const candidate of [recordValue(primarySource).url, fields.sourceURL, payload.sourceURL]) {
    if (typeof candidate !== "string" || !candidate.trim()) continue;
    try {
      const parsed = new URL(candidate);
      if (parsed.protocol !== "https:" || !parsed.hostname) continue;
      return canonicalizeURL(candidate);
    } catch {
      // Existing malformed source values do not become duplicate identities.
    }
  }
  return undefined;
}

function normalizedDuplicateOccurrences(fields) {
  const payload = recordValue(fields.payload);
  const stored = Array.isArray(fields.occurrences)
    ? fields.occurrences
    : Array.isArray(payload.occurrences)
      ? payload.occurrences
      : [];
  const occurrences = stored.length > 0
    ? stored
    : [
      ...((fields.startDate ?? payload.startDate) ? [{
        startDate: fields.startDate ?? payload.startDate,
        endDate: fields.endDate ?? payload.endDate,
        isAllDay: fields.isAllDay ?? payload.isAllDay,
      }] : []),
      ...(Array.isArray(fields.additionalOccurrences)
        ? fields.additionalOccurrences
        : Array.isArray(payload.additionalOccurrences)
          ? payload.additionalOccurrences
          : []),
    ];
  return occurrences.flatMap((rawOccurrence) => {
    const occurrence = recordValue(rawOccurrence);
    const startDate = normalizedExistingTimestamp(occurrence.startDate);
    if (!startDate) return [];
    return [{
      ...occurrence,
      startDate,
      endDate: normalizedExistingTimestamp(occurrence.endDate) ?? startDate,
    }];
  }).sort((left, right) => left.startDate.localeCompare(right.startDate));
}

function normalizedExistingTimestamp(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString();
  if (typeof value !== "string" || !value.trim()) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value.trim() : date.toISOString();
}

function recordValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function encodeMap(value) {
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .map(([key, item]) => [key, encodeValue(item)])
  );
}

function encodeValue(value) {
  if (value === null) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number") return Number.isInteger(value)
    ? {integerValue: String(value)}
    : {doubleValue: value};
  if (typeof value === "string") return {stringValue: value};
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encodeValue)}};
  if (value && typeof value === "object") return {mapValue: {fields: encodeMap(value)}};
  throw new Error(`Unsupported Firestore value type: ${typeof value}.`);
}

function decodeMap(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]));
}

function decodeValue(value) {
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return value.doubleValue;
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("mapValue" in value) return decodeMap(value.mapValue.fields ?? {});
  if ("geoPointValue" in value) return value.geoPointValue;
  throw new Error("Unsupported Firestore value in readback.");
}

function organizationSummary(organization) {
  return {
    id: organization.id,
    name: organization.name,
    federalState: organization.federalState,
    regionScope: organization.regionScope,
    ownerId: organization.ownerId,
  };
}

function resultSummary(entry) {
  return {
    id: entry.id,
    kind: entry.item.kind,
    title: entry.item.title,
    canonicalURL: entry.item.canonicalURL,
    status: entry.status,
    existingId: entry.existingId,
    existingCollection: entry.existingCollection,
    matchedBy: entry.matchedBy,
    storagePath: entry.status === "skippedExisting" ? undefined : entry.storagePath,
    cover: entry.image ? {
      contentType: entry.image.contentType,
      byteCount: entry.image.bytes.length,
      quality: entry.image.quality,
      maximumDimension: entry.image.maximumDimension,
    } : undefined,
  };
}

function printResult(result) {
  console.log(JSON.stringify(result, (_key, value) => value === undefined ? undefined : value, 2));
}
