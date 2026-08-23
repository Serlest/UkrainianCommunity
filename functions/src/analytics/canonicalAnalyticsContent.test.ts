import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {canonicalAnalyticsContentFromData} from "./canonicalAnalyticsContent";

test("uses canonical news metadata from Firestore", () => {
  assert.deepEqual(canonicalAnalyticsContentFromData("news", "news-1", {
    moderationStatus: "approved",
    title: "  Canonical   title ",
    category: "community",
    organizationId: "organization-1",
    organizationName: "Community Wien",
    regionScope: "federalState",
    federalState: "wien",
  }), {
    contentID: "news-1",
    contentType: "news",
    title: "Canonical title",
    category: "community",
    organizationID: "organization-1",
    organizationName: "Community Wien",
    regionScope: "federalState",
    federalState: "wien",
  });
});

test("uses organization identity as canonical analytics metadata", () => {
  assert.deepEqual(canonicalAnalyticsContentFromData("organization", "org-1", {
    moderationStatus: "approved",
    name: "Organization Tirol",
    regionScope: "austria",
  }), {
    contentID: "org-1",
    contentType: "organization",
    title: "Organization Tirol",
    organizationID: "org-1",
    organizationName: "Organization Tirol",
    regionScope: "austria",
  });
});

test("rejects unapproved, archived, and malformed analytics content", () => {
  const invalidDocuments = [
    {moderationStatus: "pendingReview", title: "Pending"},
    {moderationStatus: "approved", title: "Archived", archivedAt: new Date()},
    {moderationStatus: "approved", title: "   "},
  ];

  for (const document of invalidDocuments) {
    assert.throws(
      () => canonicalAnalyticsContentFromData("news", "news-1", document),
      (error) => error instanceof HttpsError
    );
  }
});

test("drops invalid optional metadata instead of persisting it", () => {
  assert.deepEqual(canonicalAnalyticsContentFromData("event", "event-1", {
    moderationStatus: "approved",
    title: "Community event",
    category: "invalid category",
    organizationId: "invalid/path",
    regionScope: "planet",
    federalState: "outside-austria",
  }), {
    contentID: "event-1",
    contentType: "event",
    title: "Community event",
  });
});
