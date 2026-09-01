import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  parseBeginPublicationInput,
  parseFailPublicationInput,
  parseFinalizePublicationInput,
  parseOwnerContentDraftID,
  parseOwnerContentDraftInput,
  parseScheduledPublicationInput,
} from "./ownerContentDrafts";

test("parses publication lease requests and rejects unsafe identifiers", () => {
  const draftId = "a".repeat(40);
  const begin = parseBeginPublicationInput({draftId, attemptId: "attempt_123456789"});
  assert.equal(begin.draftId, draftId);
  assert.equal(begin.attemptId, "attempt_123456789");
  assert.throws(() => parseBeginPublicationInput({draftId, attemptId: "short"}));

  const finalize = parseFinalizePublicationInput({
    draftId,
    leaseId: "lease-1",
    contentId: `planning-${draftId}`,
    kind: "news",
  });
  assert.equal(finalize.kind, "news");
  assert.throws(() => parseFinalizePublicationInput({
    draftId,
    leaseId: "lease-1",
    contentId: "content-1",
    kind: "organization",
  }));

  const failed = parseFailPublicationInput({draftId, leaseId: "lease-1", message: "Upload failed"});
  assert.equal(failed.message, "Upload failed");
  assert.throws(() => parseFailPublicationInput({draftId, leaseId: "lease-1", message: ""}));
});

test("parses a verified news draft without organization assignment", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "news-official-source-2026-08-27",
    kind: "news",
    payload: {
      title: "Важлива новина",
      summary: "Короткий перевірений опис.",
      body: "Повний текст новини.",
      sourceInput: "https://example.org/news",
      tags: ["Австрія"],
    },
    sources: [{url: "https://example.org/news", isPrimary: true}],
    verificationNotes: [],
    missingFields: [],
  });

  assert.equal(parsed.kind, "news");
  assert.equal(parsed.state, "readyForReview");
  assert.equal("organizationId" in parsed.payload, false);
});

test("marks a draft as needing attention when fields are missing", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "event-needs-location",
    kind: "event",
    payload: {
      title: "Зустріч",
      summary: "Зустріч громади.",
      details: "Деталі зустрічі.",
      city: "Innsbruck",
      venue: "Haus der Begegnung",
      federalState: "tirol",
      startDate: "2026-10-10T18:00:00+02:00",
      endDate: "2026-10-10T20:00:00+02:00",
      tags: [],
    },
    sources: [{url: "https://example.org/event", isPrimary: true}],
    missingFields: ["address"],
  });

  assert.equal(parsed.state, "needsAttention");
});

test("rejects a vague needs-attention draft without a concrete field", () => {
  assert.throws(() => parseOwnerContentDraftInput({
    idempotencyKey: "event-vague-attention",
    kind: "event",
    state: "needsAttention",
    payload: {
      title: "Зустріч",
      summary: "Зустріч громади.",
      details: "Деталі зустрічі.",
      city: "Innsbruck",
      venue: "Saal",
      federalState: "tirol",
      startDate: "2026-10-10T18:00:00+02:00",
      hasExplicitEndDate: false,
      tags: [],
    },
    sources: [{url: "https://example.org/event", isPrimary: true}],
    missingFields: [],
  }), /needsAttention requires at least one concrete missingFields entry/);
});

test("accepts an event without an explicit end and normalizes every open occurrence", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "event-open-ended",
    kind: "event",
    payload: {
      title: "Відкрита подія",
      summary: "Подія без оголошеного часу завершення.",
      details: "Організатор опублікував лише час початку.",
      city: "Innsbruck",
      venue: "Saal",
      federalState: "tirol",
      startDate: "2026-10-10T18:00:00+02:00",
      hasExplicitEndDate: false,
      additionalOccurrences: [{startDate: "2026-10-11T18:00:00+02:00"}],
      tags: [],
    },
    sources: [{url: "https://example.org/open-event", isPrimary: true}],
  });

  const start = parsed.payload.startDate as Timestamp;
  const end = parsed.payload.endDate as Timestamp;
  const occurrences = parsed.payload.additionalOccurrences as Array<{startDate: Timestamp; endDate: Timestamp}>;
  assert.equal(parsed.payload.hasExplicitEndDate, false);
  assert.equal(end.toMillis(), start.toMillis());
  assert.equal(occurrences[0].endDate.toMillis(), occurrences[0].startDate.toMillis());
});

test("rejects event dates without an explicit time zone", () => {
  assert.throws(() => parseOwnerContentDraftInput({
    idempotencyKey: "event-invalid-zone",
    kind: "event",
    payload: {
      title: "Зустріч",
      summary: "Зустріч громади.",
      details: "Деталі зустрічі.",
      city: "Wien",
      venue: "Saal",
      federalState: "wien",
      startDate: "2026-10-10T18:00:00",
      endDate: "2026-10-10T20:00:00",
      tags: [],
    },
    sources: [{url: "https://example.org/event", isPrimary: true}],
  }));
});

test("rejects unsupported fields such as organizationId", () => {
  assert.throws(() => parseOwnerContentDraftInput({
    idempotencyKey: "news-with-organization",
    kind: "news",
    payload: {
      title: "Новина",
      summary: "Опис.",
      body: "Текст.",
      sourceInput: "https://example.org/news",
      tags: [],
      organizationId: "must-not-be-selected",
    },
    sources: [{url: "https://example.org/news", isPrimary: true}],
  }));
});

test("accepts generated original image metadata and maps its URL into the editor payload", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "event-with-generated-image",
    kind: "event",
    payload: {
      title: "Зустріч",
      summary: "Зустріч громади.",
      details: "Деталі зустрічі.",
      city: "Innsbruck",
      venue: "Saal",
      federalState: "tirol",
      startDate: "2026-10-10T18:00:00+02:00",
      endDate: "2026-10-10T20:00:00+02:00",
      tags: [],
    },
    generatedImage: {
      url: "https://firebasestorage.googleapis.com/example.jpg",
      storagePath: "users/owner/contentPlanningDraftImages/draft/cover.jpg",
      alternativeText: "Альпійський захід сонця",
      credit: "Зображення створене ШІ",
    },
    sources: [{url: "https://example.org/event", isPrimary: true}],
  });

  assert.equal(parsed.payload.generatedImageURL, "https://firebasestorage.googleapis.com/example.jpg");
  assert.equal(parsed.payload.imageAlternativeText, "Альпійський захід сонця");
  assert.equal(parsed.payload.imageCredit, "Зображення створене ШІ");
  assert.equal(parsed.generatedImage?.storagePath, "users/owner/contentPlanningDraftImages/draft/cover.jpg");
});

test("validates owner content draft identifiers before deletion", () => {
  assert.equal(parseOwnerContentDraftID({draftId: "a".repeat(40)}), "a".repeat(40));
  assert.throws(() => parseOwnerContentDraftID({draftId: "../draft"}));
});

test("parses the link between a planning draft and scheduled content", () => {
  const scheduledAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const parsed = parseScheduledPublicationInput({
    draftId: "a".repeat(40),
    contentId: "scheduled-content-id",
    kind: "event",
    scheduledAt,
  });

  assert.equal(parsed.draftId, "a".repeat(40));
  assert.equal(parsed.contentId, "scheduled-content-id");
  assert.equal(parsed.kind, "event");
  assert.equal(parsed.scheduledAt.toISOString(), scheduledAt);
});

test("rejects an invalid scheduled planning link", () => {
  assert.throws(() => parseScheduledPublicationInput({
    draftId: "invalid",
    contentId: "scheduled-content-id",
    kind: "post",
    scheduledAt: "2026-09-10T10:00:00+02:00",
  }));
});

test("accepts nationwide scheduled news and normalizes its publication time", () => {
  const scheduledAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "scheduled-national-news",
    kind: "news",
    payload: {
      title: "Новина для всієї Австрії",
      summary: "Короткий опис.",
      body: "Повний перевірений текст.",
      sourceInput: "https://example.org/austria",
      tags: ["Австрія"],
      regionScope: "austria",
      publicationMode: "scheduled",
      scheduledAt,
    },
    sources: [{url: "https://example.org/austria", isPrimary: true}],
  });

  assert.equal(parsed.payload.regionScope, "austria");
  assert.equal(parsed.payload.publicationMode, "scheduled");
  assert.ok(parsed.payload.scheduledAt instanceof Object);
});

test("rejects scheduled publication less than five minutes ahead", () => {
  assert.throws(() => parseOwnerContentDraftInput({
    idempotencyKey: "scheduled-too-soon",
    kind: "news",
    payload: {
      title: "Новина",
      summary: "Опис.",
      body: "Текст.",
      sourceInput: "https://example.org/news",
      tags: [],
      publicationMode: "scheduled",
      scheduledAt: new Date(Date.now() + 60 * 1000).toISOString(),
    },
    sources: [{url: "https://example.org/news", isPrimary: true}],
  }));
});

test("accepts one primary category and at most two additional topics", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "news-with-topics",
    kind: "news",
    payload: {
      title: "Корисна новина",
      summary: "Короткий опис.",
      body: "Повний перевірений текст.",
      sourceInput: "https://example.org/news",
      category: "communityAndIntegration",
      additionalCategories: ["education", "benefitsAndSupport"],
      tags: ["Тіроль"],
    },
    sources: [{url: "https://example.org/news", isPrimary: true}],
  });

  assert.deepEqual(parsed.payload.additionalCategories, ["education", "benefitsAndSupport"]);
});

test("accepts the expanded categories and rejects unknown or duplicate topics", () => {
  const parsed = parseOwnerContentDraftInput({
    idempotencyKey: "expanded-event-topics",
    kind: "event",
    payload: {
      title: "Нічний фестиваль",
      summary: "Короткий опис.",
      details: "Повний перевірений опис.",
      city: "Innsbruck",
      venue: "Messe Innsbruck",
      federalState: "tirol",
      startDate: "2026-11-13T18:00:00+01:00",
      endDate: "2026-11-13T23:00:00+01:00",
      category: "nightlifeAndParties",
      additionalCategories: ["music", "festivalsAndFairs"],
      tags: [],
    },
    sources: [{url: "https://example.org/event", isPrimary: true}],
  });
  assert.deepEqual(parsed.payload.additionalCategories, ["music", "festivalsAndFairs"]);

  for (const additionalCategories of [
    ["notARealCategory"],
    ["music", "music"],
    ["nightlifeAndParties"],
  ]) {
    assert.throws(() => parseOwnerContentDraftInput({
      idempotencyKey: `invalid-${additionalCategories.join("-")}`,
      kind: "event",
      payload: {
        title: "Подія",
        summary: "Короткий опис.",
        details: "Повний перевірений опис.",
        city: "Innsbruck",
        venue: "Messe Innsbruck",
        federalState: "tirol",
        startDate: "2026-11-13T18:00:00+01:00",
        endDate: "2026-11-13T23:00:00+01:00",
        category: "nightlifeAndParties",
        additionalCategories,
        tags: [],
      },
      sources: [{url: "https://example.org/event", isPrimary: true}],
    }));
  }
});

test("rejects more than two additional topics", () => {
  assert.throws(() => parseOwnerContentDraftInput({
    idempotencyKey: "news-with-too-many-topics",
    kind: "news",
    payload: {
      title: "Новина",
      summary: "Короткий опис.",
      body: "Повний перевірений текст.",
      sourceInput: "https://example.org/news",
      additionalCategories: ["education", "health", "benefitsAndSupport"],
      tags: [],
    },
    sources: [{url: "https://example.org/news", isPrimary: true}],
  }));
});
