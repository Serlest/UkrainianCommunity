import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  analyticsDetailCoverage,
  isAnalyticsDetailRollupGenerationCurrent,
  mergeAnalyticsDetailDocuments,
  selectAnalyticsDetailPage,
  staleAnalyticsDetailDocumentIDs,
} from "./analyticsDetailRollup";

test("detail coverage remains partial until the whole selected window is v2", () => {
  assert.deepEqual(analyticsDetailCoverage([
    "2026-08-24",
    "2026-08-23",
    "2026-08-22",
  ], "2026-08-23"), {
    coverageStartDay: "2026-08-23",
    coveredSourceDocumentIDs: ["2026-08-24", "2026-08-23"],
    isPartialCoverage: true,
  });
  assert.deepEqual(analyticsDetailCoverage([
    "2026-08-24",
    "2026-08-23",
  ], "2026-08-23"), {
    coverageStartDay: "2026-08-23",
    coveredSourceDocumentIDs: ["2026-08-24", "2026-08-23"],
    isPartialCoverage: false,
  });
  assert.throws(() => analyticsDetailCoverage(["today"], "2026-08-23"));
});

test("detail rollup generation ownership fails closed", () => {
  assert.equal(isAnalyticsDetailRollupGenerationCurrent({
    rollupInProgressGeneration: "generation-2",
  }, "generation-2"), true);
  assert.equal(isAnalyticsDetailRollupGenerationCurrent({
    rollupInProgressGeneration: "generation-3",
  }, "generation-2"), false);
  assert.equal(isAnalyticsDetailRollupGenerationCurrent(undefined, "generation-2"), false);
});

test("detail pagination merges sorted source heads within a strict item bound", () => {
  const currentDocuments = [
    {itemID: "a", data: {metrics: {views: 2}}},
    {itemID: "c", data: {metrics: {views: 3}}},
    {itemID: "e", data: {metrics: {views: 5}}},
  ];
  const olderDocuments = [
    {itemID: "a", data: {metrics: {views: 7}}},
    {itemID: "b", data: {metrics: {views: 11}}},
    {itemID: "d", data: {metrics: {views: 13}}},
  ];

  const page = selectAnalyticsDetailPage([
    {
      sourceDocumentID: "2026-08-24",
      documents: currentDocuments,
      hasMore: false,
    },
    {
      sourceDocumentID: "2026-08-23",
      documents: olderDocuments,
      hasMore: false,
    },
  ], 2);

  assert.deepEqual(page.itemIDs, ["a", "b"]);
  assert.deepEqual(page.consumedDocumentCounts, [1, 2]);
  assert.equal(page.requiresRefill, false);
  assert.deepEqual(
    page.documentsByItemID.get("a")?.map((document) =>
      document.sourceDocumentID
    ),
    ["2026-08-24", "2026-08-23"]
  );
  assert.equal(page.documentsByItemID.size, 2);
  assert.equal(currentDocuments.length, 3);
  assert.equal(olderDocuments.length, 3);
});

test("detail pagination pauses at a source-buffer boundary before advancing", () => {
  const page = selectAnalyticsDetailPage([
    {
      sourceDocumentID: "2026-08-24",
      documents: [{itemID: "a", data: {metrics: {views: 1}}}],
      hasMore: true,
    },
    {
      sourceDocumentID: "2026-08-23",
      documents: [
        {itemID: "b", data: {metrics: {views: 2}}},
        {itemID: "c", data: {metrics: {views: 3}}},
      ],
      hasMore: false,
    },
  ], 3);

  assert.deepEqual(page.itemIDs, ["a"]);
  assert.deepEqual(page.consumedDocumentCounts, [1, 0]);
  assert.equal(page.requiresRefill, true);
});

test("detail pagination resumes without losing cross-source merge inputs", () => {
  const page = selectAnalyticsDetailPage([
    {
      sourceDocumentID: "2026-08-24",
      documents: [
        {itemID: "b", data: {contentTitle: "Current", metrics: {views: 4}}},
        {itemID: "d", data: {metrics: {views: 8}}},
      ],
      hasMore: false,
    },
    {
      sourceDocumentID: "2026-08-23",
      documents: [
        {itemID: "b", data: {contentTitle: "Older", metrics: {views: 6}}},
        {itemID: "c", data: {metrics: {views: 7}}},
      ],
      hasMore: false,
    },
  ], 2);
  const merged = mergeAnalyticsDetailDocuments(
    page.documentsByItemID.get("b")?.map((document) => document.data) ?? [],
    "seven_days"
  );

  assert.deepEqual(page.itemIDs, ["b", "c"]);
  assert.deepEqual(page.consumedDocumentCounts, [1, 2]);
  assert.equal(merged?.contentTitle, "Current");
  assert.deepEqual(merged?.metrics, {views: 10});
});

test("detail pagination rejects an unbounded or empty page size", () => {
  assert.throws(
    () => selectAnalyticsDetailPage([], 0),
    /positive integer/
  );
  assert.throws(
    () => selectAnalyticsDetailPage([], Number.POSITIVE_INFINITY),
    /positive integer/
  );
});

test("detail cleanup removes legacy and previous generations only", () => {
  assert.deepEqual(staleAnalyticsDetailDocumentIDs([
    {documentID: "current", rollupGeneration: "generation-2"},
    {documentID: "previous", rollupGeneration: "generation-1"},
    {documentID: "legacy", rollupGeneration: undefined},
  ], "generation-2"), ["previous", "legacy"]);
});

test("detail rollups sum metrics while keeping current canonical metadata", () => {
  const result = mergeAnalyticsDetailDocuments([
    {
      contentID: "news-1",
      contentType: "news",
      contentTitle: "Current title",
      metrics: {views: 4, likes: 2},
      regionsByKey: {
        federalState_tirol: {
          regionScope: "federalState",
          federalState: "tirol",
          metrics: {views: 3, likes: 1},
        },
      },
    },
    {
      contentID: "news-1",
      contentType: "news",
      contentTitle: "Older title",
      metrics: {views: 6, bookmarks: 1},
      regionsByKey: {
        federalState_tirol: {
          regionScope: "federalState",
          federalState: "tirol",
          metrics: {views: 5, bookmarks: 1},
        },
      },
    },
  ], "seven_days");

  assert.equal(result?.periodId, "seven_days");
  assert.equal(result?.contentTitle, "Current title");
  assert.deepEqual(result?.metrics, {views: 10, likes: 2, bookmarks: 1});
  assert.deepEqual(result?.regionsByKey.federalState_tirol.metrics, {
    views: 8,
    likes: 1,
    bookmarks: 1,
  });
});

test("detail rollups preserve newest explicit metadata removal", () => {
  const result = mergeAnalyticsDetailDocuments([
    {
      contentID: "news-1",
      contentType: "news",
      contentTitle: "Current title",
      category: null,
      organizationID: null,
      regionScope: "austria",
      federalState: null,
      metrics: {views: 2},
    },
    {
      contentID: "news-1",
      contentType: "news",
      contentTitle: "Old title",
      category: "community",
      organizationID: "old-organization",
      regionScope: "federalState",
      federalState: "tirol",
      metrics: {views: 3},
    },
  ], "seven_days");

  assert.equal(result?.contentTitle, "Current title");
  assert.equal(result?.category, null);
  assert.equal(result?.organizationID, null);
  assert.equal(result?.regionScope, "austria");
  assert.equal(result?.federalState, null);
  assert.deepEqual(result?.metrics, {views: 5});
});

test("organization detail rollups merge top content by stable key", () => {
  const result = mergeAnalyticsDetailDocuments([
    {
      organizationID: "org-1",
      metrics: {profileViews: 5},
      topEvents: {
        event_event__1: {
          contentID: "event_1",
          contentType: "event",
          contentTitle: "Event",
          metrics: {views: 4, registrations: 2},
        },
      },
    },
    {
      organizationID: "org-1",
      metrics: {profileViews: 3, eventViews: 7},
      topEvents: {
        event_event__1: {
          contentID: "event_1",
          contentType: "event",
          contentTitle: "Event",
          metrics: {views: 7, registrations: 1},
        },
      },
    },
  ], "thirty_days");

  assert.deepEqual(result?.metrics, {profileViews: 8, eventViews: 7});
  assert.deepEqual(result?.topEvents.event_event__1.metrics, {
    views: 11,
    registrations: 3,
  });
});

test("detail rollups cap nested maps by view relevance", () => {
  const topNews = Object.fromEntries(Array.from({length: 55}, (_, index) => [
    `news_${index}`,
    {
      contentID: `news-${index}`,
      metrics: {views: index + 1, likes: 1_000 - index},
    },
  ]));
  const result = mergeAnalyticsDetailDocuments([{topNews}], "thirty_days");
  const keys = Object.keys(result?.topNews ?? {});

  assert.equal(keys.length, 50);
  assert.equal(keys.includes("news_54"), true);
  assert.equal(keys.includes("news_0"), false);
});
