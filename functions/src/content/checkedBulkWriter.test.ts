import {strict as assert} from "node:assert";
import {test} from "node:test";
import {type BulkWriter, type DocumentReference} from "firebase-admin/firestore";
import {CheckedBulkWriter} from "../firebase/checkedBulkWriter";

test("draining a bulk writer cannot hide a rejected middle write", async () => {
  let calls = 0;
  let drained = false;
  const failure = new Error("server rejected deletion");
  const writer = new CheckedBulkWriter({
    delete: () => ++calls === 2 ? Promise.reject(failure) : Promise.resolve({}),
    close: async () => { drained = true; },
  } as unknown as BulkWriter);
  for (let i = 0; i < 3; i++) writer.delete({} as DocumentReference);
  await assert.rejects(writer.close(), (error: unknown) => error === failure);
  assert.equal(drained, true);
  assert.equal(calls, 3);
});

test("checked writes wait for a pending operation even if close resolves", async () => {
  let finish!: () => void;
  const operation = new Promise<void>(resolve => { finish = resolve; });
  const writer = new CheckedBulkWriter({delete: () => operation, close: async () => undefined} as unknown as BulkWriter);
  writer.delete({} as DocumentReference);
  let done = false;
  const closing = writer.close().then(() => { done = true; });
  await Promise.resolve();
  assert.equal(done, false);
  finish();
  await closing;
  assert.equal(done, true);
});
