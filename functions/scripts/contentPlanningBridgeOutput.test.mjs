import assert from "node:assert/strict";
import {Writable} from "node:stream";
import test from "node:test";

import {writeContentPlanningBridgeOutput} from "./contentPlanningBridgeOutput.mjs";

test("content planning bridge waits for JSON larger than the stdout pipe buffer", async () => {
  const chunks = [];
  const stream = new Writable({
    highWaterMark: 1_024,
    write(chunk, _encoding, callback) {
      setImmediate(() => {
        chunks.push(Buffer.from(chunk));
        callback();
      });
    },
  });
  const value = {items: Array.from({length: 2_000}, (_, index) => ({
    id: `item-${index}`,
    title: `Long content planning title ${index}`,
  }))};

  await writeContentPlanningBridgeOutput(value, stream);

  const output = Buffer.concat(chunks).toString("utf8");
  assert.ok(Buffer.byteLength(output) > 65_536);
  assert.deepEqual(JSON.parse(output), value);
});
