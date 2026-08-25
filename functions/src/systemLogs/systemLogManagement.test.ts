import * as assert from "node:assert/strict";
import {describe, test} from "node:test";

import {isEmptyRequest} from "./systemLogManagement";

describe("system log clear request", () => {
  test("accepts only an empty payload", () => {
    assert.equal(isEmptyRequest(undefined), true);
    assert.equal(isEmptyRequest(null), true);
    assert.equal(isEmptyRequest({}), true);
    assert.equal(isEmptyRequest({scope: "all"}), false);
    assert.equal(isEmptyRequest([]), false);
  });
});
