import {strict as assert} from "node:assert";
import {test} from "node:test";
import type {BaseMessage} from "firebase-admin/messaging";
import {androidPushResourceKey, messageForAndroid} from "./androidPush";
import {sendPushToRegistrationDocuments, type PushMulticastMessage} from "./pushRegistrations";

const now = 1_800_000_000_000;
const source: BaseMessage = {
  notification: {title: "Literal fallback", body: "Fallback body"},
  data: {notificationId: "synthetic-one", actionType: "openEvent", routeTargetId: "synthetic-event"},
  apns: {headers: {"apns-expiration": String(now / 1_000 + 1_800), "apns-collapse-id": "synthetic-one"},
    payload: {aps: {badge: 4, sound: "default", alert: {
      titleLocKey: "notifications.push.feedback_submitted.title",
      locKey: "notifications.push.feedback_submitted.body", locArgs: ["Synthetic person"],
    }}}},
};

test("Android envelope uses native localization, private channel/icon, current badge, bounded TTL and stable tag", () => {
  const sent = messageForAndroid(source, now);
  assert.equal(sent.notification, undefined);
  assert.equal(sent.apns, undefined);
  assert.deepEqual(sent.data, source.data);
  assert.equal(sent.android?.notification?.titleLocKey, "uac_notifications_push_feedback_submitted_title");
  assert.equal(sent.android?.notification?.bodyLocKey, "uac_notifications_push_feedback_submitted_body");
  assert.deepEqual(sent.android?.notification?.bodyLocArgs, ["Synthetic person"]);
  assert.equal(sent.android?.notification?.title, undefined);
  assert.equal(sent.android?.notification?.body, undefined);
  assert.equal(sent.android?.notification?.notificationCount, 4);
  assert.equal(sent.android?.notification?.channelId, "uac_updates");
  assert.equal(sent.android?.notification?.icon, "ic_stat_uac");
  assert.equal(sent.android?.notification?.visibility, "private");
  assert.equal(sent.android?.ttl, 1_800_000);
  assert.equal(sent.android?.priority, "high");
  assert.equal(sent.android?.collapseKey, undefined);
  assert.equal(sent.android?.notification?.tag?.length, 64);
  assert.equal(messageForAndroid(source, now + 10).android?.notification?.tag, sent.android?.notification?.tag);
});

test("invalid/missing localization falls back without turning arbitrary strings into Android resource keys", () => {
  assert.equal(androidPushResourceKey("unsafe/target"), undefined);
  assert.equal(androidPushResourceKey(""), undefined);
  assert.equal(androidPushResourceKey(1), undefined);
  const sent = messageForAndroid({notification: {title: "Fallback", body: "Body"}}, now);
  assert.equal(sent.android?.notification?.title, "Fallback");
  assert.equal(sent.android?.notification?.body, "Body");
  assert.equal(sent.android?.ttl, 3_600_000);
});

test("expired APNs notification is not granted a new Android lifetime; TTL cannot exceed one hour", () => {
  for (const [expiration, expected] of [["0", 0], [String(now / 1_000 - 1), 0],
    [String(now / 1_000 + 90_000), 3_600_000]] as const) {
    assert.equal(messageForAndroid({...source, apns: {headers: {"apns-expiration": expiration}}}, now).android?.ttl, expected);
  }
});

test("read/delete badge sync is data-only, normal priority, zero TTL and never a visible Android alert", () => {
  const sent = messageForAndroid({apns: {payload: {aps: {badge: 0}}}}, now);
  assert.deepEqual(sent, {data: {type: "inboxSync", unreadCount: "0"},
    android: {priority: "normal", ttl: 0, collapseKey: "uac-inbox-sync"}});
});

test("mixed iOS/Android registrations split envelopes without mutating APNs or target order semantics", async () => {
  const original = JSON.parse(JSON.stringify(source));
  const messages: PushMulticastMessage[] = [];
  const registrations = ["ios", "android"].map((platform) => ({
    id: `${platform}-registration`, data: () => ({token: `${platform}-token`, platform, registrationType: "token"}),
    ref: {delete: async () => {throw new Error("Valid registration must not be deleted");}},
  }));
  const observed: string[] = [];
  const result = await sendPushToRegistrationDocuments(registrations, source, async (message) => {
    messages.push(message);
    return {successCount: 1, failureCount: 0, responses: [{success: true}]};
  }, async (ids) => {observed.push(...ids);});
  assert.deepEqual(result, {targetCount: 2, successCount: 2, failureCount: 0});
  assert.deepEqual(messages.find((message) => message.tokens.includes("ios-token")), {
    ...source, tokens: ["ios-token"], fids: [],
  });
  assert.equal(messages.find((message) => message.tokens.includes("android-token"))?.notification, undefined);
  assert.deepEqual(observed.sort(), ["android-registration", "ios-registration"]);
  assert.deepEqual(source, original);
});

test("distinct pending notices retain distinct display tags while repeat delivery reuses the same tag", () => {
  const tags = Array.from({length: 6}, (_, index) => messageForAndroid({
    ...source, apns: {...source.apns, headers: {"apns-collapse-id": `notice-${index}`}},
  }, now).android?.notification?.tag);
  assert.equal(new Set(tags).size, 6);
  assert.equal(messageForAndroid({...source, apns: {...source.apns,
    headers: {"apns-collapse-id": "notice-0"}}}, now).android?.notification?.tag, tags[0]);
});

test("unknown platform is not treated as a supported device and is never deleted speculatively", async () => {
  const result = await sendPushToRegistrationDocuments([{id: "unknown", data: () => ({token: "valid", platform: "web"}),
    ref: {delete: async () => {throw new Error("Do not delete unknown-platform data");}},
  }, {id: "unknown-fid", data: () => ({token: "short", registrationType: "fid", platform: "future"}),
    ref: {delete: async () => {throw new Error("Do not delete unknown-platform data");}},
  }], source, async () => {throw new Error("Do not send to an unsupported platform");});
  assert.deepEqual(result, {targetCount: 0, successCount: 0, failureCount: 0});
});
