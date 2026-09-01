import {strict as assert} from "node:assert";
import {after, beforeEach, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {cleanupExpiredDeletedNotifications} from "./dataRetention";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const userId = "deleted-notification-retention-user";
const inbox = db.collection("users").doc(userId).collection("notificationInbox");
const now = new Date("2026-09-01T04:00:00.000Z");
const day = 24 * 60 * 60 * 1_000;

beforeEach(async () => {
  if (!live) return;
  await cleanup();
  await Promise.all([
    inbox.doc("expired").set({
      deletedAt: Timestamp.fromMillis(now.getTime() - 31 * day),
    }),
    inbox.doc("boundary").set({
      deletedAt: Timestamp.fromMillis(now.getTime() - 30 * day),
    }),
    inbox.doc("recent").set({
      deletedAt: Timestamp.fromMillis(now.getTime() - 29 * day),
    }),
    inbox.doc("active").set({deletedAt: null}),
    inbox.doc("invalid").set({deletedAt: "2020-01-01T00:00:00.000Z"}),
  ]);
});

after(async () => {
  if (live) await cleanup();
});

test("deleted inbox retention removes only timestamped records at least 30 days old", {
  skip: !live,
}, async () => {
  assert.equal(await cleanupExpiredDeletedNotifications(now), 2);

  const [expired, boundary, recent, active, invalid] = await Promise.all([
    inbox.doc("expired").get(),
    inbox.doc("boundary").get(),
    inbox.doc("recent").get(),
    inbox.doc("active").get(),
    inbox.doc("invalid").get(),
  ]);
  assert.equal(expired.exists, false);
  assert.equal(boundary.exists, false);
  assert.equal(recent.exists, true);
  assert.equal(active.exists, true);
  assert.equal(invalid.exists, true);

  assert.equal(await cleanupExpiredDeletedNotifications(now), 0);
});

async function cleanup(): Promise<void> {
  await db.recursiveDelete(db.collection("users").doc(userId));
}
