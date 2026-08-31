import {strict as assert} from "node:assert";
import {after, test} from "node:test";

import {db} from "../firebase/admin";
import {deleteSystemLogRecord} from "./systemLogManagement";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const actorUserId = "system-log-delete-integration-owner";
const logIds = ["system-log-delete-atomic", "system-log-delete-concurrent"];

after(async () => {
  if (!shouldRun) return;
  await Promise.all(logIds.map((logId) => db.collection("systemLogs").doc(logId).delete()));
  const audit = await db.collection("auditLogs").where("targetUserId", "==", actorUserId).get();
  await Promise.all(audit.docs.map((document) => document.ref.delete()));
});

test("single system log deletion commits the record and audit atomically", {skip: !shouldRun}, async () => {
  const logId = logIds[0];
  await db.collection("systemLogs").doc(logId).set({summary: "test"});

  assert.deepEqual(await deleteSystemLogRecord(logId, actorUserId), {deletedCount: 1});
  assert.equal((await db.collection("systemLogs").doc(logId).get()).exists, false);

  const audit = await systemLogDeletionAudit(logId);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].data().actionType, "systemLogDeleted");
});

test("concurrent system log deletion produces one deletion and one audit", {skip: !shouldRun}, async () => {
  const logId = logIds[1];
  await db.collection("systemLogs").doc(logId).set({summary: "test"});

  const results = await Promise.allSettled([
    deleteSystemLogRecord(logId, actorUserId),
    deleteSystemLogRecord(logId, actorUserId),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  assert.equal(results.filter((result) => result.status === "rejected").length, 1);
  assert.equal((await db.collection("systemLogs").doc(logId).get()).exists, false);
  assert.equal((await systemLogDeletionAudit(logId)).length, 1);
});

async function systemLogDeletionAudit(logId: string) {
  const snapshot = await db.collection("auditLogs")
    .where("targetUserId", "==", actorUserId)
    .get();
  return snapshot.docs.filter((document) =>
    document.data().previousValue?.systemLogId === logId
  );
}
