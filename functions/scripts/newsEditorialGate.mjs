#!/usr/bin/env node

import {createHash, randomUUID} from "node:crypto";
import {readFile, rename, unlink, writeFile} from "node:fs/promises";
import {isAbsolute, resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {canonicalizeURL} from "./contentPlanningBridgeSummary.mjs";
import {NEWS_EDITORIAL_SOURCES} from "./newsEditorialSources.mjs";
import {NEWS_SCOPES} from "./newsScopeCoordination.mjs";
import {normalizeAndValidateManifestItem} from "./verifiedContentPublisherCore.mjs";

const hour = 60 * 60 * 1000;
const maxArticleAge = 24 * hour;
const maxSourceReviewAge = 2 * hour;
const maxPublicationStampAge = 10 * 60 * 1000;

function viennaDate(time) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Vienna", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(time).map(({type, value}) => [type, value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function officialDate(value) {
  const parsed = typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ?
    new Date(`${value}T00:00:00Z`) : new Date(NaN);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new Error("sourceEventDate needs a valid official calendar date.");
  }
  return value;
}

function authorityRoot(value) {
  const hostname = new URL(value).hostname.toLowerCase();
  const parts = hostname.split(".");
  return parts.slice(hostname.endsWith(".gv.at") ? -3 : -2).join(".");
}

function exactTime(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new Error(`${field} needs a dated source timestamp with timezone.`);
  }
  const time = new Date(value);
  if (!Number.isFinite(time.getTime())) throw new Error(`${field} is invalid.`);
  return time;
}

function recent(time, now, maximumAge, field) {
  const age = now.getTime() - time.getTime();
  if (age < -5 * 60_000 || age > maximumAge) throw new Error(`${field} is outside the allowed freshness window.`);
  return age;
}

function substantiveText(value, field, minimum = 30) {
  if (typeof value !== "string" || value.trim().length < minimum) {
    throw new Error(`${field} must explain the verified fact concretely.`);
  }
}

export function validateNewsEditorialReview(rawItem, review, now = new Date()) {
  if (!NEWS_SCOPES.includes(review?.scope)) throw new Error("Review needs one news scope.");
  const target = review.scope === "austria" ? "austria" : review.scope;
  const item = normalizeAndValidateManifestItem(rawItem, target);
  if (item.kind !== "news") throw new Error("The news editorial gate accepts news only.");
  if (!isAbsolute(item.imagePath)) throw new Error("The generated news imagePath must be absolute.");

  const eventDate = officialDate(review.sourceEventDate);
  if (eventDate !== viennaDate(now)) {
    throw new Error("sourceEventDate is not today's official news date in Europe/Vienna.");
  }
  const eventAt = review.sourceEventAt == null ? null : exactTime(review.sourceEventAt, "sourceEventAt");
  if (eventAt && viennaDate(eventAt) !== eventDate) {
    throw new Error("sourceEventAt does not match the official sourceEventDate.");
  }
  recent(item.publishedAt, now, maxPublicationStampAge, "publishedAt");
  if (!["new", "material_update"].includes(review.sourceEventKind)) {
    throw new Error("sourceEventKind must be new or material_update.");
  }
  if (review.sourceEventKind === "material_update") {
    substantiveText(review.materialChange, "materialChange", 40);
  }
  recent(exactTime(review.primaryCheckedAt, "primaryCheckedAt"), now,
    maxSourceReviewAge, "primaryCheckedAt");
  recent(exactTime(review.independentCheckedAt, "independentCheckedAt"), now,
    maxSourceReviewAge, "independentCheckedAt");
  if (review.primaryOpened !== true || review.independentOpened !== true ||
      review.primaryPageKind !== "article_or_notice" || review.officialAuthorityConfirmed !== true) {
    throw new Error("Open the direct official article/notice and independent source before publication.");
  }
  if (canonicalizeURL(review.primaryURL) !== item.canonicalURL) {
    throw new Error("Reviewed official primary URL must match the published direct source URL.");
  }
  const approvedAuthorityRoots = new Set(NEWS_EDITORIAL_SOURCES
    .filter((source) => source.scopes.includes(review.scope))
    .map((source) => authorityRoot(source.url)));
  if (!approvedAuthorityRoots.has(authorityRoot(item.canonicalURL))) {
    throw new Error("Official primary site is not in the approved source registry for this scope.");
  }
  if (!item.sources.some((source) => source.verificationRole === "independent" &&
      canonicalizeURL(source.url) === canonicalizeURL(review.independentURL))) {
    throw new Error("Reviewed independent URL must match a verified independent source.");
  }
  substantiveText(review.practicalEffect, "practicalEffect", 40);
  substantiveText(review.territoryEvidence, "territoryEvidence", 30);
  substantiveText(review.affectedPeople, "affectedPeople", 20);
  substantiveText(review.readerAction, "readerAction", 20);
  if (review.ukDeFactParityConfirmed !== true || review.originalTextConfirmed !== true ||
      review.excludedTopicsAbsent !== true) {
    throw new Error("Both original language versions need checked fact parity and editorial relevance.");
  }
  if (item.body.trim().length < 180 || item.deBody.trim().length < 180 ||
      (item.body.match(/\p{Script=Cyrillic}/gu) ?? []).length < 30 ||
      (item.deBody.match(/[A-Za-zÄÖÜäöüß]/g) ?? []).length < 80 ||
      item.body.trim() === item.deBody.trim()) {
    throw new Error("Ukrainian and German bodies must be substantive original articles.");
  }
  const image = review.image;
  if (image?.tool !== "image_gen" || image.generatedForURL == null ||
      canonicalizeURL(image.generatedForURL) !== item.canonicalURL ||
      image.photorealisticReviewed !== true || image.topicMatchReviewed !== true ||
      image.sourceImageCopied !== false ||
      !/^[a-f0-9]{64}$/i.test(image.sha256 ?? "")) {
    throw new Error("The cover needs generated-image provenance and visual review for this article.");
  }
  substantiveText(image.prompt, "image.prompt", 40);
  recent(exactTime(image.generatedAt, "image.generatedAt"), now, maxArticleAge, "image.generatedAt");
  return {item, imageSHA256: image.sha256.toLowerCase(), sourceEventDate: eventDate,
    sourceEventAt: eventAt};
}

export async function reviewNewsForPublication(manifestPath, reviewPath, now = new Date()) {
  const manifestBytes = await readFile(manifestPath);
  const raw = JSON.parse(manifestBytes.toString("utf8"));
  const rawItems = Array.isArray(raw) ? raw : Array.isArray(raw?.items) ? raw.items : [raw];
  if (rawItems.length !== 1) throw new Error("One news article is required per editorial review.");
  const review = JSON.parse(await readFile(reviewPath, "utf8"));
  const {item, imageSHA256, sourceEventDate, sourceEventAt} =
    validateNewsEditorialReview(rawItems[0], review, now);
  const actualImageSHA256 = createHash("sha256").update(await readFile(item.imagePath)).digest("hex");
  if (actualImageSHA256 !== imageSHA256) throw new Error("Generated image hash does not match the reviewed cover.");
  return {
    schemaVersion: 2, passed: true, reviewedAt: now.toISOString(), scope: review.scope,
    canonicalURL: item.canonicalURL, sourceEventDate,
    sourceEventAt: sourceEventAt?.toISOString() ?? null,
    publishedAt: item.publishedAt.toISOString(),
    manifestSHA256: createHash("sha256").update(manifestBytes).digest("hex"),
    imageSHA256: actualImageSHA256,
    primaryURL: item.canonicalURL,
  };
}

export async function writeNewsEditorialReceipt(path, receipt) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, JSON.stringify(receipt, null, 2) + "\n");
    await rename(temporary, path);
  } finally {
    await unlink(temporary).catch(() => {});
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [manifestPath, reviewPath, receiptPath] = process.argv.slice(2);
  if (!manifestPath || !reviewPath || !receiptPath) {
    console.error("Usage: node newsEditorialGate.mjs <manifest.json> <review.json> <receipt.json>");
    process.exitCode = 1;
  } else {
    try {
      const receipt = await reviewNewsForPublication(resolve(manifestPath), resolve(reviewPath));
      await writeNewsEditorialReceipt(resolve(receiptPath), receipt);
      console.log(JSON.stringify(receipt));
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
}
