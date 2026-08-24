import {strict as assert} from "node:assert";
import {test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {analyticsUserActivityCollection} from "../analytics/analyticsUserActivity";
import {db} from "../firebase/admin";
import {deleteExpiredAnalyticsActivityDocument} from "./dataRetention";

const hasFirestoreEmulator = process.env.FIRESTORE_EMULATOR_HOST !== undefined;

test("activity cleanup re-reads expiry and preserves a refreshed marker", {
  skip: !hasFirestoreEmulator,
}, async () => {
  const reference = db.collection(analyticsUserActivityCollection)
    .doc("retention-refresh-race");
  const cleanupNow = new Date("2026-08-24T04:00:00.000Z");

  await reference.set({
    lastActiveAt: Timestamp.fromDate(new Date("2026-06-01T00:00:00.000Z")),
    expiresAt: Timestamp.fromDate(new Date("2026-08-24T03:59:00.000Z")),
  });
  // Simulate an activity refresh after the cleanup query selected the document.
  await reference.set({
    lastActiveAt: Timestamp.fromDate(new Date("2026-08-24T03:59:30.000Z")),
    expiresAt: Timestamp.fromDate(new Date("2026-10-23T03:59:30.000Z")),
  }, {merge: true});

  assert.equal(
    await deleteExpiredAnalyticsActivityDocument(reference, cleanupNow),
    false
  );
  assert.equal((await reference.get()).exists, true);

  await reference.set({
    expiresAt: Timestamp.fromDate(new Date("2026-08-24T03:59:59.000Z")),
  }, {merge: true});
  assert.equal(
    await deleteExpiredAnalyticsActivityDocument(reference, cleanupNow),
    true
  );
  assert.equal((await reference.get()).exists, false);
});
