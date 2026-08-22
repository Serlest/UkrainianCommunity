import assert from "node:assert/strict";
import test from "node:test";

import {countGuideAnalyticsMarkers} from "./removedGuideAuditMarkers.mjs";

test("Guide analytics markers use schema values instead of prose substrings", () => {
  assert.equal(countGuideAnalyticsMarkers("School enrollment guide updated"), 0);
  assert.equal(countGuideAnalyticsMarkers({contentKeys: {"news_school-guide": true}}), 0);
  assert.equal(countGuideAnalyticsMarkers("guideArticle"), 1);
  assert.equal(countGuideAnalyticsMarkers("guide_article_view"), 1);
  assert.equal(countGuideAnalyticsMarkers({guideArticleViews: 4}), 1);
  assert.equal(countGuideAnalyticsMarkers({contentKeys: {guideArticle_legacy: true}}), 1);
});
