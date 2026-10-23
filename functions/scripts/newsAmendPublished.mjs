#!/usr/bin/env node
import {createHash} from "node:crypto";
import {readFile, writeFile, mkdir, rename} from "node:fs/promises";
import {homedir} from "node:os";
import {join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {contentAutomationAccessToken} from "./contentAutomationCredential.mjs";
import {reviewNewsForPublication} from "./newsEditorialGate.mjs";
import {readbackPublishedNews} from "./newsProductionReadback.mjs";
import {deterministicContentId, normalizeAndValidateManifestItem, EXPECTED_OWNER_ID} from "./verifiedContentPublisherCore.mjs";

const hash = (x) => createHash("sha256").update(x).digest("hex");
const load = async (p) => JSON.parse(await readFile(p, "utf8"));
const one = (d) => {
  const a = Array.isArray(d) ? d : d.items ?? [d];
  if (a.length !== 1) throw new Error("Amend exactly one existing news article.");
  return a[0];
};
function decode(v) {
  if (v.mapValue) return Object.fromEntries(Object.entries(v.mapValue.fields ?? {}).map(([k, x]) => [k, decode(x)]));
  if (v.arrayValue) return (v.arrayValue.values ?? []).map(decode);
  if ("nullValue" in v) return null;
  for (const k of ["stringValue", "timestampValue", "booleanValue", "integerValue", "doubleValue"]) if (k in v) return v[k];
  throw new Error("Unsupported Firestore value.");
}
function encode(v) {
  if (v instanceof Date) return {timestampValue: v.toISOString()};
  if (typeof v === "string") return {stringValue: v};
  return {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)]))}};
}

export function buildNewsAmendment(before, oldRaw, newRaw, organizationId, now = new Date()) {
  const target = oldRaw.regionScope === "austria" ? "austria" : oldRaw.federalState;
  const old = normalizeAndValidateManifestItem(oldRaw, target);
  const next = normalizeAndValidateManifestItem(newRaw, target);
  if (old.kind !== "news" || next.kind !== "news") throw new Error("Amend news only.");
  const immutable = ["canonicalURL", "regionScope", "federalState", "category", "additionalCategories", "tags", "city", "sourceName", "imagePath", "imageCredit", "imageAlternativeText", "externalAction"];
  for (const k of immutable) if (JSON.stringify(old[k]) !== JSON.stringify(next[k])) throw new Error(`Amendment cannot change ${k}.`);
  const id = deterministicContentId("news", organizationId, old.canonicalURL);
  if (before.id !== id || before.organizationId !== organizationId || before.authorId !== EXPECTED_OWNER_ID || before.moderationStatus !== "approved") {
    throw new Error("Existing approved UAC organization news identity/owner required.");
  }
  for (const k of ["regionScope", "federalState", "category", "city"]) {
    if (before[k] !== old[k]) throw new Error(`Production baseline differs: ${k}.`);
  }
  if (before.sourceURL !== old.canonicalURL || Date.parse(before.publishedAt) !== old.publishedAt.getTime()) throw new Error("Production source/date differs from baseline.");
  for (const [lang, prefix] of [["uk", ""], ["de", "de"]]) {
    for (const k of ["title", "subtitle", "body"]) {
      const key = prefix ? prefix + k[0].toUpperCase() + k.slice(1) : k;
      if (before.localizations?.[lang]?.[k] !== old[key]) throw new Error(`Production baseline differs: ${lang}.${k}.`);
    }
  }
  for (const k of ["title", "subtitle", "body"]) if (before[k] !== old[k]) throw new Error(`Production baseline differs: ${k}.`);
  if (before.summary !== old.subtitle) throw new Error("Production baseline differs: summary.");
  if (before.mediaMetadata?.credit !== old.imageCredit || before.mediaMetadata?.alternativeText !== old.imageAlternativeText || !before.imageURL?.startsWith("https://")) throw new Error("Production cover differs from baseline.");
  if (old.title === next.title && old.subtitle === next.subtitle && old.body === next.body && old.deTitle === next.deTitle && old.deSubtitle === next.deSubtitle && old.deBody === next.deBody) throw new Error("No material text amendment.");
  return {id, fields: {title: next.title, subtitle: next.subtitle, summary: next.subtitle, body: next.body,
    localizations: {uk: {title: next.title, subtitle: next.subtitle, body: next.body}, de: {title: next.deTitle, subtitle: next.deSubtitle, body: next.deBody}},
    publishedAt: next.publishedAt, updatedAt: now}};
}

async function requireOwnedLocks(runId, threadId, now) {
  if (!runId || !threadId) throw new Error("Live amendment requires runId and threadId.");
  const base = join(homedir(), ".codex/uac-content-automation");
  const owners = await Promise.all([
    load(join(base, "content-publish.lock/owner.json")),
    load(join(base, "progress-v2/news-austria-regions.json.lock/owner.json")),
  ]);
  if (!owners[0].generation || owners.some((owner) => (owner.runId ?? owner.ownerRunId) !== runId || owner.threadId !== threadId || !(Date.parse(owner.expiresAt) > now.getTime())) || owners[0].generation !== owners[1].generation) {
    throw new Error("Both unexpired news locks must belong to this run/thread/generation.");
  }
}

export async function amendPublishedNews(config, {apply = false, fetchImpl = fetch, getAccessToken = contentAutomationAccessToken, checkLocks = requireOwnedLocks, readback = readbackPublishedNews, now = new Date()} = {}) {
  const review = await load(config.reviewPath);
  if (review.sourceEventKind !== "material_update") throw new Error("An amendment requires reviewed material_update evidence.");
  const age = now - new Date(review.primaryCheckedAt);
  if (!Number.isFinite(age) || age < -300_000 || age > 600_000) throw new Error("Amendment source must be rechecked within ten minutes.");
  const [oldRaw, newRaw] = await Promise.all([load(config.baselineManifestPath).then(one), load(config.manifestPath).then(one)]);
  const baselineReview = await load(config.baselineReviewPath);
  if (!baselineReview.image || JSON.stringify(review.image) !== JSON.stringify(baselineReview.image)) {
    throw new Error("An amendment must retain the exact reviewed cover provenance.");
  }
  const retainedCoverSHA256 = hash(await readFile(oldRaw.imagePath));
  if (retainedCoverSHA256 !== baselineReview.image.sha256) throw new Error("Retained cover file differs from its original reviewed hash.");
  const baselineReadback = await readback(config.baselineManifestPath, config.organizationId);
  if (!baselineReadback.allVerified || baselineReadback.coverSHA256 !== retainedCoverSHA256) {
    throw new Error("Current production does not verify the retained cover baseline.");
  }
  // The amendment updates bilingual text only. The exact old cover was verified
  // against both its original review hash and a fresh production read-back above.
  const editorial = await reviewNewsForPublication(config.manifestPath, config.reviewPath, now, {allowRetainedCover: true});
  const token = await getAccessToken();
  const id = deterministicContentId("news", config.organizationId, editorial.canonicalURL);
  const url = `https://firestore.googleapis.com/v1/projects/ukrainiancommunity-dbd5f/databases/(default)/documents/news/${id}`;
  const headers = {Authorization: `Bearer ${token}`, "Content-Type": "application/json"};
  const response = await fetchImpl(url, {headers});
  if (!response.ok) throw new Error(`Amendment production read failed (${response.status}).`);
  const record = await response.json();
  if (!record.updateTime) throw new Error("Production updateTime required.");
  const before = Object.fromEntries(Object.entries(record.fields).map(([k, v]) => [k, decode(v)]));
  const plan = buildNewsAmendment(before, oldRaw, newRaw, config.organizationId, now);
  const baselineSHA256 = hash(await readFile(config.baselineManifestPath));
  if (!apply) {
    const receipt = {dryRun: true, status: "amend_existing", contentId: id, expectedUpdateTime: record.updateTime,
      manifestSHA256: editorial.manifestSHA256, baselineSHA256, editorial, reason: review.materialChange,
      updateMask: Object.keys(plan.fields), before: record, plannedFields: plan.fields};
    await writeFile(config.planPath, JSON.stringify(receipt, null, 2) + "\n", {flag: "wx"});
    return receipt;
  }
  const dry = await load(config.planPath);
  if (dry.status !== "amend_existing" || dry.contentId !== id || dry.manifestSHA256 !== editorial.manifestSHA256 || dry.baselineSHA256 !== baselineSHA256 || dry.expectedUpdateTime !== record.updateTime) throw new Error("Dry-run/production changed; create a fresh amendment plan.");
  await checkLocks(config.runId, config.threadId, now);
  const patchURL = new URL(url);
  for (const field of Object.keys(plan.fields)) patchURL.searchParams.append("updateMask.fieldPaths", field);
  patchURL.searchParams.set("currentDocument.updateTime", record.updateTime);
  const result = await fetchImpl(patchURL, {method: "PATCH", headers,
    body: JSON.stringify({fields: Object.fromEntries(Object.entries(plan.fields).map(([k, v]) => [k, encode(v)]))})});
  if (!result.ok) throw new Error(`Conditional news amendment failed (${result.status}); reconcile production before retry.`);
  const updated = await result.json();
  return {dryRun: false, status: "amended_existing", contentId: id, beforeUpdateTime: record.updateTime, updateTime: updated.updateTime,
    manifestSHA256: editorial.manifestSHA256, reason: review.materialChange, updateMask: Object.keys(plan.fields), editorial};
}

export async function recordVerifiedAmendment(config, result) {
  const receipt = await readbackPublishedNews(config.manifestPath, config.organizationId);
  const receiptPath = config.readbackPath ?? `${config.resultPath}.readback.json`;
  await writeFile(receiptPath, JSON.stringify(receipt, null, 2) + "\n", {flag: "wx"});
  if (!receipt.allVerified || receipt.contentId !== result.contentId) throw new Error("Amendment production read-back differs; reconcile before another write.");
  const directory = join(homedir(), ".codex/uac-content-automation/progress-v3/news-scopes/amendments");
  await mkdir(directory, {recursive: true});
  const pointer = {contentId: result.contentId, amendedAt: receipt.readAt, manifestPath: resolve(config.manifestPath),
    baselineManifestPath: resolve(config.baselineManifestPath), reviewPath: resolve(config.reviewPath),
    resultPath: resolve(config.resultPath), readbackReceiptPath: resolve(receiptPath), allVerified: true};
  const temporary = join(directory, `${result.contentId}.${process.pid}.tmp`);
  await writeFile(temporary, JSON.stringify(pointer, null, 2) + "\n", {flag: "wx"});
  await rename(temporary, join(directory, `${result.contentId}.json`));
  return pointer;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const [path, mode] = process.argv.slice(2);
    if (!path || (mode && mode !== "--apply")) throw new Error("Usage: newsAmendPublished.mjs <config.json> [--apply]");
    const config = await load(path);
    const result = await amendPublishedNews(config, {apply: mode === "--apply"});
    if (mode === "--apply") {
      await writeFile(config.resultPath, JSON.stringify(result, null, 2) + "\n", {flag: "wx"});
      await recordVerifiedAmendment(config, result);
    }
    console.log(JSON.stringify({status: result.status, contentId: result.contentId, dryRun: result.dryRun}));
  } catch (error) {console.error(error.message); process.exitCode = 1;}
}
