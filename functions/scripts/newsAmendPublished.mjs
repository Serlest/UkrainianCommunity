#!/usr/bin/env node
import {createHash} from "node:crypto";
import {readFile, writeFile, mkdir, rename} from "node:fs/promises";
import {homedir} from "node:os";
import {isAbsolute, join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {contentAutomationAccessToken} from "./contentAutomationCredential.mjs";
import {reviewNewsForPublication} from "./newsEditorialGate.mjs";
import {readbackPublishedNews} from "./newsProductionReadback.mjs";
import {convertCoverToCanonicalJPEG} from "./publishVerifiedContent.mjs";
import {deterministicContentId, normalizeAndValidateManifestItem, EXPECTED_OWNER_ID} from "./verifiedContentPublisherCore.mjs";
import {canonicalizeURL} from "./contentPlanningBridgeSummary.mjs";
import {readNewsArticle} from "./newsReadArticle.mjs";

const hash = (x) => createHash("sha256").update(x).digest("hex");
const load = async (p) => JSON.parse(await readFile(p, "utf8"));
const one = (d) => {
  const a = Array.isArray(d) ? d : d.items ?? [d];
  if (a.length !== 1) throw new Error("Amend exactly one existing news article.");
  return a[0];
};

// Existing-record recovery only. Never available to the create-only publisher.
// A removed notice alone cannot enter this route: a hash-bound closed report and
// the previously read full operator text must both explicitly confirm the end.
export async function validateArchivedEndCorrection(proof, oldRaw, newRaw, review, organizationId, now,
    {readArticle = readNewsArticle} = {}) {
  if (!proof || proof.kind !== "ended_oebb_restriction" ||
      !isAbsolute(proof.articlePath ?? "") || !isAbsolute(proof.reportPath ?? "") ||
      !/^[a-f0-9]{64}$/.test(proof.articleSHA256 ?? "") || !/^[a-f0-9]{64}$/.test(proof.reportSHA256 ?? "")) {
    throw new Error("Unsupported archived correction proof.");
  }
  const [articleBytes, reportBytes] = await Promise.all([readFile(proof.articlePath), readFile(proof.reportPath)]);
  if (hash(articleBytes) !== proof.articleSHA256 || hash(reportBytes) !== proof.reportSHA256) throw new Error("Archived correction evidence hash mismatch.");
  const article = JSON.parse(articleBytes), report = JSON.parse(reportBytes);
  const publishedSourceURL = canonicalizeURL(oldRaw.sourceURL ?? oldRaw.sources?.find((s) => s.isPrimary)?.url);
  const evidenceURL = canonicalizeURL(article.requestedArticleURL);
  const cid = deterministicContentId("news", organizationId, publishedSourceURL);
  const entry = [...(report.unresolvedPublishedIncidents ?? []), ...(report.resolvedPublishedIncidents ?? [])]
    .find((x) => x.contentId === cid);
  if (new URL(publishedSourceURL).hostname !== "www.unsereoebb.at" || new URL(evidenceURL).hostname !== "www.unsereoebb.at" ||
      entry?.active !== false || canonicalizeURL(entry.sourceURL) !== evidenceURL ||
      canonicalizeURL(entry.publishedSourceURL ?? entry.sourceURL) !== publishedSourceURL ||
      canonicalizeURL(review.primaryURL) !== evidenceURL || article.textTruncated !== false || article.accessRestricted !== false ||
      typeof article.text !== "string" || article.text.length < 180) throw new Error("Closed report/official full text does not establish the same ended publication.");
  const ended = new Date(entry.endedAt), updated = new Date(entry.sourceUpdatedAt), observed = new Date(entry.checkedAt ?? report.checkedAt);
  if (![ended, updated, observed].every((x) => Number.isFinite(x.getTime())) || ended > updated || updated > observed || observed > now ||
      ended < new Date(oldRaw.publishedAt) || review.sourceEventAt !== entry.sourceUpdatedAt) throw new Error("Archived end/update/observation dates invalid.");
  const local = Object.fromEntries(new Intl.DateTimeFormat("en-GB", {timeZone: "Europe/Vienna", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23"}).formatToParts(updated).map((x) => [x.type, x.value]));
  const sourceEventDate = `${local.year}-${local.month}-${local.day}`;
  const endLocal = new Intl.DateTimeFormat("en-GB", {timeZone: "Europe/Vienna", hour: "2-digit", minute: "2-digit", hourCycle: "h23"}).format(ended);
  if (review.sourceEventDate !== sourceEventDate || !article.text.includes(`Bis ${endLocal} Uhr war`) ||
      !article.text.includes(`Aktualisiert : ${local.day}.${local.month}.${local.year} ${local.hour}:${local.minute}`) ||
      typeof proof.endQuote !== "string" || !proof.endQuote.includes(`Bis ${endLocal} Uhr war`) || !article.text.includes(proof.endQuote)) {
    throw new Error("Archived text does not explicitly confirm the reviewed end/update time.");
  }
  if (!Array.isArray(proof.routeAnchors) || new Set(proof.routeAnchors).size < 2 ||
      proof.routeAnchors.some((anchor) => typeof anchor !== "string" || anchor.length < 4 ||
        !article.text.includes(anchor) || !oldRaw.deBody.includes(anchor) || !newRaw.deBody.includes(anchor))) {
    throw new Error("Archived correction route does not match both article versions.");
  }
  // Reopen the actual migrated source. Its shell is recorded as unknown; it is
  // never treated as restoration. New nonempty content requires a new review.
  const current = await readArticle(evidenceURL);
  if (canonicalizeURL(current.requestedArticleURL) !== evidenceURL || current.accessRestricted !== false ||
      (current.text?.trim() && current.text.trim() !== article.text.trim())) throw new Error("Archived correction source now has different content; review it before correcting.");
  return {kind: proof.kind, contentId: cid, publishedSourceURL, evidenceURL, sourceEventDate,
    endedAt: entry.endedAt, sourceUpdatedAt: entry.sourceUpdatedAt, observedAt: observed.toISOString(),
    checkedAt: now.toISOString(), articlePath: resolve(proof.articlePath), articleSHA256: hash(articleBytes),
    reportPath: resolve(proof.reportPath), reportSHA256: hash(reportBytes), endQuote: proof.endQuote,
    currentSourceTextSHA256: hash(current.text ?? ""), currentSourceHasText: Boolean(current.text?.trim())};
}
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

export async function amendPublishedNews(config, {apply = false, fetchImpl = fetch, getAccessToken = contentAutomationAccessToken, checkLocks = requireOwnedLocks, readback = readbackPublishedNews, convertCover = convertCoverToCanonicalJPEG, readArticle = readNewsArticle, now = new Date()} = {}) {
  const review = await load(config.reviewPath);
  if (review.sourceEventKind !== "material_update") throw new Error("An amendment requires reviewed material_update evidence.");
  const age = now - new Date(review.primaryCheckedAt);
  if (!Number.isFinite(age) || age < -300_000 || age > 600_000) throw new Error("Amendment source must be rechecked within ten minutes.");
  const [oldRaw, newRaw] = await Promise.all([load(config.baselineManifestPath).then(one), load(config.manifestPath).then(one)]);
  const baselineReview = await load(config.baselineReviewPath);
  if (!baselineReview.image || JSON.stringify(review.image) !== JSON.stringify(baselineReview.image)) {
    throw new Error("An amendment must retain the exact reviewed cover provenance.");
  }
  const retainedCoverSourceSHA256 = hash(await readFile(oldRaw.imagePath));
  if (retainedCoverSourceSHA256 !== baselineReview.image.sha256) throw new Error("Retained cover file differs from its original reviewed hash.");
  const retainedPublishedCover = await convertCover(oldRaw.imagePath);
  const retainedPublishedCoverSHA256 = hash(retainedPublishedCover.bytes);
  const baselineReadback = await readback(config.baselineManifestPath, config.organizationId);
  if (!baselineReadback.allVerified || baselineReadback.coverSHA256 !== retainedPublishedCoverSHA256) {
    throw new Error("Current production cover does not match the canonical conversion of the retained baseline cover.");
  }
  // Match the publisher's deterministic PNG/WebP-to-JPEG conversion. The
  // amendment updates bilingual text only; no image is uploaded or replaced.
  const archivedCorrection = config.archivedEndCorrection ? await validateArchivedEndCorrection(config.archivedEndCorrection,
    oldRaw, newRaw, review, config.organizationId, now, {readArticle}) : null;
  const editorial = await reviewNewsForPublication(config.manifestPath, config.reviewPath, now, {allowRetainedCover: true, archivedCorrection});
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
  const stableProof = (x) => x ? {...x, checkedAt: undefined} : null;
  if (JSON.stringify(stableProof(dry.editorial.archivedCorrection)) !== JSON.stringify(stableProof(archivedCorrection))) throw new Error("Archived correction proof changed after dry run.");
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
