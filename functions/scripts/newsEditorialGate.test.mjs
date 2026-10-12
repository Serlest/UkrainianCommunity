import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {reviewNewsForPublication, validateNewsEditorialReview} from "./newsEditorialGate.mjs";
import {parseNewsPublishArguments} from "./newsPublishingLocalBridge.mjs";

const now = new Date("2026-10-12T11:00:00Z");
const primaryURL = "https://www.wien.gv.at/presse/2026/neue-servicestelle";
const manifest = {
  kind: "news", state: "approved", missingFields: [], regionScope: "federalState", federalState: "wien",
  canonicalURL: primaryURL, imagePath: "/tmp/uac-generated-cover.png", imageAlternativeText: "Menschen in einer Servicestelle",
  title: "Нова консультаційна служба у Відні", subtitle: "Місто відкрило новий пункт допомоги.",
  body: "Місто Відень відкрило консультаційний пункт для мешканців. Він пояснює, як отримати допомогу та які документи потрібні для звернення. Перед візитом слід перевірити години роботи на офіційній сторінці й підготувати посвідчення особи.",
  deTitle: "Neue Beratungsstelle in Wien", deSubtitle: "Die Stadt hat eine neue Anlaufstelle eröffnet.",
  deBody: "Die Stadt Wien hat eine Beratungsstelle für Einwohner eröffnet. Dort erfahren sie, wie sie Unterstützung erhalten und welche Unterlagen für einen Termin nötig sind. Vor dem Besuch sollten sie die Öffnungszeiten auf der offiziellen Seite prüfen und einen Ausweis bereithalten.",
  publishedAt: "2026-10-12T10:00:00Z", category: "communityAndIntegration",
  sources: [
    {url: primaryURL, title: "Stadt Wien", isPrimary: true, verificationRole: "officialPrimary"},
    {url: "https://orf.at/stories/example", title: "ORF", isPrimary: false, verificationRole: "independent"},
  ],
};
const review = {
  scope: "wien", sourceEventAt: "2026-10-12T10:00:00Z", sourceEventKind: "new",
  primaryCheckedAt: "2026-10-12T10:45:00Z", independentCheckedAt: "2026-10-12T10:47:00Z",
  primaryOpened: true, independentOpened: true, primaryPageKind: "article_or_notice",
  officialAuthorityConfirmed: true, primaryURL, independentURL: "https://orf.at/stories/example",
  practicalEffect: "Мешканці отримали нове місце для консультацій про доступні послуги.",
  territoryEvidence: "Офіційне повідомлення прямо стосується мешканців Відня.",
  affectedPeople: "Мешканці Відня, яким потрібна консультація.",
  readerAction: "Перевірити години роботи і взяти посвідчення особи.",
  ukDeFactParityConfirmed: true, originalTextConfirmed: true, excludedTopicsAbsent: true,
  image: {tool: "image_gen", generatedForURL: primaryURL, generatedAt: "2026-10-12T10:50:00Z",
    prompt: "Photorealistic public service desk in Vienna, people receiving guidance, no text or logos",
    photorealisticReviewed: true, topicMatchReviewed: true, sourceImageCopied: false,
    sha256: createHash("sha256").update("generated-image-bytes").digest("hex")},
};

test("news editorial gate accepts a fresh verified bilingual package", () => {
  const result = validateNewsEditorialReview(manifest, review, now);
  assert.equal(result.item.canonicalURL, primaryURL);
  assert.equal(result.item.regionScope, "federalState");
});

test("news editorial gate rejects stale, indirect, incomplete, and unproven material", () => {
  assert.throws(() => validateNewsEditorialReview({...manifest, publishedAt: "2026-10-10T10:00:00Z"},
    {...review, sourceEventAt: "2026-10-10T10:00:00Z"}, now), /freshness window/);
  assert.throws(() => validateNewsEditorialReview(manifest,
    {...review, primaryURL: "https://www.wien.gv.at/"}, now), /direct source URL/);
  const mediaAsPrimary = {...manifest, canonicalURL: "https://orf.at/stories/example",
    sources: [{url: "https://orf.at/stories/example", title: "ORF", isPrimary: true,
      verificationRole: "officialPrimary"}, {...manifest.sources[0], isPrimary: false,
      verificationRole: "independent"}]};
  assert.throws(() => validateNewsEditorialReview(mediaAsPrimary,
    {...review, primaryURL: "https://orf.at/stories/example"}, now), /approved source registry/);
  assert.throws(() => validateNewsEditorialReview({...manifest, deBody: "Kurze Notiz."}, review, now),
    /substantive original articles/);
  assert.throws(() => validateNewsEditorialReview(manifest,
    {...review, image: {...review.image, sourceImageCopied: true}}, now), /generated-image provenance/);
});

test("editorial receipt is bound to exact manifest and generated cover bytes", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uac-news-editorial-"));
  try {
    const manifestPath = join(directory, "manifest.json");
    const reviewPath = join(directory, "review.json");
    const imagePath = join(directory, "cover.png");
    await writeFile(manifestPath, JSON.stringify({...manifest, imagePath}));
    await writeFile(reviewPath, JSON.stringify(review));
    await writeFile(imagePath, "generated-image-bytes");
    const receipt = await reviewNewsForPublication(manifestPath, reviewPath, now);
    assert.equal(receipt.passed, true);
    assert.equal(receipt.scope, "wien");
    await writeFile(imagePath, "copied-or-changed-image");
    await assert.rejects(() => reviewNewsForPublication(manifestPath, reviewPath, now), /image hash/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("news publishing bridge requires review and receipt and keeps publisher options", () => {
  assert.throws(() => parseNewsPublishArguments(["publish", "manifest.json", "--dry-run"]),
    /requires review and receipt/);
  const parsed = parseNewsPublishArguments(["publish", "manifest.json", "--review", "review.json",
    "--receipt", "receipt.json", "--organization-id", "uac-wien-info", "--federal-state", "wien", "--dry-run"]);
  assert.deepEqual(parsed.publisherArgs, ["publish", "manifest.json", "--organization-id",
    "uac-wien-info", "--federal-state", "wien", "--dry-run"]);
});
