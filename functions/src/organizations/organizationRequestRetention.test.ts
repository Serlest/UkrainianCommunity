import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {
  organizationRequestActivityMilliseconds,
  organizationRequestRetentionState,
} from "./organizationRequestRetention";

const day = 24 * 60 * 60 * 1_000;

test("organization request activity uses the newest canonical activity field", () => {
  const updatedAt = Timestamp.fromMillis(4000);
  assert.equal(organizationRequestActivityMilliseconds({
    updatedAt,
    reviewedAt: Timestamp.fromMillis(3000),
    submittedAt: Timestamp.fromMillis(2000),
    createdAt: Timestamp.fromMillis(1000),
  }), 4000);
  assert.equal(organizationRequestActivityMilliseconds({
    submittedAt: Timestamp.fromMillis(2000),
  }), 2000);
  assert.equal(organizationRequestActivityMilliseconds({}), undefined);
});

test("retention warns seven days before expiry and expires at day 30", () => {
  const activity = Date.UTC(2026, 0, 1);
  assert.equal(organizationRequestRetentionState(activity, activity + 22 * day), "active");
  assert.equal(organizationRequestRetentionState(activity, activity + 23 * day), "warning");
  assert.equal(organizationRequestRetentionState(activity, activity + 29 * day), "warning");
  assert.equal(organizationRequestRetentionState(activity, activity + 30 * day), "expired");
});

test("future activity never enters cleanup", () => {
  assert.equal(organizationRequestRetentionState(2000, 1000), "active");
});
