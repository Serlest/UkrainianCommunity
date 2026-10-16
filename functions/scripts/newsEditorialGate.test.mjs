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
  publishedAt: "2026-10-12T10:55:00Z", category: "communityAndIntegration",
  sources: [
    {url: primaryURL, title: "Stadt Wien", isPrimary: true, verificationRole: "officialPrimary"},
    {url: "https://orf.at/stories/example", title: "ORF", isPrimary: false, verificationRole: "independent"},
  ],
};
const review = {
  scope: "wien", sourceEventDate: "2026-10-12", sourceEventAt: "2026-10-12T10:00:00Z",
  sourceEventKind: "new",
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

test("ASFINAG active notices accept one official source and the checked live-list URL", () => {
  const url = "https://routenplaner.asfinag.at/?activeTab=traffic-messages&language=de";
  const item = {...manifest, category: "transport", sourcePolicy: "asfinag_official_notice",
    canonicalURL: url, sources: [{url, title: "ASFINAG", isPrimary: true,
      verificationRole: "officialPrimary"}]};
  const checked = {...review, evidenceMode: "official", primaryURL: url,
    primaryCheckedAt: "2026-10-12T10:58:00Z", primaryPageKind: "live_notice_list",
    activeNoticeConfirmed: true, noticeEvidence: "A9 Plabutschtunnel northbound closure displayed in the freshly opened official list.",
    independentURL: undefined, independentCheckedAt: undefined, independentOpened: undefined,
    image: {...review.image, generatedForURL: url}};
  const result = validateNewsEditorialReview(item, checked, now);
  assert.equal(result.item.sources.length, 1);
  assert.equal(result.item.sourcePolicy, "asfinag_official_notice");
  assert.throws(() => validateNewsEditorialReview(item, {...checked, activeNoticeConfirmed: false}, now), /verified active notice/);
  assert.throws(() => validateNewsEditorialReview(item, {...checked, primaryCheckedAt: "2026-10-12T10:45:00Z"}, now), /freshness window/);
  assert.throws(() => validateNewsEditorialReview(item, {...checked, evidenceMode: "editorial"}, now), /official mode/);
  assert.throws(() => validateNewsEditorialReview({...item, sourcePolicy: undefined}, checked, now), /actual primary/);
  for (const badURL of ["https://asfinag.at.example.com/notice", "http://routenplaner.asfinag.at/", "https://orf.at/notice"]) {
    assert.throws(() => validateNewsEditorialReview({...item,
      sources: [{...item.sources[0], url: badURL}]}, checked, now), /official ASFINAG/);
  }
  assert.throws(() => validateNewsEditorialReview({...item, category: "health"}, checked, now), /official ASFINAG/);
});

test("regional reporting accepts one approved full newspaper article without seeking corroboration", () => {
  const url = "https://www.tt.com/artikel/123/tiroler-regionalnachricht";
  const item = {...manifest, federalState: "tirol", canonicalURL: url,
    sources: [{url, title: "Tiroler Tageszeitung", isPrimary: true, verificationRole: "editorialPrimary"}]};
  const checked = {...review, scope: "tirol", primaryURL: url, evidenceMode: "editorial",
    storyClass: "public_interest", primaryPublisherConfirmed: true, primaryFullTextVerified: true,
    paywallRestricted: false, claimsRequireOfficialAuthority: false, commonWireOriginExcluded: true,
    independentURL: undefined, independentCheckedAt: undefined, independentOpened: undefined,
    image: {...review.image, generatedForURL: url}};
  assert.equal(validateNewsEditorialReview(item, checked, now).evidenceMode, "editorial");
  for (const field of ["primaryFullTextVerified", "primaryPublisherConfirmed"]) {
    assert.throws(() => validateNewsEditorialReview(item, {...checked, [field]: false}, now), /Editorial news/);
  }
  assert.throws(() => validateNewsEditorialReview(item, {...checked, paywallRestricted: true}, now), /Editorial news/);
  assert.equal(validateNewsEditorialReview({...item, category: "health"}, checked, now).evidenceMode, "editorial");
  assert.throws(() => validateNewsEditorialReview({...item, federalState: "wien"}, {...checked, scope: "wien"}, now), /primary source/);
  const lead = "https://www.meinbezirk.at/tirol/c-lokales/beispiel_a123";
  assert.throws(() => validateNewsEditorialReview({...item, canonicalURL: lead,
    sources: [{...item.sources[0], url: lead}]}, {...checked, primaryURL: lead}, now), /primary source/);
  const orf = "https://tirol.orf.at/stories/123/";
  assert.throws(() => validateNewsEditorialReview({...item, canonicalURL: orf,
    sources: [{...item.sources[0], url: orf}, manifest.sources[1]]}, {...checked, primaryURL: orf}, now), /publisher group/);
});

test("one opened official authority article needs no independent review fields", () => {
  const item = {...manifest, sources: [manifest.sources[0]]};
  const checked = {...review, independentURL: undefined, independentCheckedAt: undefined,
    independentOpened: undefined};
  assert.equal(validateNewsEditorialReview(item, checked, now).item.sources.length, 1);
  assert.throws(() => validateNewsEditorialReview(item, {...checked, primaryOpened: false}, now), /actual primary/);
  assert.throws(() => validateNewsEditorialReview(item, {...checked, officialAuthorityConfirmed: false}, now), /approved source registry/);
  assert.throws(() => validateNewsEditorialReview({...item, sources: []}, checked, now), /at least 1 verified source/);
});

test("news editorial gate accepts today's official date without an invented source time", () => {
  const result = validateNewsEditorialReview(manifest,
    {...review, sourceEventAt: undefined}, now);
  assert.equal(result.sourceEventDate, "2026-10-12");
  assert.equal(result.sourceEventAt, null);
  assert.equal(result.item.publishedAt.toISOString(), "2026-10-12T10:55:00.000Z");
});

test("a verified future service change needs concrete relevance but no invented immediate application step", () => {
  const relevant = {...review, readerAction: undefined,
    readerRelevance: "Сім’ї в регіоні отримають більше місць для домашньої психіатричної допомоги дітям у наступному році."};
  assert.equal(validateNewsEditorialReview(manifest, relevant, now).item.regionScope, "federalState");
  assert.throws(() => validateNewsEditorialReview(manifest,
    {...review, readerAction: undefined, readerRelevance: "Важливо"}, now), /readerRelevance/);
});

test("today is determined in Europe/Vienna, including after UTC midnight offset", () => {
  const viennaAfterMidnight = new Date("2026-10-12T22:30:00Z");
  const item = {...manifest, publishedAt: "2026-10-12T22:25:00Z"};
  const datedToday = {...review, sourceEventDate: "2026-10-13", sourceEventAt: undefined,
    primaryCheckedAt: "2026-10-12T22:20:00Z", independentCheckedAt: "2026-10-12T22:22:00Z",
    image: {...review.image, generatedAt: "2026-10-12T22:23:00Z"}};
  assert.equal(validateNewsEditorialReview(item, datedToday, viennaAfterMidnight).sourceEventDate,
    "2026-10-13");
  assert.throws(() => validateNewsEditorialReview(item,
    {...datedToday, sourceEventDate: "2026-10-12"}, viennaAfterMidnight), /today's official news date/);
});

test("news editorial gate rejects old dates, stale post times, indirect and unproven material", () => {
  assert.throws(() => validateNewsEditorialReview(manifest,
    {...review, sourceEventDate: "2026-10-11", sourceEventAt: undefined}, now), /today's official news date/);
  assert.throws(() => validateNewsEditorialReview({...manifest, publishedAt: "2026-10-12T10:00:00Z"},
    review, now), /freshness window/);
  assert.throws(() => validateNewsEditorialReview(manifest,
    {...review, sourceEventAt: "2026-10-11T10:00:00Z"}, now), /does not match/);
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
    assert.equal(receipt.sourceEventDate, "2026-10-12");
    assert.equal(receipt.publishedAt, "2026-10-12T10:55:00.000Z");
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
