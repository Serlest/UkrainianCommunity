import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, rm, writeFile} from "node:fs/promises";
import {describe, test} from "node:test";
import {tmpdir} from "node:os";
import {join} from "node:path";

import {
  EXPECTED_OWNER_ID,
  buildContentDocument,
  buildEventOccurrences,
  classifyLegacyDuplicate,
  contentIdentityLockClaims,
  deterministicContentId,
  documentsSemanticallyMatch,
  legacyDocumentsSemanticallyMatch,
  normalizeAndValidateManifestItem,
  normalizePublicationTarget,
  validateOrganization,
  validatePublicationOrganization,
} from "./verifiedContentPublisherCore.mjs";
import {
  CANONICAL_COVER_CONTENT_TYPE,
  MAXIMUM_CANONICAL_COVER_BYTES,
  assertUniqueIdentityClaims,
  buildExistingDuplicateRecord,
  buildIdentityLockDocument,
  canonicalCoverStoragePath,
  parseArguments,
  prepareImage,
  resolvePublicationTarget,
} from "./publishVerifiedContent.mjs";
import {parsePublishCommand} from "./contentPublishingLocalBridge.mjs";

const organizationId = "regional-uac-wien";
const organization = {
  id: organizationId,
  name: "UAC Wien Info",
  moderationStatus: "approved",
  ownerId: EXPECTED_OWNER_ID,
  regionScope: "federalState",
  federalState: "wien",
  logoURL: "https://firebasestorage.googleapis.com/logo.png",
};

describe("verified content publisher core", () => {
  test("uses the required deterministic sha1 identity", () => {
    const canonicalURL = "https://example.at/events/community-day";
    const expected = createHash("sha1")
      .update(`event:${organizationId}:${canonicalURL}`)
      .digest("hex");
    assert.equal(deterministicContentId("event", organizationId, canonicalURL), expected);
    assert.equal(expected.length, 40);
    assert.equal(
      deterministicContentId(
        "event",
        organizationId,
        "https://example.at/events/community-day/?utm_source=automation#tickets"
      ),
      expected
    );
  });

  test("derives identity from the single primary source and treats provided canonicalURL as context", () => {
    const manifest = eventManifest();
    manifest.canonicalURL = "https://example.at/events/overview/?utm_campaign=uac#program";
    manifest.sources.push({
      url: "https://example.at/events/overview/",
      title: "Огляд програми",
      isPrimary: false,
      verificationRole: "municipalCalendar",
    });
    manifest.sources[0].url = "https://example.at/events/community-day/?utm_source=official#schedule";
    const item = normalizeAndValidateManifestItem(manifest, "wien");
    assert.equal(item.canonicalURL, "https://example.at/events/community-day");
    assert.equal(
      deterministicContentId(item.kind, organizationId, item.canonicalURL),
      deterministicContentId(item.kind, organizationId, manifest.sources[0].url)
    );
    assert.throws(
      () => normalizeAndValidateManifestItem({...manifest, canonicalURL: "https://unverified.example/event"}, "wien"),
      /verified source URLs/
    );
  });

  test("accepts only the approved regional organization owned by UAC", () => {
    assert.equal(validateOrganization(organization, organizationId, "wien"), organization);
    assert.throws(
      () => validateOrganization({...organization, moderationStatus: "pendingReview"}, organizationId, "wien"),
      /not approved/
    );
    assert.throws(
      () => validateOrganization({...organization, ownerId: "another-owner"}, organizationId, "wien"),
      /expected UAC owner/
    );
    assert.throws(
      () => validateOrganization({...organization, federalState: "tirol"}, organizationId, "wien"),
      /does not belong/
    );
    assert.throws(
      () => validateOrganization({...organization, logoURL: null}, organizationId, "wien"),
      /organization.logoURL/
    );
  });

  test("converts optional event endings without persisting an unsupported flag", () => {
    const contentId = "content-id";
    const occurrences = buildEventOccurrences([
      {startDate: "2026-10-02T18:00:00+02:00", endDate: "2026-10-02T20:00:00+02:00"},
      {startDate: "2026-10-01T17:00:00+02:00", hasExplicitEndDate: false},
    ], contentId);
    assert.equal(occurrences[0].hasExplicitEndDate, false);
    assert.equal(occurrences[0].endDate.toISOString(), occurrences[0].startDate.toISOString());
    assert.equal(occurrences[1].hasExplicitEndDate, true);

    const item = normalizeAndValidateManifestItem(eventManifest(), "wien");
    const document = buildContentDocument(item, organization, organizationId, "https://example.at/cover.png", new Date("2026-08-30T10:00:00Z"));
    assert.equal(document.startDate.toISOString(), "2026-10-01T15:00:00.000Z");
    assert.equal(document.endDate.toISOString(), "2026-10-02T18:00:00.000Z");
    assert.equal(document.occurrences[0].endDate.toISOString(), document.occurrences[0].startDate.toISOString());
    assert.equal("hasExplicitEndDate" in document, false);
    assert.equal("hasExplicitEndDate" in document.occurrences[0], false);
  });

  test("builds Ukrainian and German live news with manifest categories", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const document = buildContentDocument(item, organization, organizationId, "https://example.at/news.png", new Date("2026-08-30T10:00:00Z"));
    assert.deepEqual(document.localizations.uk, {
      title: "Нова послуга у Відні",
      subtitle: "Коротке пояснення",
      body: "Повний перевірений текст новини.",
    });
    assert.deepEqual(document.localizations.de, {
      title: "Neues Angebot in Wien",
      subtitle: "Kurze Erklärung",
      body: "Vollständiger geprüfter Nachrichtentext.",
    });
    assert.equal(document.category, "benefitsAndSupport");
    assert.deepEqual(document.additionalCategories, ["communityAndIntegration"]);
    assert.equal(document.summary, document.subtitle);
    assert.equal(document.regionScope, "federalState");
    assert.equal(document.federalState, "wien");
    assert.equal(document.organizationId, organizationId);
    assert.equal(document.moderationStatus, "approved");
  });

  test("supports nationwide news without inventing a federal state", () => {
    const nationwideOrganization = {
      ...organization,
      id: "central-uac",
      name: "UAC Austria Info",
      regionScope: "austria",
    };
    delete nationwideOrganization.federalState;
    const target = normalizePublicationTarget("country");
    validateOrganization(nationwideOrganization, nationwideOrganization.id, target);
    const item = normalizeAndValidateManifestItem(newsManifest(), target);
    const document = buildContentDocument(item, nationwideOrganization, nationwideOrganization.id, "https://example.at/news.png");
    assert.equal(document.regionScope, "austria");
    assert.equal("federalState" in document, false);
    assert.equal(document.sourceType, "organization");
    assert.equal(document.organizationId, nationwideOrganization.id);
    assert.throws(
      () => validateOrganization({...nationwideOrganization, federalState: "wien"}, nationwideOrganization.id, target),
      /must not have federalState/
    );
  });

  test("explicit regional UAC publishers can publish nationwide news without changing the audience", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "austria");
    for (const state of ["wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol", "vorarlberg", "steiermark", "kaernten", "burgenland"]) {
      const id = `uac-${state}-info`;
      const publisher = {...organization, id, federalState: state};
      assert.equal(validatePublicationOrganization(publisher, id, "austria", [item], state), publisher);
      const document = buildContentDocument(item, publisher, id, "https://example.at/news.png");
      assert.equal(document.regionScope, "austria");
      assert.equal("federalState" in document, false);
      assert.equal(document.organizationId, id);
      assert.equal(publisher.regionScope, "federalState");
      assert.equal(publisher.federalState, state);
      assert.throws(() => validatePublicationOrganization(publisher, id, "austria", [item]), /must use regionScope/);
      assert.throws(() => validatePublicationOrganization({...publisher, ownerId: "other"}, id, "austria", [item], state), /expected UAC owner/);
      assert.throws(() => validatePublicationOrganization({...publisher, moderationStatus: "pendingReview"}, id, "austria", [item], state), /not approved/);
      assert.throws(() => validatePublicationOrganization({...publisher, logoURL: null}, id, "austria", [item], state), /organization.logoURL/);
    }
  });

  test("regional publisher selection does not loosen regional, event, or publisher identity checks", () => {
    const id = "uac-tirol-info";
    const publisher = {...organization, id, federalState: "tirol"};
    const news = normalizeAndValidateManifestItem(newsManifest(), "austria");
    for (const items of [[], [{kind: "event"}], [news, {kind: "event"}]]) {
      assert.throws(() => validatePublicationOrganization(publisher, id, "austria", items, "tirol"), /only for Austria-wide news/);
    }
    assert.throws(() => validatePublicationOrganization(publisher, id, "tirol", [news], "tirol"), /only for Austria-wide news/);
    assert.throws(() => validatePublicationOrganization(publisher, id, "austria", [news], "wien"), /selected regional publisher/);
    assert.throws(() => validatePublicationOrganization({...publisher, federalState: "wien"}, id, "austria", [news], "tirol"), /does not belong/);
    assert.throws(() => validatePublicationOrganization(publisher, id, "austria", [news], "unknown"), /Unsupported federal state/);
    const opts = parseArguments(["manifest.json", "--organization-id", id, "--region-scope", "austria", "--publisher-federal-state", "tirol", "--dry-run"]);
    assert.equal(opts.publisherFederalState, "tirol");
    assert.deepEqual(resolvePublicationTarget(opts), {regionScope: "austria", federalState: undefined});
  });

  test("live news rejects empty Ukrainian or German descriptions", () => {
    for (const field of ["body", "deBody"]) {
      const manifest = newsManifest();
      manifest[field] = " \n\t ";
      assert.throws(() => normalizeAndValidateManifestItem(manifest, "wien"), /required/);
    }
  });

  test("live news rejects descriptions consisting only of a heading or a link in either language", () => {
    for (const [bodyField, titleField, subtitleField] of [["body", "title", "subtitle"], ["deBody", "deTitle", "deSubtitle"]]) {
      for (const value of [newsManifest()[titleField], newsManifest()[subtitleField], "https://example.at/details", "[Details](https://example.at/details)"]) {
        assert.throws(() => normalizeAndValidateManifestItem({...newsManifest(), [bodyField]: value}, "wien"), /full article/);
      }
    }
  });

  test("CLI exposes explicit regional and nationwide scope contracts", () => {
    // Scope belongs to the article; publisher region is explicitly separate.
    const legacyCountry = parseArguments([
      "manifest.json", "--organization-id", "central-uac", "--federal-state", "austria", "--dry-run",
    ]);
    assert.deepEqual(resolvePublicationTarget(legacyCountry), {regionScope: "austria", federalState: undefined});
    assert.equal(legacyCountry.dryRun, true);

    const explicitCountry = parseArguments([
      "manifest.json", "--organization-id", "central-uac", "--region-scope", "country",
    ]);
    assert.deepEqual(resolvePublicationTarget(explicitCountry), {regionScope: "austria", federalState: undefined});

    const regional = parseArguments([
      "manifest.json", "--organization-id", organizationId,
      "--region-scope", "federalState", "--federal-state", "wien",
    ]);
    assert.deepEqual(resolvePublicationTarget(regional), {regionScope: "federalState", federalState: "wien"});
    assert.throws(
      () => resolvePublicationTarget({...explicitCountry, federalState: "wien"}),
      /cannot specify a federal state/
    );
  });

  test("compatibility bridge accepts only the explicit publish command", () => {
    const argumentsList = [
      "manifest.json", "--organization-id", organizationId, "--federal-state", "wien", "--dry-run",
    ];
    assert.deepEqual(parsePublishCommand(["publish", ...argumentsList]), argumentsList);
    assert.throws(() => parsePublishCommand(["save", ...argumentsList]), /Usage:/);
    assert.throws(() => parsePublishCommand(["publish"]), /Usage:/);
  });

  test("uses only canonical live cover paths", () => {
    assert.equal(canonicalCoverStoragePath("news", "news-id"), "news/news-id/cover.jpg");
    assert.equal(canonicalCoverStoragePath("event", "event-id"), "events/event-id/cover.jpg");
    assert.throws(() => canonicalCoverStoragePath("organization", "id"), /news or event/);
    assert.throws(() => canonicalCoverStoragePath("news", "unsafe/id"), /invalid/);
  });

  test("converts PNG input into a bounded canonical JPEG", {skip: process.platform !== "darwin"}, async (context) => {
    const temporaryDirectory = await mkdtemp(join(tmpdir(), "uac-cover-test-"));
    context.after(() => rm(temporaryDirectory, {recursive: true, force: true}));
    const sourcePath = join(temporaryDirectory, "source.png");
    const png = Buffer.from(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
      "base64"
    );
    await writeFile(sourcePath, png);
    const prepared = await prepareImage({imagePath: sourcePath}, join(temporaryDirectory, "manifest.json"));
    assert.equal(prepared.extension, ".jpg");
    assert.equal(prepared.contentType, CANONICAL_COVER_CONTENT_TYPE);
    assert.ok(prepared.bytes.length > 0);
    assert.ok(prepared.bytes.length < MAXIMUM_CANONICAL_COVER_BYTES);
    assert.deepEqual([...prepared.bytes.subarray(0, 3)], [0xff, 0xd8, 0xff]);
  });

  test("external ticket events disable in-app registration and preserve legacy price", () => {
    const manifest = {
      ...eventManifest(),
      participationMode: "externalTickets",
      requiresRegistration: true,
      externalActionTitle: "Квитки",
      externalActionURL: "https://example.at/events/community-day/tickets",
      pricing: {kind: "startingFrom", amount: 19.5, currencyCode: "EUR"},
    };
    const item = normalizeAndValidateManifestItem(manifest, "wien");
    const document = buildContentDocument(item, organization, organizationId, "https://example.at/cover.jpg");
    assert.equal(document.participationMode, "externalTickets");
    assert.equal(document.requiresRegistration, false);
    assert.equal(document.externalAction.url, manifest.externalActionURL);
    assert.equal(document.price, 19.5);
    assert.equal(document.pricing.amount, 19.5);
  });

  test("preserves real and backward-compatible flat pricing fields", () => {
    const real = eventManifest();
    delete real.pricing;
    real.priceKind = "range";
    real.price = 12;
    real.maximumPrice = 28;
    const realItem = normalizeAndValidateManifestItem(real, "wien");
    assert.deepEqual(realItem.pricing, {
      kind: "range", amount: 12, maximumAmount: 28, currencyCode: "EUR",
    });
    assert.equal(buildContentDocument(realItem, organization, organizationId).price, 12);

    const legacy = eventManifest();
    delete legacy.pricing;
    legacy.priceKind = "range";
    legacy.priceAmount = 14;
    legacy.maximumPriceAmount = 32;
    assert.deepEqual(normalizeAndValidateManifestItem(legacy, "wien").pricing, {
      kind: "range", amount: 14, maximumAmount: 32, currencyCode: "EUR",
    });
  });

  test("requires two unique canonical HTTP(S) news sources", () => {
    const duplicate = newsManifest();
    duplicate.sources[1].url = `${duplicate.sources[0].url}/?utm_source=second#context`;
    assert.throws(
      () => normalizeAndValidateManifestItem(duplicate, "wien"),
      /two unique canonical source URLs/
    );
    const http = newsManifest();
    http.sources[1].url = "http://orf.at/example";
    assert.equal(normalizeAndValidateManifestItem(http, "wien").sources.length, 2);
    const sameHost = newsManifest();
    sameHost.sources[1].url = "https://example.at/independent/report";
    assert.throws(
      () => normalizeAndValidateManifestItem(sameHost, "wien"),
      /different site/
    );
  });

  test("rejects category errors and unverified manifests", () => {
    assert.throws(
      () => normalizeAndValidateManifestItem({...eventManifest(), category: "not-real"}, "wien"),
      /category is invalid/
    );
    assert.throws(
      () => normalizeAndValidateManifestItem({...eventManifest(), state: "needsAttention"}, "wien"),
      /explicitly approved/
    );
    const noState = eventManifest();
    delete noState.state;
    assert.throws(() => normalizeAndValidateManifestItem(noState, "wien"), /explicitly approved/);
    assert.throws(
      () => normalizeAndValidateManifestItem({
        payload: {...eventManifest(), state: "needsAttention", missingFields: ["Поле «Адреса»: відсутнє"]},
      }, "wien"),
      /explicitly approved/
    );
    assert.throws(
      () => normalizeAndValidateManifestItem({
        ...eventManifest(),
        state: "approved",
        missingFields: [],
        payload: {...eventManifest(), state: "needsAttention", missingFields: ["Поле «Адреса»: відсутнє"]},
      }, "wien"),
      /Every provided manifest state/
    );
    assert.throws(
      () => normalizeAndValidateManifestItem({
        ...eventManifest(),
        state: "approved",
        missingFields: [],
        payload: {...eventManifest(), state: "approved", missingFields: ["Поле «Адреса»: відсутнє"]},
      }, "wien"),
      /still has missingFields/
    );
    assert.throws(
      () => normalizeAndValidateManifestItem({...eventManifest(), missingFields: ["Дата завершення"]}, "wien"),
      /missingFields/
    );
    for (const malformed of [null, "", {}, true]) {
      assert.throws(
        () => normalizeAndValidateManifestItem({...eventManifest(), missingFields: malformed}, "wien"),
        /missingFields must be an explicit empty array/
      );
    }
    assert.doesNotThrow(
      () => normalizeAndValidateManifestItem({...eventManifest(), missingFields: []}, "wien")
    );
  });

  test("idempotency comparison ignores counters but rejects changed content", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const expected = buildContentDocument(item, organization, organizationId, "https://example.at/first.png", new Date("2026-08-30T10:00:00Z"));
    const existing = {
      ...expected,
      createdAt: expected.createdAt.toISOString(),
      updatedAt: "2026-09-01T10:00:00.000Z",
      imageURL: "https://example.at/replaced.png",
      viewCount: 40,
      likeCount: 3,
      likeState: "liked",
    };
    assert.equal(documentsSemanticallyMatch(existing, expected), true);
    assert.equal(documentsSemanticallyMatch({...existing, title: "Changed title"}, expected), false);
  });

  test("idempotency comparison treats equivalent Firestore timestamp precision as equal", () => {
    const item = normalizeAndValidateManifestItem(eventManifest(), "wien");
    const expected = buildContentDocument(
      item,
      organization,
      organizationId,
      "https://example.at/event.png",
      new Date("2026-08-30T10:00:00Z")
    );
    const existing = {
      ...expected,
      startDate: expected.startDate.toISOString().replace(".000Z", "Z"),
      endDate: expected.endDate.toISOString().replace(".000Z", "Z"),
      occurrences: expected.occurrences.map((occurrence) => ({
        ...occurrence,
        startDate: occurrence.startDate.toISOString().replace(".000Z", "Z"),
        endDate: occurrence.endDate.toISOString().replace(".000Z", "Z"),
      })),
    };

    assert.equal(documentsSemanticallyMatch(existing, expected), true);
  });

  test("skips exact legacy event ids using UTC-sorted occurrences and rejects semantic conflicts", () => {
    const item = normalizeAndValidateManifestItem(eventManifest(), "wien");
    const expected = buildContentDocument(
      item,
      organization,
      organizationId,
      undefined,
      new Date("2026-08-30T10:00:00Z")
    );
    const legacyFields = {
      ...expected,
      id: "legacy-event-id",
      sourceURL: "https://example.at/events/community-day/?utm_source=legacy#details",
      authorName: "Serlest",
      requiresRegistration: true,
      hasExplicitEndDate: false,
      occurrences: [
        {
          id: "legacy-02",
          startDate: "2026-10-02T18:00:00+02:00",
          endDate: "2026-10-02T20:00:00+02:00",
          hasExplicitEndDate: true,
          isAllDay: false,
          status: "scheduled",
        },
        {
          id: "legacy-01",
          startDate: "2026-10-01T17:00:00+02:00",
          endDate: "2026-10-01T17:00:00+02:00",
          hasExplicitEndDate: false,
          isAllDay: false,
          status: "scheduled",
        },
      ],
    };
    const record = buildExistingDuplicateRecord({
      id: legacyFields.id,
      collection: "events",
      defaultKind: "event",
      fields: legacyFields,
    });
    const exact = classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [record]});
    assert.deepEqual(exact, {
      status: "skippedExisting",
      existingId: "legacy-event-id",
      existingCollection: "events",
      matchedBy: "eventComposite",
    });
    assert.deepEqual(record.summary.occurrenceStartDates, [
      "2026-10-01T15:00:00.000Z",
      "2026-10-02T16:00:00.000Z",
    ]);

    const conflictRecord = buildExistingDuplicateRecord({
      id: legacyFields.id,
      collection: "events",
      defaultKind: "event",
      fields: {...legacyFields, details: "Інший опис події."},
    });
    const conflict = classifyLegacyDuplicate({
      item,
      expectedDocument: expected,
      existingRecords: [conflictRecord],
    });
    assert.equal(conflict.status, "needsAttention");
    assert.equal(conflict.conflicts[0].existingId, "legacy-event-id");
  });

  test("flags a possible event reschedule but allows a differently titled annual edition", () => {
    const item = normalizeAndValidateManifestItem(eventManifest(), "wien");
    const expected = buildContentDocument(item, organization, organizationId, undefined);
    const rescheduled = {
      ...expected,
      id: "rescheduled-event",
      sourceURL: item.canonicalURL,
      occurrences: expected.occurrences.map((occurrence) => ({
        ...occurrence,
        startDate: new Date(occurrence.startDate.getTime() + 86_400_000).toISOString(),
        endDate: new Date(occurrence.endDate.getTime() + 86_400_000).toISOString(),
      })),
    };
    const rescheduledRecord = buildExistingDuplicateRecord({
      id: rescheduled.id,
      collection: "events",
      defaultKind: "event",
      fields: rescheduled,
    });
    const conflict = classifyLegacyDuplicate({
      item,
      expectedDocument: expected,
      existingRecords: [rescheduledRecord],
    });
    assert.equal(conflict.status, "needsAttention");
    assert.equal(conflict.conflicts[0].matchedBy, "possibleReschedule");

    const annualRecord = buildExistingDuplicateRecord({
      id: "annual-2027",
      collection: "events",
      defaultKind: "event",
      fields: {
        ...rescheduled,
        id: "annual-2027",
        title: "День громади у Відні 2027",
        localizations: {
          ...rescheduled.localizations,
          uk: {...rescheduled.localizations.uk, title: "День громади у Відні 2027"},
          de: {...rescheduled.localizations.de, title: "Community-Tag in Wien 2027"},
        },
      },
    });
    assert.deepEqual(
      classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [annualRecord]}),
      {status: "new"}
    );
  });

  test("news identity ignores secondary sources and compares the full draft semantics", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const expected = buildContentDocument(item, organization, organizationId, undefined);
    const unrelated = buildExistingDuplicateRecord({
      id: "other-news",
      collection: "news",
      defaultKind: "news",
      fields: {
        ...expected,
        id: "other-news",
        sourceURL: "https://different.example/primary",
        verificationSources: [
          {url: "https://different.example/primary", isPrimary: true},
          {url: item.canonicalURL, isPrimary: false},
        ],
      },
    });
    assert.deepEqual(
      classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [unrelated]}),
      {status: "new"}
    );

    const exactDraft = buildExistingDuplicateRecord({
      id: "exact-draft",
      collection: "drafts",
      fields: newsDraftFields(item, "readyForReview"),
    });
    const exact = classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [exactDraft]});
    assert.equal(exact.status, "skippedExisting");

    const changedDraft = buildExistingDuplicateRecord({
      id: "changed-draft",
      collection: "drafts",
      fields: newsDraftFields(item, "readyForReview", {body: "Інший текст у чернетці."}),
    });
    assert.equal(
      classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [changedDraft]}).status,
      "needsAttention"
    );

    const attentionDraft = buildExistingDuplicateRecord({
      id: "attention-draft",
      collection: "drafts",
      fields: newsDraftFields(item, "needsAttention"),
    });
    assert.equal(
      classifyLegacyDuplicate({item, expectedDocument: expected, existingRecords: [attentionDraft]}).status,
      "needsAttention"
    );
  });

  test("semantic projection includes the effective registration contract", () => {
    const item = normalizeAndValidateManifestItem({
      ...eventManifest(), participationMode: "inAppRegistration",
    }, "wien");
    const expected = buildContentDocument(item, organization, organizationId);
    assert.equal(expected.requiresRegistration, true);
    assert.equal(legacyDocumentsSemanticallyMatch("event", {...expected, requiresRegistration: false}, expected), false);

    const externalItem = normalizeAndValidateManifestItem({
      ...eventManifest(),
      participationMode: "externalRegistration",
      externalActionURL: "https://example.at/register",
    }, "wien");
    const externalExpected = buildContentDocument(externalItem, organization, organizationId);
    assert.equal(legacyDocumentsSemanticallyMatch(
      "event", {...externalExpected, requiresRegistration: true}, externalExpected
    ), true);
  });

  test("global identity locks are organization-independent and collision-safe", () => {
    const news = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const firstClaims = contentIdentityLockClaims(news);
    const variant = {...news, canonicalURL: `${news.canonicalURL}/?utm_source=other#fragment`};
    assert.deepEqual(contentIdentityLockClaims(variant), firstClaims);
    assert.ok(firstClaims.length >= 2);
    assert.equal(firstClaims[0].id.length, 64);

    const sameTitleDifferentStory = normalizeAndValidateManifestItem({
      ...newsManifest(),
      canonicalURL: "https://another-official.at/news/other-story",
      body: "Це інша перевірена новина з таким самим загальним заголовком.",
      sources: [
        {
          url: "https://another-official.at/news/other-story",
          title: "Інше офіційне повідомлення",
          isPrimary: true,
          verificationRole: "officialPrimary",
        },
        {
          url: "https://another-media.at/report",
          title: "Незалежне підтвердження",
          isPrimary: false,
          verificationRole: "independent",
        },
      ],
    }, "wien");
    const otherClaims = contentIdentityLockClaims(sameTitleDifferentStory);
    assert.equal(firstClaims.some((claim) => otherClaims.some((other) => other.id === claim.id)), false);

    const entry = {id: "content-a", collection: "news", item: news, identityClaims: firstClaims};
    const lock = buildIdentityLockDocument({
      claim: firstClaims[0], entry, organizationId: "org-a", now: new Date("2026-08-30T10:00:00Z"),
    });
    assert.equal(lock.identityAlgorithm, "uacContentIdentity-v1");
    assert.equal(lock.contentId, "content-a");
    assert.doesNotThrow(() => assertUniqueIdentityClaims([entry]));
    assert.throws(
      () => assertUniqueIdentityClaims([entry, {...entry, id: "content-b"}]),
      /same global content identity/
    );
  });

  test("live identity conflicts take priority over exact drafts", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const expected = buildContentDocument(item, organization, organizationId, undefined);
    const exactDraft = buildExistingDuplicateRecord({
      id: "exact-draft",
      collection: "drafts",
      fields: {
        kind: "news",
        state: "readyForReview",
        title: item.title,
        sources: [{url: item.canonicalURL, title: "Primary", isPrimary: true}],
      },
    });
    const conflictingLive = buildExistingDuplicateRecord({
      id: "conflicting-live",
      collection: "news",
      defaultKind: "news",
      fields: {
        ...expected,
        id: "conflicting-live",
        sourceURL: item.canonicalURL,
        body: "Інший live-текст за тією самою identity.",
      },
    });
    const conflict = classifyLegacyDuplicate({
      item,
      expectedDocument: expected,
      existingRecords: [exactDraft, conflictingLive],
    });
    assert.equal(conflict.status, "needsAttention");
    assert.deepEqual(conflict.existingIds, ["conflicting-live"]);
    assert.deepEqual(conflict.conflicts.map((candidate) => candidate.existingCollection), ["news"]);

    const exactLive = buildExistingDuplicateRecord({
      id: "exact-live",
      collection: "news",
      defaultKind: "news",
      fields: {...expected, id: "exact-live", sourceURL: item.canonicalURL},
    });
    const conflictingDraft = buildExistingDuplicateRecord({
      id: "conflicting-draft",
      collection: "drafts",
      fields: {
        kind: "news",
        state: "needsAttention",
        title: "Інший draft-заголовок",
        sources: [{url: item.canonicalURL, title: "Primary", isPrimary: true}],
      },
    });
    const liveWins = classifyLegacyDuplicate({
      item,
      expectedDocument: expected,
      existingRecords: [conflictingDraft, exactLive],
    });
    assert.equal(liveWins.status, "skippedExisting");
    assert.equal(liveWins.existingId, "exact-live");
    assert.equal(liveWins.existingCollection, "news");
  });

  test("localized alias conflicts and hidden live records cannot false-skip", () => {
    const item = normalizeAndValidateManifestItem(newsManifest(), "wien");
    const expected = buildContentDocument(item, organization, organizationId);
    const conflictingLocalization = buildExistingDuplicateRecord({
      id: "localized-conflict",
      collection: "news",
      defaultKind: "news",
      fields: {
        ...expected,
        id: "localized-conflict",
        sourceURL: item.canonicalURL,
        localizations: {
          ...expected.localizations,
          uk: {...expected.localizations.uk, body: "Інший видимий текст."},
        },
      },
    });
    assert.equal(classifyLegacyDuplicate({
      item, expectedDocument: expected, existingRecords: [conflictingLocalization],
    }).status, "needsAttention");

    const rejected = buildExistingDuplicateRecord({
      id: "rejected-live",
      collection: "news",
      defaultKind: "news",
      fields: {...expected, id: "rejected-live", sourceURL: item.canonicalURL, moderationStatus: "rejected"},
    });
    assert.equal(classifyLegacyDuplicate({
      item, expectedDocument: expected, existingRecords: [rejected],
    }).status, "new");
  });
});

function eventManifest() {
  return {
    state: "approved",
    missingFields: [],
    kind: "event",
    canonicalURL: "https://example.at/events/community-day",
    imagePath: "cover.png",
    imageAlternativeText: "Люди на міському святі",
    title: "День громади у Відні",
    summary: "Зустріч, музика та корисна інформація.",
    details: "Повний перевірений опис події.",
    deTitle: "Community-Tag in Wien",
    deSummary: "Begegnung, Musik und nützliche Informationen.",
    deDetails: "Vollständige geprüfte Veranstaltungsbeschreibung.",
    city: "Wien",
    venue: "Rathausplatz",
    address: "Rathausplatz, 1010 Wien",
    organizerName: "Stadt Wien",
    organizerURL: "https://www.wien.gv.at/",
    contactURL: "https://example.at/events/community-day",
    category: "meetups",
    additionalCategories: ["music"],
    audience: "everyone",
    participationMode: "none",
    pricing: {kind: "free", amount: 0, note: "Вхід вільний."},
    occurrences: [
      {startDate: "2026-10-02T18:00:00+02:00", endDate: "2026-10-02T20:00:00+02:00"},
      {startDate: "2026-10-01T17:00:00+02:00", hasExplicitEndDate: false},
    ],
    sources: [
      {
        url: "https://example.at/events/community-day",
        title: "Офіційна сторінка",
        isPrimary: true,
        verificationRole: "officialPrimary",
      },
      {
        url: "https://tickets.example.org/community-day",
        title: "Квитки",
        isPrimary: false,
        verificationRole: "ticketing",
      },
    ],
  };
}

function newsManifest() {
  return {
    state: "approved",
    missingFields: [],
    kind: "news",
    canonicalURL: "https://example.at/news/new-service",
    imagePath: "news.png",
    imageAlternativeText: "Консультація у віденському сервісному центрі",
    title: "Нова послуга у Відні",
    subtitle: "Коротке пояснення",
    body: "Повний перевірений текст новини.",
    deTitle: "Neues Angebot in Wien",
    deSubtitle: "Kurze Erklärung",
    deBody: "Vollständiger geprüfter Nachrichtentext.",
    publishedAt: "2026-08-30T08:00:00Z",
    city: "Wien",
    category: "benefitsAndSupport",
    additionalCategories: ["communityAndIntegration"],
    sourceName: "Stadt Wien / ORF Wien",
    externalActionTitle: "Офіційна інформація",
    externalActionURL: "https://example.at/news/new-service",
    sources: [
      {
        url: "https://example.at/news/new-service",
        title: "Stadt Wien",
        isPrimary: true,
        verificationRole: "officialPrimary",
      },
      {
        url: "https://orf.at/example",
        title: "ORF",
        isPrimary: false,
        verificationRole: "independent",
      },
    ],
  };
}

function newsDraftFields(item, state, overrides = {}) {
  return {
    kind: "news",
    state,
    title: item.title,
    sources: item.sources,
    missingFields: [],
    payload: {
      title: item.title,
      summary: item.subtitle,
      body: item.body,
      germanTitle: item.deTitle,
      germanSummary: item.deSubtitle,
      germanBody: item.deBody,
      regionScope: item.regionScope,
      federalState: item.federalState,
      category: item.category,
      additionalCategories: item.additionalCategories,
      tags: item.tags,
      externalActionTitle: item.externalAction?.title,
      externalActionURL: item.externalAction?.url,
      ...overrides,
    },
  };
}
