import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  analyticsSchemaGateState,
  isAnalyticsSchemaReady,
  requireAnalyticsSchemaReady,
} from "./analyticsSchemaGate";
import type {Firestore} from "firebase-admin/firestore";

test("analytics schema gate accepts only an explicit completed v2 generation", () => {
  assert.equal(isAnalyticsSchemaReady(undefined), false);
  assert.equal(isAnalyticsSchemaReady({}), false);
  assert.equal(isAnalyticsSchemaReady({
    schemaVersion: 1,
    status: "complete",
    generation: "legacy",
    cutoverDay: "2026-08-24",
  }), false);
  assert.equal(isAnalyticsSchemaReady({
    schemaVersion: 2,
    status: "prepared",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  }), false);
  assert.equal(isAnalyticsSchemaReady({
    schemaVersion: 2,
    status: "finalizing",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  }), false);
  assert.equal(isAnalyticsSchemaReady({
    schemaVersion: 2,
    status: "complete",
    generation: "   ",
    cutoverDay: "2026-08-24",
  }), false);
  assert.equal(isAnalyticsSchemaReady({
    schemaVersion: 2,
    status: "complete",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  }), true);
});

test("analytics schema gate normalizes a valid state and rejects extra statuses", () => {
  assert.deepEqual(analyticsSchemaGateState({
    schemaVersion: 2,
    status: "complete",
    generation: "  cutover-2026-08-24  ",
    cutoverDay: "2026-08-24",
  }), {
    schemaVersion: 2,
    status: "complete",
    generation: "cutover-2026-08-24",
    cutoverDay: "2026-08-24",
  });
  assert.equal(analyticsSchemaGateState({
    schemaVersion: 2,
    status: "finalizing",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  })?.status, "finalizing");
  assert.equal(analyticsSchemaGateState({
    schemaVersion: 2,
    status: "bypassed",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  }), undefined);
});

test("prepared callable gate rejects retryably and completed gate accepts", async () => {
  await assert.rejects(
    requireAnalyticsSchemaReady(fakeFirestore({
      schemaVersion: 2,
      status: "prepared",
      generation: "cutover-1",
      cutoverDay: "2026-08-24",
    })),
    (error: unknown) => {
      assert.equal((error as {code?: string}).code, "unavailable");
      return true;
    }
  );
  await assert.doesNotReject(requireAnalyticsSchemaReady(fakeFirestore({
    schemaVersion: 2,
    status: "complete",
    generation: "cutover-1",
    cutoverDay: "2026-08-24",
  })));
});

function fakeFirestore(data: Record<string, unknown>): Firestore {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({data: () => data}),
      }),
    }),
  } as unknown as Firestore;
}
