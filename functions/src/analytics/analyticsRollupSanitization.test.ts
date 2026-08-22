import {strict as assert} from "node:assert";
import {test} from "node:test";

import {hasActiveRegionAnalytics} from "./analyticsRollupSanitization";

test("Guide-only regions are removed after active analytics are filtered", () => {
  assert.equal(hasActiveRegionAnalytics(0, 0), false);
  assert.equal(hasActiveRegionAnalytics(1, 0), true);
  assert.equal(hasActiveRegionAnalytics(0, 1), true);
});
