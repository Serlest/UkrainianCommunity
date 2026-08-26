import {strict as assert} from "node:assert";
import {describe, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {eventPublishingFieldChanged, nextEventStartMillis} from "./eventNotificationSemantics";

describe("event notification semantics", () => {
  test("detects a changed time inside an occurrence", () => {
    const before = {occurrences: [{id: "one", startDate: Timestamp.fromMillis(2_000)}]};
    const after = {occurrences: [{id: "one", startDate: Timestamp.fromMillis(3_000)}]};
    assert.equal(eventPublishingFieldChanged(before, after), true);
  });

  test("does not report equivalent nested publishing values as changed", () => {
    const before = {pricing: {kind: "free", currencyCode: "EUR"}};
    const after = {pricing: {currencyCode: "EUR", kind: "free"}};
    assert.equal(eventPublishingFieldChanged(before, after), false);
  });

  test("uses the next scheduled occurrence and ignores cancelled sessions", () => {
    const result = nextEventStartMillis({
      startDate: Timestamp.fromMillis(1_000),
      occurrences: [
        {startDate: Timestamp.fromMillis(2_000), status: "cancelled"},
        {startDate: Timestamp.fromMillis(5_000), status: "scheduled"},
        {startDate: Timestamp.fromMillis(4_000), status: "scheduled"},
      ],
    }, 3_000);
    assert.equal(result, 4_000);
  });
});
