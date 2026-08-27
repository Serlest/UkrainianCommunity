import {strict as assert} from "node:assert";
import {describe, it} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  hasReachedOrganizationRequestLimit,
  parseOrganizationRulesAcceptanceRequest,
} from "./organizationRulesAcceptance";

describe("organization rules acceptance request", () => {
  it("normalizes a valid organization-bound request", () => {
    assert.deepEqual(parseOrganizationRulesAcceptanceRequest({
      organizationId: " 123e4567-e89b-12d3-a456-426614174000 ",
      organizationName: " Український магазин ",
      version: " 2026.10 ",
      locale: " uk ",
    }), {
      organizationId: "123e4567-e89b-12d3-a456-426614174000",
      organizationName: "Український магазин",
      version: "2026.10",
      locale: "uk",
      acceptedFromPlatform: "ios",
      appVersion: undefined,
    });
  });

  it("rejects an unsafe organization id", () => {
    assert.throws(
      () => parseOrganizationRulesAcceptanceRequest({
        organizationId: "../other",
        organizationName: "Name",
        version: "2026.10",
      }),
      (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
    );
  });

  it("allows three unpublished requests and blocks the next one", () => {
    assert.equal(hasReachedOrganizationRequestLimit(2), false);
    assert.equal(hasReachedOrganizationRequestLimit(3), true);
    assert.equal(hasReachedOrganizationRequestLimit(4), true);
  });
});
