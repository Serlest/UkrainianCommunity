import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  assertCanSendTestPush,
  localizedAlertKeys,
  shouldDeliverInboxNotificationPush,
} from "./inboxPushDelivery";

test("test push is restricted to the application owner", () => {
  assert.doesNotThrow(() => assertCanSendTestPush({
    uid: "owner",
    globalRole: "owner",
    accountStatus: "active",
    blockState: "active",
  }));
  assert.throws(
    () => assertCanSendTestPush({
      uid: "admin",
      globalRole: "admin",
      accountStatus: "active",
      blockState: "active",
    }),
    (error: unknown) => typeof error === "object"
      && error !== null
      && "code" in error
      && error.code === "permission-denied"
  );
  assert.throws(
    () => assertCanSendTestPush({
      uid: "user",
      globalRole: "user",
      accountStatus: "active",
      blockState: "active",
    }),
    (error: unknown) => typeof error === "object"
      && error !== null
      && "code" in error
      && error.code === "permission-denied"
  );
});

test("central push trigger owns every organization moderation notification", () => {
  for (const type of [
    "organizationRequestApproved",
    "organizationRequestNeedsRevision",
    "organizationRequestRejected",
  ] as const) {
    assert.equal(shouldDeliverInboxNotificationPush(type, {}), true);
  }
});

test("central trigger avoids duplicate pushes managed by the original writer", () => {
  assert.equal(shouldDeliverInboxNotificationPush(
    "organizationRequestApproved",
    {pushManagedByWriter: true}
  ), false);
  assert.equal(shouldDeliverInboxNotificationPush("feedbackReply", {}), false);
});

test("moderation pushes use localized notification keys", () => {
  assert.deepEqual(localizedAlertKeys("organizationRequestApproved", {}), {
    titleLocKey: "notifications.inbox.organization_approved.title",
    bodyLocKey: "notifications.inbox.generic.body",
  });
  assert.deepEqual(localizedAlertKeys("organizationRequestNeedsRevision", {}), {
    titleLocKey: "notifications.inbox.organization_needs_revision.title",
    bodyLocKey: "notifications.inbox.generic.body",
  });
  assert.deepEqual(localizedAlertKeys("organizationRequestRejected", {}), {
    titleLocKey: "notifications.inbox.organization_rejected.title",
    bodyLocKey: "notifications.inbox.generic.body",
  });
});
