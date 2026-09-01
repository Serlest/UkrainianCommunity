import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  firebaseDownloadURLsForStorageObject,
  featuredBannerIdFromObjectName,
  isStaleOrphan,
  orphanContentObjectIdentity,
  orphanOrganizationLogoIdentity,
} from "./storageOrphanCleanup";

test("featured banner orphan cleanup accepts only canonical image paths", () => {
  assert.equal(
    featuredBannerIdFromObjectName("featuredBanners/banner-1/hero.jpg"),
    "banner-1"
  );
  assert.equal(
    featuredBannerIdFromObjectName("featuredBanners/banner-1/hero-version-1.jpg"),
    "banner-1"
  );
  assert.equal(
    featuredBannerIdFromObjectName("featuredBanners/banner-1/private.jpg"),
    undefined
  );
  assert.equal(featuredBannerIdFromObjectName("news/banner-1/cover.jpg"), undefined);
});

test("orphan cleanup preserves uploads during a 24 hour save grace period", () => {
  const now = Date.UTC(2026, 7, 25, 12);
  assert.equal(isStaleOrphan(now - 23 * 60 * 60 * 1000, now), false);
  assert.equal(isStaleOrphan(now - 24 * 60 * 60 * 1000, now), true);
  assert.equal(isStaleOrphan(Number.NaN, now), false);
});

test("content orphan parser accepts only owned canonical and legacy paths", () => {
  assert.deepEqual(orphanContentObjectIdentity("news/news-1/cover.jpg"), {
    kind: "news",
    contentId: "news-1",
  });
  assert.deepEqual(orphanContentObjectIdentity("events/event-1/cover.jpg"), {
    kind: "events",
    contentId: "event-1",
  });
  assert.deepEqual(orphanContentObjectIdentity(
    "organizations/org-1/draftUploads/news/news-legacy_cover.jpg"
  ), {
    kind: "news",
    contentId: "news-legacy",
  });
  assert.deepEqual(orphanContentObjectIdentity(
    "organizations/org-1/events/event-legacy/upload.png"
  ), {
    kind: "events",
    contentId: "event-legacy",
  });
  assert.equal(orphanContentObjectIdentity(
    "organizations/org-1/events/event-legacy/upload.pdf"
  ), undefined);
  assert.equal(orphanContentObjectIdentity("organizations/org-1/logo.jpg"), undefined);
  assert.equal(orphanContentObjectIdentity("users/user-1/avatar.jpg"), undefined);
  assert.equal(orphanContentObjectIdentity("featuredBanners/banner-1/hero.jpg"), undefined);
});

test("organization logo cleanup accepts only the canonical logo object", () => {
  assert.deepEqual(
    orphanOrganizationLogoIdentity("organizations/org-1/logo.jpg"),
    {organizationId: "org-1"}
  );
  assert.equal(
    orphanOrganizationLogoIdentity("organizations/org-1/photos/photo-1.jpg"),
    undefined
  );
  assert.equal(
    orphanOrganizationLogoIdentity("organizations/org-1/logo.png"),
    undefined
  );
});

test("builds exact Firebase download URLs only from explicit metadata tokens", () => {
  assert.deepEqual(firebaseDownloadURLsForStorageObject(
    "example.firebasestorage.app",
    "organizations/org-1/logo.jpg",
    {firebaseStorageDownloadTokens: "token-1, token-2, token-1"}
  ), [
    "https://firebasestorage.googleapis.com/v0/b/example.firebasestorage.app/o/"
      + "organizations%2Forg-1%2Flogo.jpg?alt=media&token=token-1",
    "https://firebasestorage.googleapis.com/v0/b/example.firebasestorage.app/o/"
      + "organizations%2Forg-1%2Flogo.jpg?alt=media&token=token-2",
  ]);
  assert.deepEqual(firebaseDownloadURLsForStorageObject(
    "example.firebasestorage.app",
    "organizations/org-1/logo.jpg",
    {}
  ), []);
});
