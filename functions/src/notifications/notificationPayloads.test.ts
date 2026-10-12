import {strict as assert} from "node:assert";
import {mock, test} from "node:test";

import {adminAuth, db} from "../firebase/admin";
import {notificationRecipientEligibility, resolveNotificationRecipients} from "./notificationPayloads";

test("regular notifications require an active or warned recipient", () => {
  assert.deepEqual(notificationRecipientEligibility({
    userExists: true,
    emailVerified: true,
    accountStatus: "active",
    blockState: "active",
    notificationsEnabled: true,
  }), {
    canReceiveInbox: true,
    canReceivePush: true,
  });

  assert.deepEqual(notificationRecipientEligibility({
    userExists: true,
    emailVerified: true,
    accountStatus: "bannedPermanent",
    blockState: "bannedPermanent",
    notificationsEnabled: true,
  }), {
    canReceiveInbox: false,
    canReceivePush: false,
  });
});

test("account restriction push reaches a restricted existing user when enabled", () => {
  assert.deepEqual(notificationRecipientEligibility({
    userExists: true,
    emailVerified: true,
    accountStatus: "suspendedUntil",
    blockState: "suspendedUntil",
    notificationsEnabled: true,
    allowRestrictedPush: true,
  }), {
    canReceiveInbox: false,
    canReceivePush: true,
  });

  assert.equal(notificationRecipientEligibility({
    userExists: true,
    emailVerified: true,
    accountStatus: "suspendedUntil",
    blockState: "suspendedUntil",
    notificationsEnabled: false,
    allowRestrictedPush: true,
  }).canReceivePush, false);
});

test("an unverified account receives neither inbox nor push notifications", () => {
  assert.deepEqual(notificationRecipientEligibility({
    userExists: true, emailVerified: false, accountStatus: "active", blockState: "active",
    notificationsEnabled: true, allowRestrictedPush: true,
  }), {canReceiveInbox: false, canReceivePush: false});
});

test("recipient resolution rejects an unverified Auth identity before Firestore access", async () => {
  const auth = mock.method(adminAuth, "getUsers", async () => ({users: [{uid: "unverified", emailVerified: false}], notFound: []}) as never);
  const firestore = mock.method(db, "collection", () => { throw new Error("unexpected profile read"); });
  try {
    assert.deepEqual(await resolveNotificationRecipients(["unverified"]), {
      inboxRecipientIds: [], pushRecipientIds: [],
    });
    assert.equal(auth.mock.calls.length, 1);
    assert.equal(firestore.mock.calls.length, 0);
  } finally { auth.mock.restore(); firestore.mock.restore(); }
});
