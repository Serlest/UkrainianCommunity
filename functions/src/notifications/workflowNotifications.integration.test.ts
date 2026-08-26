import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import type {BatchResponse, SendResponse} from "firebase-admin/messaging";
import {db} from "../firebase/admin";
import {notifyOrganizationSubmission, notifyContentComment, isOrganizationSubmission, organizationStaff, canReceiveScopedNotification} from "./workflowNotifications";
import {deliverPushDurably, notificationPushIsExpired, terminalTargetIds} from "./durablePushDelivery";
import {countsAsUnread, unreadNotificationCount} from "./notificationBadge";
import {shouldDeliverInboxNotificationPush, synchronizeNotificationBadge} from "./inboxPushDelivery";
import type {PushRegistrationDocument} from "./pushRegistrations";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const owner = "notification-audit-owner", admin = "notification-audit-admin", author = "notification-audit-author", staff = "notification-audit-staff";
const badgeUser = "notification-badge-test-user";
const orgId = "notification-audit-org";
const inbox = (id: string) => db.collection("users").doc(id).collection("notificationInbox");
before(async () => {
  if (!live) return;
  await cleanup();
  for (const [id, globalRole] of [[owner, "owner"], [admin, "admin"], [author, "user"], [staff, "user"]]) {
    await db.collection("users").doc(id).set({globalRole, accountStatus: "active", blockState: "active"});
  }
  await db.collection("organizations").doc(orgId).set({name: "Test org", submittedByUserId: author, moderationStatus: "pendingReview", ownerId: staff, adminIds: [], moderatorIds: []});
});
after(async () => {if (live) await cleanup();});
async function cleanup() {
  for (const id of [owner, admin, author, staff, badgeUser]) await db.recursiveDelete(db.collection("users").doc(id));
  await db.recursiveDelete(db.collection("organizations").doc(orgId));
}

test("only initial and resubmitted organizations produce submission alerts", () => {
  const pending = {moderationStatus: "pendingReview", submittedByUserId: author};
  assert.equal(isOrganizationSubmission(undefined, pending), true);
  assert.equal(isOrganizationSubmission({moderationStatus: "needsRevision"}, pending), true);
  assert.equal(isOrganizationSubmission(pending, {...pending, name: "edited"}), false);
  assert.equal(isOrganizationSubmission(undefined, {...pending, moderationStatus: "approved"}), false);
  assert.equal(isOrganizationSubmission(undefined, {moderationStatus: "pendingReview"}), false);
  assert.deepEqual(organizationStaff({ownerId: staff, adminIds: [staff, admin], moderatorIds: [admin, 7]}), [staff, admin]);
});
test("new central writers are handled once while old direct writers remain compatible", () => {
  for (const type of ["feedbackReply", "feedbackSubmitted", "organizationNewsPublished", "eventRegistrationConfirmed", "organizationRequestSubmitted", "commentAdded", "contentModerationChanged", "eventParticipationChanged"] as const) {
    assert.equal(shouldDeliverInboxNotificationPush(type, {pushDelivery: "central"}), true);
    assert.equal(shouldDeliverInboxNotificationPush(type, {pushManagedByWriter: true}), false);
  }
  assert.equal(shouldDeliverInboxNotificationPush("feedbackReply", {}), false);
});
test("delivery eligibility expires stale pushes and retains only terminal target receipts", () => {
  assert.equal(notificationPushIsExpired(0, 86_400_001), true);
  assert.equal(notificationPushIsExpired(100, 101), false);
  assert.deepEqual([...terminalTargetIds({a: "accepted", b: "retry", c: "permanentFailure"})], ["a", "c"]);
});

test("submission creates deduplicated owner/admin inbox entries independent of push opt-in", {skip: !live}, async () => {
  const data = (await db.collection("organizations").doc(orgId).get()).data()!;
  await notifyOrganizationSubmission("submission-1", orgId, undefined, data);
  await notifyOrganizationSubmission("submission-1", orgId, undefined, data);
  assert.equal((await inbox(owner).get()).size, 1);
  assert.equal((await inbox(admin).get()).size, 1);
  assert.equal((await inbox(author).get()).size, 0);
  assert.equal((await inbox(staff).get()).size, 0);
  await notifyOrganizationSubmission("submission-2", orgId, {moderationStatus: "needsRevision"}, data);
  assert.equal((await inbox(owner).get()).size, 2);
  await db.collection("users").doc(admin).update({globalRole: "user"});
  assert.equal(await canReceiveScopedNotification(admin, {recipientScope: "platformReviewers"}), false);
});

test("comments notify relevant staff only; exclude actor, personal blocks and private content", {skip: !live}, async () => {
  await db.collection("organizations").doc(orgId).update({moderationStatus: "approved"});
  await notifyContentComment("comment-1", "organizations", orgId, {authorId: author, moderationStatus: "approved"});
  await notifyContentComment("comment-1", "organizations", orgId, {authorId: author, moderationStatus: "approved"});
  assert.equal((await inbox(staff).get()).size, 1);
  await notifyContentComment("self-comment", "organizations", orgId, {authorId: staff, moderationStatus: "approved"});
  assert.equal((await inbox(staff).get()).size, 1);
  await db.collection("users").doc(staff).collection("blockedUsers").doc(author).set({});
  await notifyContentComment("blocked-comment", "organizations", orgId, {authorId: author, moderationStatus: "approved"});
  assert.equal((await inbox(staff).get()).size, 1);
  await db.collection("organizations").doc(orgId).update({moderationStatus: "pendingReview"});
  await notifyContentComment("private-comment", "organizations", orgId, {authorId: author, moderationStatus: "approved"});
  assert.equal((await inbox(staff).get()).size, 1);
});

function registration(id: string): PushRegistrationDocument {
  return {id, data: () => ({token: `token-${id}`}), ref: {delete: async () => {}}};
}
function batch(responses: SendResponse[]): BatchResponse {
  return {responses, successCount: responses.filter((x) => x.success).length, failureCount: responses.filter((x) => !x.success).length};
}

test("partial FCM failures retry only failed devices and duplicate events cannot resend accepted devices", {skip: !live}, async () => {
  const ref = inbox(owner).doc("delivery-test");
  await ref.set({createdAt: Timestamp.now(), isRead: false});
  const regs = [registration("one"), registration("two")];
  await assert.rejects(deliverPushDurably(ref, {notification: {title: "Test"}}, regs, async () => batch([
    {success: true, messageId: "one"},
    {success: false, error: {code: "messaging/server-unavailable"} as SendResponse["error"]},
  ])), /Transient push/);
  let calls = 0;
  const sender = async (message: {tokens: string[]}) => {
    calls++;
    assert.deepEqual(message.tokens, ["token-two"]);
    return batch([{success: true, messageId: "two"}]);
  };
  await deliverPushDurably(ref, {}, regs, sender);
  await deliverPushDurably(ref, {}, regs, sender);
  assert.equal(calls, 1);
  assert.equal((await ref.collection("privateDelivery").doc("push").get()).data()?.status, "complete");
});

test("deleted, read and expired inbox entries never generate a late push", {skip: !live}, async () => {
  let calls = 0;
  for (const [id, data] of [
    ["deleted", {createdAt: Timestamp.now(), deletedAt: Timestamp.now()}],
    ["read", {createdAt: Timestamp.now(), isRead: true}],
    ["expired", {createdAt: Timestamp.fromMillis(1)}],
  ] as const) {
    const ref = inbox(owner).doc(id); await ref.set(data);
    await deliverPushDurably(ref, {}, [registration("one")], async () => {calls++; return batch([]);});
  }
  assert.equal(calls, 0);
});


test("provider credential failures remain visible and never delete a valid registration", {skip: !live}, async () => {
  const ref = inbox(owner).doc("credential-test"); await ref.set({createdAt: Timestamp.now(), isRead: false});
  let deletes = 0, calls = 0;
  const doc: PushRegistrationDocument = {id: "apns", data: () => ({token: "valid-registration"}), ref: {delete: async () => {deletes++;}}};
  const sender = async () => {calls++; return batch([{success: false, error: {code: "messaging/third-party-auth-error"} as SendResponse["error"]}]);};
  await deliverPushDurably(ref, {}, [doc], sender);
  await deliverPushDurably(ref, {}, [doc], sender);
  const receipt = (await ref.collection("privateDelivery").doc("push").get()).data()!;
  assert.equal(receipt.status, "failedConfiguration");
  assert.equal(receipt.lastErrorCode, "messaging/third-party-auth-error");
  assert.equal(deletes, 0); assert.equal(calls, 1);
});

test("concurrent delivery events cannot send through the same active lease", {skip: !live}, async () => {
  const ref = inbox(owner).doc("concurrent-test"); await ref.set({createdAt: Timestamp.now(), isRead: false});
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>((resolve) => {entered = resolve;});
  const gate = new Promise<void>((resolve) => {release = resolve;});
  const first = deliverPushDurably(ref, {}, [registration("one")], async () => {
    entered(); await gate; return batch([{success: true}]);
  });
  await started;
  try {
    await assert.rejects(deliverPushDurably(ref, {}, [registration("one")], async () => {throw Error("Duplicate provider call");}), /lease is still active/);
  } finally {release();}
  await first;
});


test("badge eligibility matches unread inbox semantics", () => {
  assert.equal(countsAsUnread({isRead: false}), true);
  assert.equal(countsAsUnread({isRead: false, archivedAt: null, deletedAt: null}), true);
  assert.equal(countsAsUnread({isRead: true}), false);
  assert.equal(countsAsUnread({isRead: false, archivedAt: Timestamp.now()}), false);
  assert.equal(countsAsUnread({isRead: false, deletedAt: Timestamp.now()}), false);
});

test("APNs badge counts all unread records, preserves alert, retries with latest total and syncs zero without sound", {skip: !live}, async () => {
  const user = db.collection("users").doc(badgeUser);
  await user.set({accountStatus: "active", blockState: "active"});
  await user.collection("notificationPreferences").doc("settings").set({notificationsEnabled: true});
  await user.collection("notificationPushTokens").doc("one").set({token: "badge-test-token"});
  const batchWrite = db.batch();
  for (let i = 0; i < 65; i++) {
    batchWrite.set(inbox(badgeUser).doc(`unread-${i}`), {isRead: false, createdAt: Timestamp.now()});
  }
  batchWrite.set(inbox(badgeUser).doc("read"), {isRead: true});
  batchWrite.set(inbox(badgeUser).doc("archived"), {isRead: false, archivedAt: Timestamp.now()});
  batchWrite.set(inbox(badgeUser).doc("deleted"), {isRead: false, deletedAt: Timestamp.now()});
  await batchWrite.commit();
  assert.equal(await unreadNotificationCount(badgeUser), 65);
  const message = {apns: {payload: {aps: {sound: "default", alert: {locKey: "localized"}, badge: 999}}}};
  const ref = inbox(badgeUser).doc("unread-0");
  await assert.rejects(deliverPushDurably(ref, message, [registration("one")], async (sent) => {
    assert.equal(sent.apns?.payload?.aps.badge, 65);
    assert.equal(sent.apns?.payload?.aps.sound, "default");
    assert.deepEqual(sent.apns?.payload?.aps.alert, {locKey: "localized"});
    return batch([{success: false, error: {code: "messaging/server-unavailable"} as SendResponse["error"]}]);
  }), /Transient push/);
  await inbox(badgeUser).doc("unread-1").update({isRead: true});
  await deliverPushDurably(ref, message, [registration("one")], async (sent) => {
    assert.equal(sent.apns?.payload?.aps.badge, 64);
    return batch([{success: true}]);
  });
  const readAll = db.batch();
  for (const doc of (await inbox(badgeUser).get()).docs) readAll.update(doc.ref, {isRead: true});
  await readAll.commit();
  let calls = 0;
  await synchronizeNotificationBadge(badgeUser, async (sent) => {
    calls++;
    assert.deepEqual(sent.apns?.payload?.aps, {badge: 0});
    assert.equal(sent.notification, undefined);
    assert.equal(sent.apns?.headers?.["apns-push-type"], "alert");
    return batch([{success: true}]);
  });
  assert.equal(calls, 1);
  await user.collection("notificationPreferences").doc("settings").update({notificationsEnabled: false});
  await synchronizeNotificationBadge(badgeUser, async () => {throw Error("Must respect disabled notifications");});
});
