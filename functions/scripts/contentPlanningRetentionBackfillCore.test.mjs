import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  addUtcCalendarMonths,
  assertContentPlanningRetentionExpectations,
  classifyContentPlanningRetentionDraft,
  parseContentPlanningRetentionBackfillOptions,
  summarizeContentPlanningRetention,
} from "./contentPlanningRetentionBackfillCore.mjs";

const terminalDraft = (overrides = {}) => ({
  data: {
    state: "completed",
    completedAt: new Date("2026-08-31T12:00:00.000Z"),
    publishedContentId: "news-1",
    publishedContentKind: "news",
    generatedImage: {
      url: "https://firebasestorage.googleapis.com/example",
      storagePath: "users/owner/contentPlanningDraftImages/draft/cover.jpg",
    },
    ...overrides,
  },
});

test("prepares linked terminal receipts for cleanup and calendar retention", () => {
  const result = classifyContentPlanningRetentionDraft(terminalDraft());
  assert.equal(result.status, "update");
  assert.equal(result.category, "linked");
  assert.equal(result.mediaCleanupStatus, "pending");
  assert.equal(result.requestsMediaCleanup, true);
  assert.equal(
    new Date(result.retentionExpiresAtMilliseconds).toISOString(),
    "2027-02-28T12:00:00.000Z"
  );
});

test("keeps unresolved and archived records explicit", () => {
  const unresolved = classifyContentPlanningRetentionDraft(terminalDraft({
    publishedContentId: null,
    publishedContentKind: null,
  }));
  assert.equal(unresolved.category, "unresolved");
  assert.equal(unresolved.mediaCleanupStatus, "pending");

  const archived = classifyContentPlanningRetentionDraft(terminalDraft({
    state: "archived",
    completedAt: null,
    archivedAt: new Date("2026-08-31T12:00:00.000Z"),
    publishedContentId: null,
    publishedContentKind: null,
  }));
  assert.equal(archived.category, "archived");
});

test("does not rewrite an already prepared receipt", () => {
  const result = classifyContentPlanningRetentionDraft(terminalDraft({
    retentionExpiresAt: new Date("2027-02-28T12:00:00.000Z"),
    draftMediaCleanupStatus: "deletedRedundantCopy",
  }));
  assert.equal(result.status, "alreadyPrepared");
  assert.equal(result.requestsMediaCleanup, false);
});

test("prefers the original update time over an administrative history backfill", () => {
  const result = classifyContentPlanningRetentionDraft(terminalDraft({
    completedAt: null,
    updatedAt: new Date("2026-08-15T09:30:00.000Z"),
    historyBackfilledAt: new Date("2026-09-01T12:00:00.000Z"),
  }));
  assert.equal(
    new Date(result.retentionExpiresAtMilliseconds).toISOString(),
    "2027-02-15T09:30:00.000Z"
  );
});

test("summarizes active, terminal, and invalid records independently", () => {
  const values = [
    {result: classifyContentPlanningRetentionDraft(terminalDraft())},
    {result: classifyContentPlanningRetentionDraft(terminalDraft({
      publishedContentId: null,
      publishedContentKind: null,
    }))},
    {result: classifyContentPlanningRetentionDraft({data: {state: "needsAttention"}})},
    {result: classifyContentPlanningRetentionDraft({data: {state: "completed"}})},
  ];
  assert.deepEqual(summarizeContentPlanningRetention(values), {
    total: 4,
    updates: 2,
    alreadyPrepared: 0,
    active: 1,
    linked: 1,
    unresolved: 1,
    archived: 0,
    invalid: 1,
  });
});

test("requires exact fresh expectations before apply", () => {
  assert.throws(() => parseContentPlanningRetentionBackfillOptions([
    "--project=example",
    "--apply",
    "--confirm-project=example",
  ]), /requires every expectation/);
  assert.throws(() => parseContentPlanningRetentionBackfillOptions([
    "--project=example",
    "--expect-updates=94",
  ]), /Provide all retention expectations/);

  const options = parseContentPlanningRetentionBackfillOptions([
    "--project=example",
    "--apply",
    "--confirm-project=example",
    "--expect-updates=94",
    "--expect-active=3",
    "--expect-linked=92",
    "--expect-unresolved=2",
    "--expect-archived=0",
    "--expect-invalid=0",
  ]);
  assert.equal(options.apply, true);
  assert.equal(options.expectations.updates, 94);
  assert.doesNotThrow(() => assertContentPlanningRetentionExpectations({
    updates: 94,
    active: 3,
    linked: 92,
    unresolved: 2,
    archived: 0,
    invalid: 0,
  }, options.expectations));
});

test("calendar month addition clamps the last day", () => {
  assert.equal(
    new Date(addUtcCalendarMonths(Date.parse("2026-08-31T12:00:00Z"), 6)).toISOString(),
    "2027-02-28T12:00:00.000Z"
  );
});
