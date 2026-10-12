#!/usr/bin/env node

import {createHash, randomUUID} from "node:crypto";
import {readFile, rename, unlink, writeFile} from "node:fs/promises";
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {contentAutomationAccessToken} from "./contentAutomationCredential.mjs";
import {deterministicContentId, normalizeAndValidateManifestItem} from "./verifiedContentPublisherCore.mjs";

const defaultProjectId = "ukrainiancommunity-dbd5f";

function decodeValue(value) {
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("mapValue" in value) return Object.fromEntries(Object.entries(value.mapValue.fields ?? {})
    .map(([key, nested]) => [key, decodeValue(nested)]));
  if ("arrayValue" in value) return (value.arrayValue.values ?? []).map(decodeValue);
  if ("nullValue" in value) return null;
  throw new Error("Unsupported Firestore field in news read-back.");
}

export function verifyNewsProductionDocument(document, item, organizationId, contentId, cover) {
  const checks = {
    id: document.id === contentId,
    organization: document.organizationId === organizationId,
    scope: document.regionScope === item.regionScope &&
      document.federalState === item.federalState,
    approved: document.moderationStatus === "approved",
    ukTitle: document.localizations?.uk?.title === item.title,
    ukSubtitle: document.localizations?.uk?.subtitle === item.subtitle,
    ukBody: document.localizations?.uk?.body === item.body,
    deTitle: document.localizations?.de?.title === item.deTitle,
    deSubtitle: document.localizations?.de?.subtitle === item.deSubtitle,
    deBody: document.localizations?.de?.body === item.deBody,
    source: document.sourceURL === item.canonicalURL,
    publishedAt: Date.parse(document.publishedAt) === item.publishedAt.getTime(),
    imageCredit: document.mediaMetadata?.credit === item.imageCredit,
    imageAlternativeText: document.mediaMetadata?.alternativeText === item.imageAlternativeText,
    cover: cover.contentType === "image/jpeg" && cover.bytes > 10_000,
  };
  return {
    schemaVersion: 1, readAt: new Date().toISOString(), contentId,
    document: {
      id: document.id, organizationId: document.organizationId,
      moderationStatus: document.moderationStatus,
      regionScope: document.regionScope, federalState: document.federalState,
    },
    checks, allVerified: Object.values(checks).every(Boolean),
    sourceURL: document.sourceURL, publishedAt: document.publishedAt,
    coverContentType: cover.contentType, coverBytes: cover.bytes,
    coverSHA256: cover.sha256,
  };
}

export async function readbackPublishedNews(manifestPath, organizationId, dependencies = {}) {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const items = Array.isArray(manifest) ? manifest : Array.isArray(manifest?.items) ? manifest.items : [manifest];
  if (items.length !== 1) throw new Error("News read-back requires one manifest item.");
  const rawItem = items[0];
  const target = rawItem.regionScope === "austria" ? "austria" : rawItem.federalState;
  const item = normalizeAndValidateManifestItem(rawItem, target);
  if (item.kind !== "news") throw new Error("News read-back accepts news only.");
  const contentId = deterministicContentId("news", organizationId, item.canonicalURL);
  const projectId = dependencies.projectId ?? process.env.UAC_FIREBASE_PROJECT_ID ?? defaultProjectId;
  const accessToken = await (dependencies.getAccessToken ?? contentAutomationAccessToken)();
  const fetchImpl = dependencies.fetchImpl ?? fetch;
  const url = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/news/${encodeURIComponent(contentId)}`;
  const documentResponse = await fetchImpl(url, {headers: {Authorization: `Bearer ${accessToken}`}});
  if (!documentResponse.ok) throw new Error(`Production news read-back failed (${documentResponse.status}).`);
  const record = await documentResponse.json();
  const document = Object.fromEntries(Object.entries(record.fields ?? {})
    .map(([key, value]) => [key, decodeValue(value)]));
  if (typeof document.imageURL !== "string" || !document.imageURL.startsWith("https://")) {
    throw new Error("Published news has no HTTPS cover URL.");
  }
  const coverResponse = await fetchImpl(document.imageURL);
  if (!coverResponse.ok) throw new Error(`Published news cover read-back failed (${coverResponse.status}).`);
  const bytes = Buffer.from(await coverResponse.arrayBuffer());
  return verifyNewsProductionDocument(document, item, organizationId, contentId, {
    contentType: coverResponse.headers.get("content-type"), bytes: bytes.length,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  });
}

export async function writeNewsProductionReceipt(path, receipt) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, JSON.stringify(receipt, null, 2) + "\n");
    await rename(temporary, path);
  } finally {
    await unlink(temporary).catch(() => {});
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [manifestPath, organizationId, receiptPath] = process.argv.slice(2);
  if (!manifestPath || !organizationId || !receiptPath) {
    console.error("Usage: node newsProductionReadback.mjs <manifest.json> <organization-id> <receipt.json>");
    process.exitCode = 1;
  } else {
    try {
      const receipt = await readbackPublishedNews(resolve(manifestPath), organizationId);
      await writeNewsProductionReceipt(resolve(receiptPath), receipt);
      console.log(JSON.stringify(receipt));
      if (!receipt.allVerified) process.exitCode = 1;
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
}
