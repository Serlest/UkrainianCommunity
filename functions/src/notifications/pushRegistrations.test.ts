import { strict as assert } from "node:assert";
import { describe, test } from "node:test";

import type { BatchResponse, SendResponse } from "firebase-admin/messaging";

import {
  isPermanentPushRegistrationFailure,
  parseStoredPushRegistration,
  pushRegistrationBatches,
  sendPushToRegistrationDocuments,
} from "./pushRegistrations";
import type {
  PushMulticastMessage,
  PushMulticastSender,
  PushRegistrationDocument,
  PushRegistrationKind,
} from "./pushRegistrations";

const fidA = "a123456789012345678901";
const fidB = "b123456789012345678901";
const notification = { notification: { title: "Compatibility test" } };

interface TestRegistrationDocument {
  snapshot: PushRegistrationDocument;
  readonly deleteCount: number;
}

function registrationDocument(
  id: string,
  identifier: string,
  kind?: PushRegistrationKind
): TestRegistrationDocument {
  let deleteCount = 0;
  const data: FirebaseFirestore.DocumentData = { token: identifier };
  if (kind !== undefined) {
    data.registrationType = kind;
  }

  return {
    snapshot: {
      id,
      data: () => data,
      ref: {
        delete: async () => {
          deleteCount += 1;
        },
      },
    },
    get deleteCount() {
      return deleteCount;
    },
  };
}

function response(code?: string): SendResponse {
  return code
    ? { success: false, error: { code } as SendResponse["error"] }
    : { success: true, messageId: "message-id" };
}

function batchResponse(responses: SendResponse[]): BatchResponse {
  return {
    responses,
    successCount: responses.filter((value) => value.success).length,
    failureCount: responses.filter((value) => !value.success).length,
  };
}

function recordingSender(
  responses: SendResponse[],
  messages: PushMulticastMessage[]
): PushMulticastSender {
  return async (message) => {
    messages.push(message);
    return batchResponse(responses);
  };
}

describe("push registration compatibility", () => {
  test("treats documents without a type as legacy tokens", () => {
    assert.deepEqual(
      parseStoredPushRegistration("legacy-doc", { token: "  legacy-token  " }),
      {
        documentId: "legacy-doc",
        identifier: "legacy-token",
        kind: "token",
      }
    );
  });

  test("decodes explicit FIDs and rejects malformed registrations", () => {
    assert.deepEqual(
      parseStoredPushRegistration("fid-doc", {
        token: fidA,
        registrationType: "fid",
      }),
      {
        documentId: "fid-doc",
        identifier: fidA,
        kind: "fid",
      }
    );
    assert.equal(parseStoredPushRegistration("empty", { token: "  " }), undefined);
    assert.equal(parseStoredPushRegistration("short-fid", {
      token: "too-short",
      registrationType: "fid",
    }), undefined);
    assert.equal(parseStoredPushRegistration("invalid-fid", {
      token: "a12345678901234567890!",
      registrationType: "fid",
    }), undefined);
    assert.equal(parseStoredPushRegistration("unknown", {
      token: "value",
      registrationType: "future-kind",
    }), undefined);
  });

  test("delivers a legacy-only registration through the token field", async () => {
    const legacy = registrationDocument("legacy", "legacy-registration-token");
    const messages: PushMulticastMessage[] = [];

    const result = await sendPushToRegistrationDocuments(
      [legacy.snapshot],
      notification,
      recordingSender([response()], messages)
    );

    assert.deepEqual(messages.map(({ tokens, fids }) => ({ tokens, fids })), [{
      tokens: ["legacy-registration-token"],
      fids: [],
    }]);
    assert.deepEqual(result, { targetCount: 1, successCount: 1, failureCount: 0 });
    assert.equal(legacy.deleteCount, 0);
  });

  test("delivers a FID-only registration through the FID field", async () => {
    const fid = registrationDocument("fid", fidA, "fid");
    const messages: PushMulticastMessage[] = [];

    await sendPushToRegistrationDocuments(
      [fid.snapshot],
      notification,
      recordingSender([response()], messages)
    );

    assert.deepEqual(messages.map(({ tokens, fids }) => ({ tokens, fids })), [{
      tokens: [],
      fids: [fidA],
    }]);
    assert.equal(fid.deleteCount, 0);
  });

  test("suppresses and cleans a same-installation legacy token after FID success", async () => {
    const legacy = registrationDocument("legacy", `${fidA}:legacy-token`);
    const fid = registrationDocument("fid", fidA, "fid");
    const messages: PushMulticastMessage[] = [];

    await sendPushToRegistrationDocuments(
      [legacy.snapshot, fid.snapshot],
      notification,
      recordingSender([response()], messages)
    );

    assert.deepEqual(messages.map(({ tokens, fids }) => ({ tokens, fids })), [{
      tokens: [],
      fids: [fidA],
    }]);
    assert.equal(legacy.deleteCount, 1);
    assert.equal(fid.deleteCount, 0);
  });

  test("retains the same-installation legacy fallback when FID delivery fails", async () => {
    const legacy = registrationDocument("legacy", `${fidA}:legacy-token`);
    const fid = registrationDocument("fid", fidA, "fid");

    await sendPushToRegistrationDocuments(
      [legacy.snapshot, fid.snapshot],
      notification,
      recordingSender([response("messaging/invalid-registration-token")], [])
    );

    assert.equal(legacy.deleteCount, 0);
    assert.equal(fid.deleteCount, 1);
  });

  test("does not suppress another device or a token matched by a malformed FID", async () => {
    const unrelatedToken = registrationDocument(
      "unrelated-token",
      `${fidB}:other-device-token`
    );
    const validFid = registrationDocument("valid-fid", fidA, "fid");
    const shortFidValue = "short-fid";
    const shortMatchedToken = registrationDocument(
      "short-token",
      `${shortFidValue}:must-not-be-suppressed`
    );
    const shortFid = registrationDocument("short-fid", shortFidValue, "fid");
    const messages: PushMulticastMessage[] = [];

    await sendPushToRegistrationDocuments(
      [
        unrelatedToken.snapshot,
        validFid.snapshot,
        shortMatchedToken.snapshot,
        shortFid.snapshot,
      ],
      notification,
      recordingSender([response(), response(), response()], messages)
    );

    assert.deepEqual(messages.map(({ tokens, fids }) => ({ tokens, fids })), [{
      tokens: [`${fidB}:other-device-token`, `${shortFidValue}:must-not-be-suppressed`],
      fids: [fidA],
    }]);
    assert.equal(unrelatedToken.deleteCount, 0);
    assert.equal(shortMatchedToken.deleteCount, 0);
    assert.equal(shortFid.deleteCount, 1);
  });

  test("maps mixed response order to permanent and superseded cleanup", async () => {
    const invalidToken = registrationDocument("invalid-token", "invalid-legacy-token");
    const supersededToken = registrationDocument("superseded-token", `${fidA}:legacy-token`);
    const transientFid = registrationDocument("transient-fid", fidB, "fid");
    const successfulFid = registrationDocument("successful-fid", fidA, "fid");
    const messages: PushMulticastMessage[] = [];

    await sendPushToRegistrationDocuments(
      [
        invalidToken.snapshot,
        supersededToken.snapshot,
        transientFid.snapshot,
        successfulFid.snapshot,
      ],
      notification,
      recordingSender([
        response("messaging/registration-token-not-registered"),
        response("messaging/server-unavailable"),
        response(),
      ], messages)
    );

    assert.deepEqual(messages.map(({ tokens, fids }) => ({ tokens, fids })), [{
      tokens: ["invalid-legacy-token"],
      fids: [fidB, fidA],
    }]);
    assert.equal(invalidToken.deleteCount, 1);
    assert.equal(supersededToken.deleteCount, 1);
    assert.equal(transientFid.deleteCount, 0);
    assert.equal(successfulFid.deleteCount, 0);
  });

  test("keeps mixed batches within the Admin SDK limit and deduplicates targets", () => {
    const registrations = Array.from({ length: 503 }, (_, index) => ({
      documentId: `doc-${index}`,
      identifier: `registration-${index}`,
      kind: index % 2 === 0 ? "fid" as const : "token" as const,
    }));
    registrations.push({
      documentId: "duplicate",
      identifier: "registration-0",
      kind: "fid",
    });

    const batches = pushRegistrationBatches(registrations);

    assert.equal(batches.length, 2);
    assert.equal(batches[0].tokens.length + batches[0].fids.length, 500);
    assert.equal(batches[1].tokens.length + batches[1].fids.length, 3);
  });

  test("only permanent identifier failures qualify for deletion", () => {
    assert.equal(isPermanentPushRegistrationFailure(
      response("messaging/invalid-registration-token")
    ), true);
    assert.equal(isPermanentPushRegistrationFailure(
      response("messaging/registration-token-not-registered")
    ), true);
    assert.equal(isPermanentPushRegistrationFailure(
      response("messaging/server-unavailable")
    ), false);
    assert.equal(isPermanentPushRegistrationFailure(response()), false);
  });
});
