import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  canonicalContentStoragePath,
  canonicalContentStoragePrefix,
  canDiscardOrganizationRequest,
  contentReferencePoliciesFor,
  contentStoragePrefixes,
  eventBlocksOrganizationDeletion,
  firebaseStorageDownloadURL,
  featuredBannerActionType,
  legacyDraftStoragePath,
  normalizedResourceId,
  organizationStoragePrefix,
  referenceDataMatchesPolicy,
  storageObjectPathFromDownloadURL,
} from "./contentDeletionPolicy";

test("canonical content paths have one stable owner", () => {
  assert.equal(canonicalContentStoragePath("news", "news-1"), "news/news-1/cover.jpg");
  assert.equal(canonicalContentStoragePrefix("events", "event-1"), "events/event-1/");
  assert.equal(organizationStoragePrefix("org-1"), "organizations/org-1/");
});

test("deletion covers canonical and legacy organization draft media", () => {
  assert.equal(
    legacyDraftStoragePath("news", "org-1", "news-1"),
    "organizations/org-1/draftUploads/news/news-1_cover.jpg"
  );
  assert.deepEqual(contentStoragePrefixes("events", "event-1", "org-1"), [
    "events/event-1/",
    "organizations/org-1/draftUploads/events/event-1_cover.jpg",
  ]);
});

test("reference policies include every interaction owned by news and events", () => {
  assert.deepEqual(contentReferencePoliciesFor("news"), [
    {source: "collection", collectionId: "likes", field: "newsId"},
    {source: "collectionGroup", collectionId: "newsBookmarks", field: "newsId"},
    {source: "collectionGroup", collectionId: "newsViews", field: "newsId"},
    {
      source: "collectionGroup",
      collectionId: "recentViews",
      field: "itemId",
      filters: {itemType: "news"},
    },
    {
      source: "collectionGroup",
      collectionId: "activityLog",
      field: "targetId",
      filters: {targetType: "news"},
    },
    {
      source: "collectionGroup",
      collectionId: "notificationInbox",
      field: "actionTargetId",
      filters: {actionType: "openNews"},
    },
  ]);
  assert.deepEqual(contentReferencePoliciesFor("events"), [
    {source: "collection", collectionId: "likes", field: "eventId"},
    {source: "collection", collectionId: "registrations", field: "eventId"},
    {source: "collectionGroup", collectionId: "eventBookmarks", field: "eventId"},
    {source: "collectionGroup", collectionId: "eventViews", field: "eventId"},
    {
      source: "collectionGroup",
      collectionId: "recentViews",
      field: "itemId",
      filters: {itemType: "event"},
    },
    {
      source: "collectionGroup",
      collectionId: "activityLog",
      field: "targetId",
      filters: {targetType: "event"},
    },
    {
      source: "collectionGroup",
      collectionId: "notificationInbox",
      field: "actionTargetId",
      filters: {actionType: "openEvent"},
    },
  ]);
});

test("typed references cannot delete another content kind with the same ID", () => {
  const recentPolicy = contentReferencePoliciesFor("news")
    .find((policy) => policy.collectionId === "recentViews");
  assert.ok(recentPolicy);
  assert.equal(referenceDataMatchesPolicy({itemType: "news"}, recentPolicy), true);
  assert.equal(referenceDataMatchesPolicy({itemType: "event"}, recentPolicy), false);
  assert.equal(featuredBannerActionType("news"), "news");
  assert.equal(featuredBannerActionType("events"), "event");
});

test("Firebase and Google Storage URLs resolve to their object paths", () => {
  const objectPath = "organizations/org-1/draftUploads/news/news-1_cover.jpg";
  const firebaseURL = firebaseStorageDownloadURL(
    "example.firebasestorage.app",
    objectPath,
    "download-token"
  );
  assert.equal(storageObjectPathFromDownloadURL(firebaseURL), objectPath);
  assert.equal(
    storageObjectPathFromDownloadURL(`https://storage.googleapis.com/example.appspot.com/${objectPath}`),
    objectPath
  );
  assert.equal(storageObjectPathFromDownloadURL("https://example.com/image.jpg"), undefined);
});

test("organization deletion blocks active events but accepts archived cancellations", () => {
  assert.equal(eventBlocksOrganizationDeletion({moderationStatus: "approved"}), true);
  assert.equal(eventBlocksOrganizationDeletion({moderationStatus: "archived"}), false);
  assert.equal(eventBlocksOrganizationDeletion({
    moderationStatus: "approved",
    cancellationState: "cancelled",
  }), false);
});

test("request submitter may discard only their own unpublished organization request", () => {
  assert.equal(canDiscardOrganizationRequest("submitter", {
    submittedByUserId: "submitter",
    moderationStatus: "pendingReview",
  }), true);
  assert.equal(canDiscardOrganizationRequest("submitter", {
    submittedByUserId: "submitter",
    moderationStatus: "needsRevision",
  }), true);
  assert.equal(canDiscardOrganizationRequest("submitter", {
    submittedByUserId: "submitter",
    moderationStatus: "rejected",
  }), true);
  assert.equal(canDiscardOrganizationRequest("another-user", {
    submittedByUserId: "submitter",
    moderationStatus: "pendingReview",
  }), false);
  assert.equal(canDiscardOrganizationRequest("submitter", {
    submittedByUserId: "submitter",
    moderationStatus: "approved",
  }), false);
  assert.equal(canDiscardOrganizationRequest("submitter", {
    submittedByUserId: "submitter",
  }), false);
});

test("resource IDs reject empty values and path separators", () => {
  assert.equal(normalizedResourceId(" news-1 ", "newsId"), "news-1");
  assert.throws(() => normalizedResourceId("", "newsId"));
  assert.throws(() => normalizedResourceId("news/1", "newsId"));
});
