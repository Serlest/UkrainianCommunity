import * as assert from "node:assert/strict";
import {describe, test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {parseDiagnostic, assertDiagnosticPrincipal} from "./clientDiagnostics";

function validDiagnostic() {
  return {
    eventType: "technicalError",
    severity: "error",
    targetType: "event",
    summary: "Failed to load an event",
    metadata: {operation: "load"},
  };
}

describe("client diagnostic validation", () => {
  test("accepts and normalizes a bounded diagnostic", () => {
    const parsed = parseDiagnostic(validDiagnostic());
    assert.equal(parsed.eventType, "technicalError");
    assert.equal(parsed.severity, "error");
    assert.equal(parsed.summary, "Failed to load an event");
    assert.deepEqual(parsed.metadata, {operation: "load"});
  });

  test("rejects unsupported fields and oversized private payloads", () => {
    assert.throws(
      () => parseDiagnostic({...validDiagnostic(), actorRole: "owner"}),
      (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
    );
    assert.throws(
      () => parseDiagnostic({...validDiagnostic(), technicalMessage: "x".repeat(1_521)}),
      (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
    );
  });
});

test("diagnostic identity fence accepts legacy clients and rejects a different session", () => {
  assert.doesNotThrow(() => assertDiagnosticPrincipal(undefined, "current"));
  assert.doesNotThrow(() => assertDiagnosticPrincipal("current", "current"));
  assert.throws(() => assertDiagnosticPrincipal("previous", "current"), {code: "failed-precondition"});
  assert.equal(parseDiagnostic({...validDiagnostic(), principalId: "current"}).principalId, "current");
});
