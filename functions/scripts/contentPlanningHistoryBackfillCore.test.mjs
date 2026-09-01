import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  classifyPlanningHistoryDraft,
  normalizeSourceURL,
  publicationOutcomeForContent,
  summarizeHistoryClassifications,
} from "./contentPlanningHistoryBackfillCore.mjs";

const draft = (overrides = {}) => ({
  id: "draft-1",
  path: "users/owner/contentPlanningDrafts/draft-1",
  data: {
    kind: "news",
    sources: [{url: "https://example.org/story/?utm_source=uac#details"}],
    ...overrides,
  },
});
const content = (id, overrides = {}) => ({
  collection: "news",
  id,
  data: {
    sourceURL: "https://example.org/story",
    moderationStatus: "approved",
    organizationId: "org-1",
    ...overrides,
  },
});

test("normalizes only non-semantic URL differences", () => {
  assert.equal(
    normalizeSourceURL("https://EXAMPLE.org/story/?utm_source=uac#details"),
    "https://example.org/story"
  );
  assert.equal(normalizeSourceURL("not a url"), undefined);
});

test("matches exactly one live item by an official URL", () => {
  const result = classifyPlanningHistoryDraft(draft(), [content("news-1")]);
  assert.equal(result.status, "matched");
  assert.equal(result.content.id, "news-1");
});

test("does not guess when the URL has zero or multiple matches", () => {
  assert.equal(classifyPlanningHistoryDraft(draft(), []).status, "unresolved");
  assert.equal(
    classifyPlanningHistoryDraft(draft(), [content("news-1"), content("news-2")]).status,
    "ambiguous"
  );
});

test("recognizes an existing valid link without scheduling another write", () => {
  const result = classifyPlanningHistoryDraft(
    draft({
      schemaVersion: 3,
      publishedContentId: "news-1",
      publishedContentKind: "news",
      publishedOrganizationId: "org-1",
      publishedOrganizationName: null,
      publicationOutcome: "approved",
      historyBackfillStatus: "matched",
      historyBackfilledAt: {seconds: 1},
    }),
    [content("news-1")]
  );
  assert.equal(result.status, "alreadyLinked");
  const summary = summarizeHistoryClassifications([{result}]);
  assert.equal(summary.safeResolved, 1);
  assert.equal(summary.matched, 0);
});

test("repairs an existing link when its receipt fields are incomplete", () => {
  const result = classifyPlanningHistoryDraft(
    draft({publishedContentId: "news-1"}),
    [content("news-1")]
  );
  assert.equal(result.status, "matched");
  assert.equal(result.content.id, "news-1");
});

test("treats an already marked unresolved record as an idempotent no-op", () => {
  const result = classifyPlanningHistoryDraft(
    draft({
      schemaVersion: 3,
      historyBackfillStatus: "unresolved",
      publicationOutcome: "unresolved",
      historyBackfilledAt: {seconds: 1},
    }),
    []
  );
  assert.equal(result.status, "alreadyUnresolved");
  const summary = summarizeHistoryClassifications([{result}]);
  assert.equal(summary.unresolved, 0);
  assert.equal(summary.totalUnresolved, 1);
});

test("requires exact title and start date when only an event organization URL matches", () => {
  const eventDraft = draft({
    kind: "event",
    title: "Зустріч громади",
    payload: {startDate: "2026-09-12T18:00:00+02:00"},
  });
  const candidate = {
    collection: "events",
    id: "event-1",
    data: {
      title: "Інша подія",
      startDate: "2026-09-12T18:00:00+02:00",
      organizerURL: "https://example.org/story",
      moderationStatus: "approved",
    },
  };
  assert.equal(classifyPlanningHistoryDraft(eventDraft, [candidate]).status, "unresolved");
  candidate.data.title = "Зустріч громади";
  assert.equal(classifyPlanningHistoryDraft(eventDraft, [candidate]).status, "matched");
});

test("derives receipt outcomes only from persisted moderation state", () => {
  assert.equal(publicationOutcomeForContent({moderationStatus: "approved"}), "approved");
  assert.equal(publicationOutcomeForContent({moderationStatus: "pendingReview"}), "pendingReview");
  assert.equal(
    publicationOutcomeForContent({moderationStatus: "draft", scheduledAt: {seconds: 1}}),
    "scheduled"
  );
  assert.equal(publicationOutcomeForContent({moderationStatus: "draft"}), "unresolved");
});
