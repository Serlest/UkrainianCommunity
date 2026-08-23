import { strict as assert } from "node:assert";
import { test } from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import {
  canonicalFeaturedBannerData,
  parseFeaturedBannerDraft,
  parseFeaturedBannerSaveRequest,
} from "./featuredBannerMutations";

function validDraft(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "banner-1",
    internalName: " Summer campaign ",
    title: " Community day ",
    subtitle: " Meet in Vienna ",
    imageURL: "https://example.com/new-hero.jpg",
    actionType: "none",
    regionScope: "allAustria",
    visibleSections: ["organizations", "home"],
    displayDurationSeconds: 6,
    priority: 25,
    isActive: true,
    ...overrides,
  };
}

test("normalizes cleared text and stale conditional fields", () => {
  const parsed = parseFeaturedBannerDraft(validDraft({
    title: "   ",
    subtitle: "",
    actionTargetID: "stale-target",
    externalURL: "https://example.com/stale",
    federalState: "wien",
  }));

  assert.equal(parsed.title, undefined);
  assert.equal(parsed.subtitle, undefined);
  assert.equal(parsed.actionTargetID, undefined);
  assert.equal(parsed.externalURL, undefined);
  assert.equal(parsed.federalState, undefined);
  assert.deepEqual(parsed.visibleSections, ["home", "organizations"]);
});

test("canonical update preserves identity and removes cleared or legacy fields", () => {
  const createdAt = Timestamp.fromMillis(1_700_000_000_000);
  const committedAt = Timestamp.fromMillis(1_800_000_000_000);
  const parsed = parseFeaturedBannerDraft(validDraft({ title: "", subtitle: "" }));

  const data = canonicalFeaturedBannerData(parsed, "current-owner", committedAt, {
    id: "wrong-legacy-id",
    title: "Old title",
    subtitle: "Old subtitle",
    imageURL: "https://example.com/old.jpg",
    createdAt,
    createdBy: "original-owner",
    retiredField: "must disappear",
  });

  assert.equal(data.id, "banner-1");
  assert.equal(data.imageURL, "https://example.com/new-hero.jpg");
  assert.equal(data.title, undefined);
  assert.equal(data.subtitle, undefined);
  assert.equal(data.retiredField, undefined);
  assert.equal(data.createdAt, createdAt);
  assert.equal(data.createdBy, "original-owner");
  assert.equal(data.updatedAt, committedAt);
  assert.equal(data.updatedBy, "current-owner");
});

test("save request requires an explicit create or update mode", () => {
  assert.equal(
    parseFeaturedBannerSaveRequest({ mode: "update", banner: validDraft() }).mode,
    "update"
  );
  assert.throws(() => parseFeaturedBannerSaveRequest({ mode: "replace", banner: validDraft() }));
});

test("requires action targets, valid dates, and supported web image URLs", () => {
  assert.throws(() => parseFeaturedBannerDraft(validDraft({ actionType: "event" })));
  assert.throws(() => parseFeaturedBannerDraft(validDraft({ imageURL: "file:///tmp/banner.jpg" })));
  assert.throws(() => parseFeaturedBannerDraft(validDraft({
    startsAt: "2026-08-24T12:00:00.000Z",
    endsAt: "2026-08-24T11:00:00.000Z",
  })));
});
