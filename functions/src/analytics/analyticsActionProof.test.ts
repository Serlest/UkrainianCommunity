import {strict as assert} from "node:assert";
import {test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  analyticsActionProofDocumentData,
  analyticsActionReceiptID,
  analyticsActorBinding,
  analyticsSessionBinding,
  isMatchingAnalyticsActionReceipt,
  optionalAnalyticsActionProofBinding,
  requireMatchingAnalyticsActionProofBinding,
  validateAnalyticsActionProof,
  type AnalyticsActionProofBinding,
} from "./analyticsActionProof";

const proofID = "123e4567-e89b-42d3-a456-426614174000";
const consentID = "223e4567-e89b-42d3-a456-426614174000";

function binding(overrides: Partial<AnalyticsActionProofBinding> = {}): AnalyticsActionProofBinding {
  return {
    proofID,
    eventName: "news_bookmark",
    contentID: "news-1",
    actorBinding: analyticsActorBinding("user-1", proofID),
    sessionBinding: analyticsSessionBinding(consentID, proofID),
    ...overrides,
  };
}

test("accepts only an exact privacy-minimized proof binding schema", () => {
  const value = binding();
  assert.deepEqual(optionalAnalyticsActionProofBinding(value), value);

  for (const invalid of [
    {...value, extra: true},
    {...value, proofID: "not-a-uuid"},
    {...value, eventName: "news_view"},
    {...value, contentID: "bad/path"},
    {...value, actorBinding: "user-1"},
    {...value, sessionBinding: "session-1"},
  ]) {
    assert.throws(
      () => optionalAnalyticsActionProofBinding(invalid),
      (error) => error instanceof HttpsError && error.code === "invalid-argument"
    );
  }
});

test("rejects reuse for another event or content item", () => {
  const value = binding();
  assert.throws(
    () => requireMatchingAnalyticsActionProofBinding(value, "event_bookmark", "news-1"),
    (error) => error instanceof HttpsError && error.code === "invalid-argument"
  );
  assert.throws(
    () => requireMatchingAnalyticsActionProofBinding(value, "news_bookmark", "news-2"),
    (error) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});

test("uses opaque per-proof actor and receipt identifiers", () => {
  const actor = analyticsActorBinding("private-user-id", proofID);
  const receipt = analyticsActionReceiptID(proofID);

  assert.match(actor, /^[a-f0-9]{64}$/);
  assert.match(receipt, /^[a-f0-9]{64}$/);
  assert.equal(actor.includes("private-user-id"), false);
  assert.equal(receipt.includes(proofID), false);
  assert.notEqual(actor, analyticsActorBinding("other-user", proofID));
});

test("validates immutable proof identity, principal, session, and bounded lifetime", () => {
  const value = binding();
  const createdAt = new Date("2026-08-24T21:59:59.900Z");
  const receivedAt = new Date("2026-08-24T22:00:02.000Z");
  const data = analyticsActionProofDocumentData(value, "user-1", createdAt);

  const validated = validateAnalyticsActionProof(data, value, "user-1", consentID, receivedAt);
  assert.equal(validated.createdAt.toISOString(), createdAt.toISOString());
  assert.equal(
    validated.expiresAt.toISOString(),
    "2026-08-26T21:59:59.900Z"
  );

  for (const [invalidData, invalidBinding, uid] of [
    [{...data, contentId: "news-2"}, value, "user-1"],
    [data, binding({sessionBinding: "c".repeat(64)}), "user-1"],
    [data, value, "user-2"],
    [{...data, expiresAt: Timestamp.fromDate(new Date("2026-08-27T00:00:00Z"))}, value, "user-1"],
  ] as const) {
    assert.throws(
      () => validateAnalyticsActionProof(invalidData, invalidBinding, uid, consentID, receivedAt),
      (error) => error instanceof HttpsError && error.code === "failed-precondition"
    );
  }
});

test("accepts an idempotency receipt only for the exact consumed proof", () => {
  const value = binding();
  const receipt = {
    receiptKind: "actionProof",
    proofId: value.proofID,
    actorBinding: value.actorBinding,
    eventName: value.eventName,
    contentType: "news",
    contentID: value.contentID,
    sessionBinding: value.sessionBinding,
  };

  assert.equal(
    isMatchingAnalyticsActionReceipt(receipt, value, "user-1", "news"),
    true
  );
  assert.equal(
    isMatchingAnalyticsActionReceipt(receipt, value, "user-2", "news"),
    false
  );
  assert.equal(
    isMatchingAnalyticsActionReceipt({...receipt, contentID: "news-2"}, value, "user-1", "news"),
    false
  );
});
