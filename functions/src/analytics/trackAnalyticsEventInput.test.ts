import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  analyticsActionProofDescriptor,
  assertAnalyticsUserProfileActive,
  analyticsLifecycleEventCount,
  analyticsLifecyclePeriodCounts,
  analyticsLifecycleWeightedPeriodCounts,
  analyticsEventDate,
  analyticsRegistrationDays,
  isValidAnalyticsActionProof,
  mergeAnalyticsTopContentSources,
  normalizeAnalyticsRegion,
  parseAnalyticsRequest,
  resolveRateLimitedAnalyticsContent,
  sanitizeAnalyticsEvent,
  regionStatsItemsFromData,
  topContentItemsFromData,
} from "./trackAnalyticsEvent";
import {analyticsActivityWindowIndex} from "./analyticsUserActivity";

const consentID = "123e4567-e89b-42d3-a456-426614174000";

test("accepts only the canonical analytics request envelope", () => {
  assert.equal(parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
    consentID,
  }).name, "news_view");

  assert.equal(parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
    consentID,
    occurredAtMilliseconds: 1_700_000_000_000,
  }).occurredAtMilliseconds, 1_700_000_000_000);

  assert.throws(() => parseAnalyticsRequest({
    eventName: "news_view",
    parameters: {content_id: "news-1"},
    consentID,
  }));
  assert.throws(() => parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
    consentID,
    actorUserId: "forged-user",
  }));
  assert.throws(() => parseAnalyticsRequest({
    name: "news_view",
    parameters: {content_id: "news-1"},
    consentID,
    occurredAtMilliseconds: "1700000000000",
  }));
});

test("uses bounded occurrence time for durable event delivery", () => {
  const receivedAt = new Date("2026-08-24T10:00:00.000Z");
  const occurredAt = new Date("2026-08-23T23:58:00.000Z");

  assert.equal(
    analyticsEventDate(occurredAt.getTime(), receivedAt).toISOString(),
    occurredAt.toISOString()
  );
  assert.equal(
    analyticsEventDate(undefined, receivedAt).toISOString(),
    receivedAt.toISOString()
  );
  assert.throws(() => analyticsEventDate(
    new Date("2026-08-22T09:59:59.000Z").getTime(),
    receivedAt
  ));
  assert.throws(() => analyticsEventDate(
    new Date("2026-08-24T10:05:01.000Z").getTime(),
    receivedAt
  ));
});

test("aggregate transaction fails closed for deleted or inactive profiles", () => {
  assert.doesNotThrow(() => assertAnalyticsUserProfileActive(
    "user-1",
    true,
    {accountStatus: "active", blockState: "warned"}
  ));
  assert.throws(
    () => assertAnalyticsUserProfileActive("user-1", false, undefined),
    (error) => error instanceof Error &&
      "code" in error && error.code === "permission-denied"
  );
  assert.throws(
    () => assertAnalyticsUserProfileActive(
      "user-1",
      true,
      {accountStatus: "deactivated"}
    ),
    (error) => error instanceof Error &&
      "code" in error && error.code === "permission-denied"
  );
});

test("maps positive actions to deterministic server proof documents", () => {
  assert.deepEqual(
    analyticsActionProofDescriptor("news_like", "user-1", "news-1"),
    {documentPath: "likes/news-1_user-1", contentField: "newsId"}
  );
  assert.deepEqual(
    analyticsActionProofDescriptor("event_register", "user-1", "event-1"),
    {
      documentPath: "registrations/event_event-1_user-1",
      contentField: "eventId",
    }
  );
  assert.equal(
    analyticsActionProofDescriptor("news_view", "user-1", "news-1"),
    undefined
  );
});

test("accepts action proof only for the actor, content, and Vienna day", () => {
  const descriptor = analyticsActionProofDescriptor(
    "news_bookmark",
    "user-1",
    "news-1"
  );
  assert.ok(descriptor);

  const proof = {
    userId: "user-1",
    newsId: "news-1",
    createdAt: Timestamp.fromDate(new Date("2026-08-23T22:01:00.000Z")),
  };
  assert.equal(isValidAnalyticsActionProof(
    proof,
    descriptor,
    "user-1",
    "news-1",
    new Date("2026-08-24T18:00:00.000Z")
  ), true);
  assert.equal(isValidAnalyticsActionProof(
    proof,
    descriptor,
    "other-user",
    "news-1",
    new Date("2026-08-24T18:00:00.000Z")
  ), false);
  assert.equal(isValidAnalyticsActionProof(
    proof,
    descriptor,
    "user-1",
    "news-1",
    new Date("2026-08-23T21:59:00.000Z")
  ), false);
});

test("folds city content into its federal state without inventing location data", () => {
  assert.deepEqual(
    normalizeAnalyticsRegion("city", "wien"),
    {regionScope: "federalState", federalState: "wien"}
  );
  assert.deepEqual(
    normalizeAnalyticsRegion("federalState", "wien"),
    {regionScope: "federalState", federalState: "wien"}
  );
  assert.deepEqual(
    normalizeAnalyticsRegion("austria", "wien"),
    {regionScope: "austria"}
  );
  assert.equal(normalizeAnalyticsRegion("city", undefined), undefined);
});

test("uses canonical content metadata instead of client supplied values", () => {
  const request = parseAnalyticsRequest({
    name: "news_view",
    parameters: {
      content_id: "news-1",
      content_type: "news",
      content_title: "Forged title",
      organization_id: "forged-organization",
      organization_name: "Forged organization",
      category: "forged",
      federal_state: "tirol",
      region_scope: "federalState",
    },
    consentID,
  });

  const event = sanitizeAnalyticsEvent(request, {
    contentID: "news-1",
    contentType: "news",
    title: "Canonical title",
    organizationID: "canonical-organization",
    organizationName: "Canonical organization",
    category: "community",
    federalState: "wien",
    regionScope: "federalState",
  });

  assert.equal(event.title, "Canonical title");
  assert.equal(event.organizationID, "canonical-organization");
  assert.equal(event.organizationName, "Canonical organization");
  assert.equal(event.category, "community");
  assert.equal(event.federalState, "wien");
});

test("newest top-content metadata absence is authoritative", () => {
  const result = mergeAnalyticsTopContentSources([
    [{
      contentID: "news-1",
      contentType: "news",
      title: "Current title",
      viewCount: 2,
      rank: 0,
    }],
    [{
      contentID: "news-1",
      contentType: "news",
      title: "Old title",
      category: "community",
      organizationID: "old-organization",
      organizationName: "Old organization",
      regionScope: "federalState",
      federalState: "tirol",
      viewCount: 3,
      rank: 0,
    }],
  ]);

  assert.equal(result.length, 1);
  assert.equal(result[0].title, "Current title");
  assert.equal(result[0].viewCount, 5);
  assert.equal(result[0].category, undefined);
  assert.equal(result[0].organizationID, undefined);
  assert.equal(result[0].regionScope, undefined);
  assert.equal(result[0].federalState, undefined);
});

test("malformed keyed rollup maps fall back to valid legacy arrays", () => {
  const topItems = topContentItemsFromData({
    itemsByKey: {
      broken: {
        contentID: "zero-news",
        contentType: "news",
        viewCount: 0,
      },
    },
    items: [{
      contentID: "news-1",
      contentType: "news",
      title: "Legacy news",
      viewCount: 4,
    }],
  });
  const regions = regionStatsItemsFromData({
    regionsByKey: {broken: {regionScope: "invalid"}},
    regions: [{
      regionScope: "federalState",
      federalState: "wien",
      viewCount: 3,
      metrics: {newsViews: 3},
    }],
  });

  assert.equal(topItems[0]?.contentID, "news-1");
  assert.equal(regions[0]?.federalState, "wien");
  assert.equal(regions[0]?.viewCount, 3);
});

test("rejects mismatched canonical content identity", () => {
  const request = parseAnalyticsRequest({
    name: "event_view",
    parameters: {content_id: "event-1"},
    consentID,
  });

  assert.throws(() => sanitizeAnalyticsEvent(request, {
    contentID: "different-event",
    contentType: "event",
    title: "Canonical event",
  }));
});

test("consumes one attempt before resolving canonical analytics content", async () => {
  const calls: string[] = [];
  const receivedAt = new Date("2026-08-24T10:00:00.000Z");
  const content = await resolveRateLimitedAnalyticsContent(
    "user-1",
    "news",
    "news-1",
    receivedAt,
    {
      consumeRateLimit: async (uid, date) => {
        calls.push(`rate:${uid}:${date.toISOString()}`);
      },
      resolveCanonicalContent: async (contentType, contentID) => {
        calls.push(`read:${contentType}:${contentID}`);
        return {contentID, contentType, title: "Canonical news"};
      },
    }
  );

  assert.equal(content.contentID, "news-1");
  assert.deepEqual(calls, [
    `rate:user-1:${receivedAt.toISOString()}`,
    "read:news:news-1",
  ]);

  calls.length = 0;
  await assert.rejects(resolveRateLimitedAnalyticsContent(
    "user-1",
    "news",
    "missing-news",
    receivedAt,
    {
      consumeRateLimit: async () => {
        calls.push("rate");
        throw new Error("rate exhausted");
      },
      resolveCanonicalContent: async () => {
        calls.push("read");
        return {contentID: "missing-news", contentType: "news", title: "Unexpected"};
      },
    }
  ));
  assert.deepEqual(calls, ["rate"]);
});

test("registration markers survive deletion and deduplicate legacy fallback", () => {
  const now = new Date("2026-08-24T12:00:00.000Z");
  const days = analyticsRegistrationDays([
    {analyticsDay: "2026-08-23", userKey: "user-a"},
    // A deleted user is no longer in currentUsers but remains in the ledger.
    {analyticsDay: "2026-08-22", userKey: "deleted-user"},
  ], [
    // The marker wins, so current profile fallback does not double count user-a.
    {userKey: "user-a", createdAt: new Date("2026-08-23T08:00:00.000Z")},
    {userKey: "legacy-user", createdAt: new Date("2026-08-21T08:00:00.000Z")},
    {userKey: "future-user", createdAt: new Date("2026-08-25T08:00:00.000Z")},
  ], now);

  assert.deepEqual(days, ["2026-08-23", "2026-08-22", "2026-08-21"]);
  assert.equal(
    analyticsLifecycleEventCount(days, ["2026-08-24", "2026-08-23", "2026-08-22"]),
    2
  );
});

test("lifecycle counters aggregate large pages with one shared window index", () => {
  const windowIndex = analyticsActivityWindowIndex(
    new Date("2026-08-24T12:00:00.000Z")
  );
  const eventDays = Array.from({length: 30_000}, (_, index) => {
    switch (index % 3) {
      case 0:
        return "2026-08-24";
      case 1:
        return "2026-08-20";
      default:
        return "2026-07-20";
    }
  });

  assert.deepEqual(
    analyticsLifecyclePeriodCounts(eventDays, windowIndex),
    {today: 10_000, sevenDays: 20_000, thirtyDays: 20_000}
  );
});

test("legacy lifecycle baselines add weighted daily counts without synthetic users", () => {
  const windowIndex = analyticsActivityWindowIndex(
    new Date("2026-08-24T12:00:00.000Z")
  );
  assert.deepEqual(analyticsLifecycleWeightedPeriodCounts([
    {analyticsDay: "2026-08-24", count: 2},
    {analyticsDay: "2026-08-20", count: 3},
    {analyticsDay: "2026-08-01", count: 5},
    {analyticsDay: "2026-07-01", count: 100},
  ], windowIndex), {
    today: 2,
    sevenDays: 5,
    thirtyDays: 10,
  });
  assert.throws(() => analyticsLifecycleWeightedPeriodCounts([
    {analyticsDay: "2026-08-24", count: -1},
  ], windowIndex));
});
