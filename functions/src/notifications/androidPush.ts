import {createHash} from "node:crypto";
import type {BaseMessage, AndroidNotification} from "firebase-admin/messaging";

export const androidPushChannelId = "uac_updates";
export const androidPushIcon = "ic_stat_uac";
export const androidPushMaximumTtlMs = 3_600_000;

/** Resource names are shared with the Android UK/DE notification strings. */
export function androidPushResourceKey(value: unknown): string | undefined {
  return typeof value === "string" && /^[a-z][a-z0-9_.]{0,159}$/.test(value)
    ? `uac_${value.replaceAll(".", "_")}` : undefined;
}

/** Build only the Android envelope. The caller keeps the iOS message untouched.
 * In particular, common literal title/body would override Android loc keys. */
export function messageForAndroid(message: BaseMessage, nowMs = Date.now()): BaseMessage {
  const aps = message.apns?.payload?.aps;
  const alert = aps?.alert;
  const badge = typeof aps?.badge === "number" && Number.isSafeInteger(aps.badge) && aps.badge >= 0
    ? aps.badge : undefined;
  const isBadgeSync = !message.notification && !alert && badge !== undefined;
  if (isBadgeSync) {
    return {
      data: {...message.data, type: "inboxSync", unreadCount: String(badge)},
      android: {priority: "normal", ttl: 0, collapseKey: "uac-inbox-sync"},
    };
  }

  const localized = typeof alert === "object" && alert !== null ? alert : undefined;
  const titleLocKey = androidPushResourceKey(localized?.titleLocKey);
  const bodyLocKey = androidPushResourceKey(localized?.locKey);
  const notification: AndroidNotification = {
    channelId: androidPushChannelId,
    icon: androidPushIcon,
    visibility: "private",
    defaultSound: true,
    ...(badge === undefined ? {} : {notificationCount: badge}),
  };
  // Use literal fallback only for the individual field without a valid loc key.
  if (titleLocKey) {
    notification.titleLocKey = titleLocKey;
    if (Array.isArray(localized?.titleLocArgs)) notification.titleLocArgs = localized.titleLocArgs;
  } else if (message.notification?.title) notification.title = message.notification.title;
  if (bodyLocKey) {
    notification.bodyLocKey = bodyLocKey;
    if (Array.isArray(localized?.locArgs)) notification.bodyLocArgs = localized.locArgs;
  } else if (message.notification?.body) notification.body = message.notification.body;

  const identity = message.apns?.headers?.["apns-collapse-id"] ?? message.data?.notificationId;
  if (identity) notification.tag = createHash("sha256").update(identity).digest("hex");
  const expirationSeconds = Number(message.apns?.headers?.["apns-expiration"]);
  const ttl = Number.isFinite(expirationSeconds) && expirationSeconds >= 0
    ? Math.min(androidPushMaximumTtlMs, Math.max(0, expirationSeconds * 1_000 - nowMs))
    : androidPushMaximumTtlMs;
  return {
    ...(message.data ? {data: message.data} : {}),
    android: {
      priority: "high",
      ttl,
      // Do not invent a shared collapse key for distinct inbox events. FCM
      // notification messages are inherently collapsible; full inbox refresh,
      // not this notification envelope, must recover every offline notice.
      notification,
    },
  };
}
