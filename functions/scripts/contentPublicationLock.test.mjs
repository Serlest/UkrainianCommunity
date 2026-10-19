import test from "node:test";
import assert from "node:assert/strict";
import {acquireContentPublicationLock} from "./contentPublicationLock.mjs";

test("waits through transient contention and reports attempts", async () => {
  let calls = 0;
  const result = await acquireContentPublicationLock({
    invoke: async () => ++calls < 3 ? {acquired: false, reason: "busy"} : {acquired: true, owner: {runId: "r"}},
    wait: async () => {},
  });
  assert.equal(result.acquired, true);
  assert.equal(result.attempts, 3);
  assert.equal(calls, 3);
  assert.equal(result.maxWaitSeconds, 900);
});

test("does not retry non-contention failures", async () => {
  let calls = 0;
  const result = await acquireContentPublicationLock({
    invoke: async () => { calls += 1; return {acquired: false, reason: "invalid_owner"}; },
    wait: async () => { throw new Error("unexpected wait"); },
  });
  assert.equal(result.reason, "invalid_owner");
  assert.equal(calls, 1);
});

test("busy lock with zero wait returns a bounded timeout", async () => {
  const result = await acquireContentPublicationLock({
    invoke: async () => ({acquired: false, reason: "busy"}),
    maxWaitSeconds: 0,
  });
  assert.equal(result.acquired, false);
  assert.equal(result.reason, "busy_timeout");
  assert.equal(result.maxWaitSeconds, 0);
});
