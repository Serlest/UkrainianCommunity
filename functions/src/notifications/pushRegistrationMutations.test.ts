import { strict as assert } from "node:assert";
import { describe, test } from "node:test";

import {
  assertPushRegistrationOwner,
  parsePushRegistrationDeletionRequest,
  registrationDeletionPageSize,
  registrationDocumentIDsForDeletion,
} from "./pushRegistrationMutations";

const fidA = "a123456789012345678901";
const fidB = "b123456789012345678901";

describe("push registration deletion", () => {
  test("keeps every Firestore cleanup page below the write-batch limit", () => {
    assert.equal(registrationDeletionPageSize, 250);
    assert.ok(registrationDeletionPageSize <= 500);
  });

  test("parses a strict FID deletion request", () => {
    assert.deepEqual(parsePushRegistrationDeletionRequest({
      userId: " user-a ",
      identifier: ` ${fidA} `,
      registrationType: "fid",
    }), {
      userId: "user-a",
      identifier: fidA,
      registrationType: "fid",
    });
    assert.throws(() => parsePushRegistrationDeletionRequest({
      userId: "user-a",
      identifier: "too-short",
      registrationType: "fid",
    }));
    assert.throws(() => parsePushRegistrationDeletionRequest({
      userId: "user-a",
      identifier: fidA,
      registrationType: "fid",
      unexpected: true,
    }));
  });

  test("allows only the authenticated owner to request cleanup", () => {
    const input = {
      userId: "user-a",
      identifier: fidA,
      registrationType: "fid" as const,
    };

    assert.doesNotThrow(() => assertPushRegistrationOwner("user-a", input));
    assert.throws(
      () => assertPushRegistrationOwner("user-b", input),
      (error: unknown) => (
        typeof error === "object"
        && error !== null
        && "code" in error
        && error.code === "permission-denied"
      )
    );
  });

  test("sign-out before first FID delivery removes only the same installation", () => {
    const selected = registrationDocumentIDsForDeletion([
      {
        documentId: "current-fid",
        data: { token: fidA, registrationType: "fid" },
      },
      {
        documentId: "matching-legacy",
        data: { token: `${fidA}:legacy-token` },
      },
      {
        documentId: "matching-explicit-token",
        data: { token: `${fidA}:explicit-token`, registrationType: "token" },
      },
      {
        documentId: "other-device-token",
        data: { token: `${fidB}:other-device-token` },
      },
      {
        documentId: "other-device-fid",
        data: { token: fidB, registrationType: "fid" },
      },
      {
        documentId: "short-prefix-token",
        data: { token: "short-fid:legacy-token" },
      },
    ], {
      userId: "user-a",
      identifier: fidA,
      registrationType: "fid",
    });

    assert.deepEqual(selected, [
      "current-fid",
      "matching-legacy",
      "matching-explicit-token",
    ]);
  });

  test("legacy deletion matches only the exact token", () => {
    const selected = registrationDocumentIDsForDeletion([
      { documentId: "exact", data: { token: "legacy-token" } },
      { documentId: "other", data: { token: "legacy-token-other" } },
      { documentId: "fid", data: { token: fidA, registrationType: "fid" } },
    ], {
      userId: "user-a",
      identifier: "legacy-token",
      registrationType: "token",
    });

    assert.deepEqual(selected, ["exact"]);
  });
});
