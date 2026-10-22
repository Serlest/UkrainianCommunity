import {strict as assert} from "node:assert";
import {after, test} from "node:test";

import {db} from "../firebase/admin";
import {writeClientDiagnostic} from "./clientDiagnostics";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {clearSystemLogs, deleteSystemLog, deleteSystemLogRecord} from "./systemLogManagement";

const shouldRun = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const actorUserId = "system-log-delete-integration-owner";
const logIds = ["system-log-delete-atomic", "system-log-delete-concurrent"];
const protectedOwnerId = "system-log-protected-owner";

function ownerRequest(data: unknown, totp: boolean) {
  return {
    data,
    auth: {
      uid: protectedOwnerId,
      token: {
        email_verified: true,
        firebase: {sign_in_second_factor: totp ? "totp" : undefined},
      },
    },
  } as any;
}

after(async () => {
  if (!shouldRun) return;
  await Promise.all(logIds.map((logId) => db.collection("systemLogs").doc(logId).delete()));
  const audit = await db.collection("auditLogs").where("targetUserId", "==", actorUserId).get();
  await Promise.all(audit.docs.map((document) => document.ref.delete()));
  await db.doc(`users/${protectedOwnerId}`).delete();
});

test("protected owner needs TOTP before deleting or clearing system logs", {skip: !shouldRun}, async () => {
  const log = db.collection("systemLogs").doc("system-log-mfa-protected");
  try {
    await db.doc(`users/${protectedOwnerId}`).set({globalRole: "owner", accountStatus: "active", requiresMultiFactorAuth: true});
    await seedCurrentLegalForIntegration(protectedOwnerId);
    await log.set({summary: "protected"});

    await assert.rejects(deleteSystemLog.run(ownerRequest({logId: log.id}, false)), {code: "failed-precondition"});
    await assert.rejects(clearSystemLogs.run(ownerRequest({}, false)), {code: "failed-precondition"});
    assert.equal((await log.get()).exists, true);

    assert.deepEqual(await deleteSystemLog.run(ownerRequest({logId: log.id}, true)), {deletedCount: 1});
    assert.equal((await log.get()).exists, false);
  } finally {
    await log.delete();
  }
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

test("late diagnostic cannot be attributed to a newly signed-in account", {skip: !shouldRun}, async () => {
  const uid = "diagnostic-identity-integration-user";
  const profile = db.doc(`users/${uid}`);
  const payload = {eventType: "technicalError", severity: "warning", targetType: "notification", summary: "Fixture diagnostic", metadata: {}};
  const request = (principalId?: string) => ({auth: {uid, token: {email_verified: true}}, data: {...payload, ...(principalId === undefined ? {} : {principalId})}} as any);
  const logs: string[] = [];
  try {
    await profile.set({globalRole: "user", accountStatus: "active"});
    await seedCurrentLegalForIntegration(uid);
    await assert.rejects(writeClientDiagnostic.run(request("previous-account")), {code: "failed-precondition"});
    for (const principalId of [undefined, uid]) {
      const created = await writeClientDiagnostic.run(request(principalId));
      logs.push(created.id);
      const stored = await db.doc(`systemLogs/${created.id}`).get();
      assert.equal(stored.get("actorUserId"), uid);
      assert.equal(stored.get("principalId"), undefined);
    }
  } finally {
    await Promise.all(logs.map(id => db.doc(`systemLogs/${id}`).delete()));
    await profile.delete();
    await db.doc(`systemLogDiagnosticRateLimits/${uid}`).delete();
  }
});
