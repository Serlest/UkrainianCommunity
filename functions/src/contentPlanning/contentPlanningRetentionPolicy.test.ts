import {strict as assert} from "node:assert";
import {test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {
  contentPlanningDraftImagePrefix,
  contentPlanningDraftMediaCleanupDecision,
  contentPlanningRetentionExpiresAt,
} from "./contentPlanningRetentionPolicy";

test("retains planning receipts for six calendar months", () => {
  const expiry = contentPlanningRetentionExpiresAt(
    Timestamp.fromDate(new Date("2026-08-31T18:45:00.000Z"))
  );
  assert.equal(expiry.toDate().toISOString(), "2027-02-28T18:45:00.000Z");
});

test("accepts only the exact owner and draft media prefix", () => {
  assert.equal(
    contentPlanningDraftImagePrefix("owner-1", "draft-1"),
    "users/owner-1/contentPlanningDraftImages/draft-1/"
  );
  assert.throws(() => contentPlanningDraftImagePrefix("../owner", "draft-1"));
  assert.throws(() => contentPlanningDraftImagePrefix("owner-1", ""));
});

test("deletes only redundant terminal draft media", () => {
  const base = {
    state: "completed",
    draftStoragePath: "users/owner-1/contentPlanningDraftImages/draft-1/cover.jpg",
    expectedDraftPrefix: "users/owner-1/contentPlanningDraftImages/draft-1/",
    publishedContentId: "news-1",
    publishedContentKind: "news",
    liveContentExists: true,
    liveImagePath: "news/news-1/cover.jpg",
    liveImageExists: true,
    hasOtherLiveReference: false,
  };

  assert.equal(contentPlanningDraftMediaCleanupDecision(base), "deleteRedundantCopy");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    state: "archived",
    publishedContentId: undefined,
    liveContentExists: false,
    liveImagePath: undefined,
    liveImageExists: false,
  }), "deleteArchivedCopy");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    state: "archived",
    hasOtherLiveReference: true,
  }), "retainLiveReference");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    state: "archived",
    liveImagePath: base.draftStoragePath,
  }), "retainLiveReference");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    liveImagePath: base.draftStoragePath,
  }), "retainLiveReference");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    hasOtherLiveReference: true,
  }), "retainLiveReference");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    draftStoragePath: "users/owner-1/contentPlanningDraftImages/other/cover.jpg",
  }), "retainInvalidPath");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    publishedContentId: undefined,
  }), "retainUnresolved");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    liveContentExists: false,
  }), "retainMissingLiveContent");
  assert.equal(contentPlanningDraftMediaCleanupDecision({
    ...base,
    liveImageExists: false,
  }), "retainMissingLiveImage");
});
