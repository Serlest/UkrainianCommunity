import test from "node:test";
import assert from "node:assert/strict";
import {acquirePublicationLock} from "./newsAcquirePublicationLock.mjs";

test("a short foreign write can finish before the same pass acquires both locks", async () => {
  let calls = 0; const waits = [];
  const result = await acquirePublicationLock("runtime", "run", "thread", {
    invoke: async () => ++calls < 2 ? {acquired: false, reason: "busy"} : {acquired: true},
    wait: async (ms) => waits.push(ms),
  });
  assert.equal(result.acquired, true);
  assert.equal(result.attempts, 2);
  assert.deepEqual(waits, [15_000]);
});
test("lock contention is bounded and technical errors are never retried", async () => {
  let calls = 0;
  const result = await acquirePublicationLock("runtime", "run", "thread", {
    invoke: async () => {calls++; return {acquired: false, reason: "busy"};}, wait: async () => {},
  });
  assert.equal(calls, 3); assert.equal(result.acquired, false);
  await assert.rejects(acquirePublicationLock("runtime", "run", "thread", {
    invoke: async () => {throw new Error("invalid arguments");}, wait: async () => assert.fail("must not wait"),
  }), /invalid arguments/);
});
