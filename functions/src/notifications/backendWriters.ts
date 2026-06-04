import { randomUUID } from "node:crypto";

import { Timestamp } from "firebase-admin/firestore";
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import { assertOwner, getUserPermissions } from "../permissions/userPermissions";
import {
  type NotificationActionType,
  type NotificationSeverity,
  writeUserNotification,
} from "./notificationPayloads";

type SystemAnnouncementTargetMode = "all" | "role" | "userIds";

interface SystemAnnouncementRequest {
  title: string;
  message: string;
  severity: NotificationSeverity;
  requiresPopup: boolean;
  targetMode: SystemAnnouncementTargetMode;
  targetUserIds: string[];
  role?: string;
  actionType: NotificationActionType;
  actionTargetId?: string;
  url?: string;
}

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const maxFanoutRecipients = 200;
const soonWindowMs = 24 * 60 * 60 * 1000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(data: Record<string, unknown>, field: string): string {
  const value = data[field];
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return trimmedValue;
}

function optionalString(data: Record<string, unknown>, field: string): string | undefined {
  const value = data[field];
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : undefined;
}

function stringField(data: Record<string, unknown> | undefined, field: string): string | undefined {
  const value = data?.[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function timestampField(
  data: Record<string, unknown> | undefined,
  field: string
): Timestamp | undefined {
  const value = data?.[field];
  return value instanceof Timestamp ? value : undefined;
}

function boolField(data: Record<string, unknown> | undefined, field: string): boolean {
  return data?.[field] === true;
}

function hasMeaningfulEventChange(
  before: Record<string, unknown>,
  after: Record<string, unknown>
): boolean {
  return [
    "startDate",
    "endDate",
    "venue",
    "address",
    "locationNote",
    "latitude",
    "longitude",
    "city",
    "moderationStatus",
    "registrationState",
  ].some((field) => String(before[field]) !== String(after[field]));
}

function eventTitle(data: Record<string, unknown> | undefined): string {
  return stringField(data, "title") ?? "Event";
}

function isSoon(data: Record<string, unknown> | undefined): boolean {
  const startDate = timestampField(data, "startDate")?.toDate();
  if (!startDate) {
    return false;
  }

  const timeUntilStart = startDate.getTime() - Date.now();
  return timeUntilStart >= 0 && timeUntilStart <= soonWindowMs;
}

async function registeredUserIds(eventId: string): Promise<string[]> {
  const snapshot = await db.collection("registrations")
    .where("eventId", "==", eventId)
    .get();

  return Array.from(new Set(snapshot.docs
    .map((document) => stringField(document.data(), "userId"))
    .filter((userId): userId is string => userId !== undefined)));
}

async function writeEventNotifications(
  eventId: string,
  userIds: string[],
  input: {
    type: "eventUpdated" | "eventCancelled";
    title: string;
    message: string;
    severity: NotificationSeverity;
    requiresPopup: boolean;
    dedupeKeyPart: string;
    metadata: Record<string, unknown>;
  }
): Promise<void> {
  await Promise.all(userIds.map((userId) => writeUserNotification({
    targetUserId: userId,
    type: input.type,
    title: input.title,
    message: input.message,
    severity: input.severity,
    actionType: "openEvent",
    actionTargetId: eventId,
    requiresPopup: input.requiresPopup,
    sourceType: "event",
    sourceId: eventId,
    metadata: {
      ...input.metadata,
      eventId,
    },
    dedupeKey: `${input.type}:${eventId}:${input.dedupeKeyPart}`,
  })));
}

export const notifyFeedbackReplyOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "feedback/{feedbackId}/messages/{messageId}" },
  async (event) => {
    const message = event.data?.data();
    if (!message || stringField(message, "senderRole") !== "owner") {
      return;
    }

    if (boolField(message, "isSystem")) {
      return;
    }

    const feedbackId = event.params.feedbackId;
    const feedbackSnapshot = await db.collection("feedback").doc(feedbackId).get();
    const feedback = feedbackSnapshot.data();
    const targetUserId = stringField(feedback, "userId");
    if (!targetUserId) {
      return;
    }

    const text = stringField(message, "text") ?? "Support replied to your message.";
    const subject = stringField(feedback, "subject");
    const createdAt = timestampField(message, "createdAt")?.toMillis() ?? Date.now();

    await writeUserNotification({
      targetUserId,
      type: "feedbackReply",
      title: "Support replied",
      message: text,
      severity: "info",
      actionType: "openFeedback",
      actionTargetId: feedbackId,
      requiresPopup: false,
      actorUserId: stringField(message, "senderId"),
      actorDisplayName: stringField(message, "senderDisplayName"),
      sourceType: "feedback",
      sourceId: feedbackId,
      metadata: {
        feedbackId,
        subject: subject ?? null,
        messagePreview: text.slice(0, 160),
      },
      dedupeKey: `feedbackReply:${feedbackId}:${event.params.messageId}:${createdAt}`,
    });
  }
);

export const notifyEventUpdatedOnUpdate = onDocumentUpdated(
  { ...triggerOptions, document: "events/{eventId}" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || !hasMeaningfulEventChange(before, after)) {
      return;
    }

    const eventId = event.params.eventId;
    const userIds = await registeredUserIds(eventId);
    if (userIds.length === 0) {
      return;
    }

    const updatedAt = timestampField(after, "updatedAt")?.toMillis() ?? Date.now();
    await writeEventNotifications(eventId, userIds, {
      type: "eventUpdated",
      title: "Event updated",
      message: `${eventTitle(after)} was updated.`,
      severity: "info",
      requiresPopup: false,
      dedupeKeyPart: String(updatedAt),
      metadata: {
        eventTitle: eventTitle(after),
        changedAt: updatedAt,
      },
    });
  }
);

export const notifyEventCancelledOnDelete = onDocumentDeleted(
  { ...triggerOptions, document: "events/{eventId}" },
  async (event) => {
    const deletedEvent = event.data?.data();
    const eventId = event.params.eventId;
    const userIds = await registeredUserIds(eventId);
    if (userIds.length === 0) {
      return;
    }

    const cancelledAt = Date.now();
    const requiresPopup = isSoon(deletedEvent);
    await writeEventNotifications(eventId, userIds, {
      type: "eventCancelled",
      title: "Event cancelled",
      message: `${eventTitle(deletedEvent)} was cancelled.`,
      severity: requiresPopup ? "critical" : "warning",
      requiresPopup,
      dedupeKeyPart: String(cancelledAt),
      metadata: {
        eventTitle: eventTitle(deletedEvent),
        cancelledAt,
      },
    });
  }
);

export const createSystemAnnouncement = onCall(
  callableOptions,
  async (request): Promise<{ announcementId: string; recipientCount: number }> => {
    const auth = requireAuth(request);
    const actorPermissions = await getUserPermissions(auth.uid);
    assertOwner(actorPermissions);

    const announcementRequest = parseSystemAnnouncementRequest(request.data);
    const targetUserIds = await resolveSystemAnnouncementRecipients(announcementRequest);
    const announcementId = randomUUID();

    await db.collection("systemAnnouncements").doc(announcementId).set({
      id: announcementId,
      title: announcementRequest.title,
      message: announcementRequest.message,
      severity: announcementRequest.severity,
      requiresPopup: announcementRequest.requiresPopup,
      targetMode: announcementRequest.targetMode,
      targetUserIds,
      role: announcementRequest.role ?? null,
      actionType: announcementRequest.actionType,
      actionTargetId: announcementRequest.actionTargetId ?? null,
      url: announcementRequest.url ?? null,
      createdAt: Timestamp.now(),
      createdBy: auth.uid,
    });

    await Promise.all(targetUserIds.map((userId) => writeUserNotification({
      targetUserId: userId,
      type: "systemAnnouncement",
      title: announcementRequest.title,
      message: announcementRequest.message,
      severity: announcementRequest.severity,
      actionType: announcementRequest.actionType,
      actionTargetId: announcementRequest.actionTargetId ?? announcementRequest.url,
      requiresPopup: announcementRequest.requiresPopup,
      actorUserId: auth.uid,
      sourceType: "system",
      sourceId: announcementId,
      metadata: {
        announcementId,
        url: announcementRequest.url ?? null,
      },
      dedupeKey: `systemAnnouncement:${announcementId}:${userId}`,
    })));

    return {
      announcementId,
      recipientCount: targetUserIds.length,
    };
  }
);

function parseSystemAnnouncementRequest(data: unknown): SystemAnnouncementRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const severity = requiredString(data, "severity") as NotificationSeverity;
  if (!["info", "success", "warning", "critical"].includes(severity)) {
    throw new HttpsError("invalid-argument", "severity is invalid.");
  }

  const actionType = (optionalString(data, "actionType") ?? "none") as NotificationActionType;
  if (![
    "none",
    "openURL",
    "openProfile",
    "openLegalDocuments",
  ].includes(actionType)) {
    throw new HttpsError("invalid-argument", "actionType is not supported.");
  }

  const requiresPopup = data.requiresPopup === true;
  if (requiresPopup && severity !== "critical") {
    throw new HttpsError(
      "invalid-argument",
      "requiresPopup is allowed only for critical severity."
    );
  }

  const targetMode = requiredString(data, "targetMode") as SystemAnnouncementTargetMode;
  if (!["all", "role", "userIds"].includes(targetMode)) {
    throw new HttpsError("invalid-argument", "targetMode is invalid.");
  }

  const targetUserIds = Array.isArray(data.targetUserIds)
    ? data.targetUserIds.filter((userId): userId is string => typeof userId === "string")
    : [];

  return {
    title: requiredString(data, "title"),
    message: requiredString(data, "message"),
    severity,
    requiresPopup,
    targetMode,
    targetUserIds,
    role: optionalString(data, "role"),
    actionType,
    actionTargetId: optionalString(data, "actionTargetId"),
    url: optionalString(data, "url"),
  };
}

async function resolveSystemAnnouncementRecipients(
  request: SystemAnnouncementRequest
): Promise<string[]> {
  switch (request.targetMode) {
    case "userIds":
      return limitedUniqueUserIds(request.targetUserIds);
    case "role":
      if (!request.role) {
        throw new HttpsError("invalid-argument", "role is required for role targeting.");
      }
      return fetchUsersByRole(request.role);
    case "all":
      return fetchAllUsers();
  }
}

function limitedUniqueUserIds(userIds: string[]): string[] {
  const uniqueUserIds = Array.from(new Set(userIds.map((userId) => userId.trim())))
    .filter((userId) => userId.length > 0);
  if (uniqueUserIds.length > maxFanoutRecipients) {
    throw new HttpsError("invalid-argument", `Fanout is limited to ${maxFanoutRecipients} users.`);
  }

  return uniqueUserIds;
}

async function fetchAllUsers(): Promise<string[]> {
  const snapshot = await db.collection("users")
    .limit(maxFanoutRecipients)
    .get();
  return snapshot.docs.map((document) => document.id);
}

async function fetchUsersByRole(role: string): Promise<string[]> {
  const snapshot = await db.collection("users")
    .where("globalRole", "==", role)
    .limit(maxFanoutRecipients)
    .get();
  return snapshot.docs.map((document) => document.id);
}
