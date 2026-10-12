import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {restoreExpiredTemporarySuspensionsOnce} from "./accountStatusManagement";

test("concurrent suspension restoration creates one audit record and one notification", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const userId = `scheduler-restore-${randomUUID()}`;
  const user = db.doc(`users/${userId}`);
  const now = Timestamp.now();
  await user.set({
    globalRole: "user",
    accountStatus: "suspendedUntil",
    blockState: "suspendedUntil",
    banExpiresAt: Timestamp.fromMillis(now.toMillis() - 1_000),
    warningCount: 1,
    isBlocked: true,
  });

  try {
    const results = await Promise.all([
      restoreExpiredTemporarySuspensionsOnce(now),
      restoreExpiredTemporarySuspensionsOnce(now),
    ]);
    assert.deepEqual(results.sort(), [0, 1]);
    assert.equal(await restoreExpiredTemporarySuspensionsOnce(now), 0);
    assert.equal((await user.get()).get("accountStatus"), "active");

    const [audit, notifications] = await Promise.all([
      db.collection("auditLogs").where("targetUserId", "==", userId).get(),
      user.collection("notificationInbox").get(),
    ]);
    assert.equal(audit.size, 1);
    assert.equal(notifications.size, 1);
  } finally {
    await db.recursiveDelete(user);
    const audit = await db.collection("auditLogs").where("targetUserId", "==", userId).get();
    await Promise.all(audit.docs.map((document) => document.ref.delete()));
  }
});
