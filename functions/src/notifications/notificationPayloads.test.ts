import {strict as assert} from "node:assert";
import {test} from "node:test";

import {notificationRecipientEligibility} from "./notificationPayloads";

test("regular notifications require an active or warned recipient", () => {
  assert.deepEqual(notificationRecipientEligibility({
    userExists: true,
    accountStatus: "active",
    blockState: "active",
    notificationsEnabled: true,
  }), {
    canReceiveInbox: true,
    canReceivePush: true,
  });

  assert.deepEqual(notificationRecipientEligibility({
    userExists: true,
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
    accountStatus: "suspendedUntil",
    blockState: "suspendedUntil",
    notificationsEnabled: false,
    allowRestrictedPush: true,
  }).canReceivePush, false);
});
