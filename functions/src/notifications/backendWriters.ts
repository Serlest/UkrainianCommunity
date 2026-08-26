import { randomUUID } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  onDocumentDeleted,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireVerifiedActiveUser } from "../auth/context";
import {deleteEventContent} from "../content/contentDeletion";
import { db } from "../firebase/admin";
import { getOrganizationRoles } from "../permissions/organizationPermissions";
import { assertOwner, getUserPermissions, isOwner } from "../permissions/userPermissions";
import {
  type NotificationActionType,
  type NotificationSeverity,
  resolveNotificationRecipients,
  writeUserNotification,
} from "./notificationPayloads";
import {eventPublishingFieldChanged, nextEventStartMillis} from "./eventNotificationSemantics";

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

interface EventCancellationRequest {
  eventId: string;
  reason?: string;
}

interface EventCancellationResponse {
  eventId: string;
  status: "cancelled" | "deleted";
  recipientCount: number;
  notificationCount: number;
  pushRecipientCount: number;
  cancelledAt: string;
}

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
  retry: true,
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

function parseEventCancellationRequest(data: unknown): EventCancellationRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    eventId: requiredString(data, "eventId"),
    reason: optionalString(data, "reason"),
  };
}

function stringField(data: Record<string, unknown> | undefined, field: string): string | undefined {
  const value = data?.[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

async function assertCanCancelEvent(
  actorPermissions: Awaited<ReturnType<typeof getUserPermissions>>,
  eventData: Record<string, unknown>
): Promise<void> {
  if (isOwner(actorPermissions)) {
    return;
  }

  if (stringField(eventData, "sourceType") !== "organization") {
    throw new HttpsError("permission-denied", "Event cancellation permissions are required.");
  }

  const organizationId = stringField(eventData, "organizationId");
  if (!organizationId) {
    throw new HttpsError("permission-denied", "Event organization is missing.");
  }

  const roles = await getOrganizationRoles(organizationId);
  if (roles.ownerId !== actorPermissions.uid) {
    throw new HttpsError("permission-denied", "Event cancellation permissions are required.");
  }
}

function timestampField(
  data: Record<string, unknown> | undefined,
  field: string
): Timestamp | undefined {
  const value = data?.[field];
  return value instanceof Timestamp ? value : undefined;
}

function hasMeaningfulEventChange(
  before: Record<string, unknown>,
  after: Record<string, unknown>
): boolean {
  return eventPublishingFieldChanged(before, after);
}

function isCancellationTransition(after: Record<string, unknown>): boolean {
  return after.cancellationState === "cancelled"
    || (after.moderationStatus === "archived" && after.cancelledAt !== undefined);
}

function eventTitle(data: Record<string, unknown> | undefined): string {
  return stringField(data, "title") ?? "Event";
}

function localizedEventTitle(
  data: Record<string, unknown> | undefined,
  language: NotificationLanguage
): string {
  const localizations = data?.localizations;
  if (isRecord(localizations)) {
    const preferred = localizations[language];
    const ukrainian = localizations.uk;
    if (isRecord(preferred) && stringField(preferred, "title")) {
      return stringField(preferred, "title") as string;
    }
    if (isRecord(ukrainian) && stringField(ukrainian, "title")) {
      return stringField(ukrainian, "title") as string;
    }
  }
  return eventTitle(data);
}

function isSoon(data: Record<string, unknown> | undefined): boolean {
  const now = Date.now();
  const startMillis = nextEventStartMillis(data, now);
  if (startMillis === undefined) {
    return false;
  }

  const timeUntilStart = startMillis - now;
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

function eventCancellationNotificationId(eventId: string, userId: string): string {
  return ["eventCancelled", eventId, userId].join("_");
}

function eventCancellationCopy(
  title: string,
  language: NotificationLanguage
): EventNotificationCopy {
  const body = `${truncate(title, 120)} was cancelled.`;
  switch (language) {
    case "uk":
      return {
        title: "Подію скасовано",
        body: `Скасовано: ${truncate(title, 110)}`,
      };
    case "de":
      return {
        title: "Veranstaltung abgesagt",
        body: `Abgesagt: ${truncate(title, 110)}`,
      };
    case "en":
      return {
        title: "Event cancelled",
        body,
      };
  }
}

function eventUpdateCopy(
  title: string,
  language: NotificationLanguage
): EventNotificationCopy {
  switch (language) {
    case "uk":
      return {title: "Подію оновлено", body: `Оновлено: ${truncate(title, 110)}`};
    case "de":
      return {title: "Veranstaltung aktualisiert", body: `Aktualisiert: ${truncate(title, 110)}`};
    case "en":
      return {title: "Event updated", body: `${truncate(title, 110)} was updated.`};
  }
}

type NotificationLanguage = "uk" | "de" | "en";

interface EventNotificationCopy {
  title: string;
  body: string;
}

interface CreatedEventNotification {
  recipientUserId: string;
  notificationId: string;
}

async function writeEventCancellationNotifications(
  eventId: string,
  candidateUserIds: string[],
  input: {
    eventData: Record<string, unknown>;
    cancelledAt: Timestamp;
    requiresPopup: boolean;
  }
): Promise<{
  recipientCount: number;
  createdNotifications: CreatedEventNotification[];
  pushRecipientIds: Set<string>;
}> {
  const recipients = await resolveNotificationRecipients(candidateUserIds);
  const createdNotifications = (await Promise.all(
    recipients.inboxRecipientIds.map(async (userId) => {
      const userSnapshot = await db.collection("users").doc(userId).get();
      const language = notificationLanguage(userSnapshot.data());
      const title = localizedEventTitle(input.eventData, language);
      const copy = eventCancellationCopy(
        title,
        language
      );
      const notificationId = eventCancellationNotificationId(eventId, userId);
      const writeResult = await writeUserNotification({
        notificationId,
        targetUserId: userId,
        type: "eventCancelled",
        title: copy.title,
        message: copy.body,
        severity: input.requiresPopup ? "critical" : "warning",
        actionType: "openEvent",
        actionTargetId: eventId,
        requiresPopup: input.requiresPopup,
        sourceType: "event",
        sourceId: eventId,
        metadata: {
          eventId,
          eventTitle: title,
          cancelledAt: String(input.cancelledAt.toMillis()),
          route: "openEvent",
          routeTargetId: eventId,
          pushDelivery: "central",
        },
        dedupeKey: `eventCancelled:${eventId}`,
      });

      return writeResult.didCreate
        ? { recipientUserId: userId, notificationId }
        : undefined;
    })
  )).filter((notification): notification is CreatedEventNotification => notification !== undefined);

  return {
    recipientCount: recipients.inboxRecipientIds.length,
    createdNotifications,
    pushRecipientIds: new Set(recipients.pushRecipientIds),
  };
}

async function writeEventNotifications(
  eventId: string,
  userIds: string[],
  input: {
    type: "eventUpdated";
    severity: NotificationSeverity;
    requiresPopup: boolean;
    versionPart?: string;
    metadata: Record<string, unknown>;
    eventData?: Record<string, unknown>;
  }
): Promise<void> {
  const recipients = await resolveNotificationRecipients(userIds);
  await Promise.all(recipients.inboxRecipientIds.map(async (userId) => {
    const userSnapshot = await db.collection("users").doc(userId).get();
    const language = notificationLanguage(userSnapshot.data());
    const localizedTitle = localizedEventTitle(input.eventData, language);
    const copy = eventUpdateCopy(localizedTitle, language);
    return writeUserNotification({
      notificationId: ["eventUpdated", eventId, input.versionPart ?? "unknown", userId].join("_"),
      targetUserId: userId,
      type: input.type,
      title: copy.title,
      message: copy.body,
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
      dedupeKey: `${input.type}:${eventId}:${input.versionPart ?? "unknown"}`,
    });
  }));
}

export const notifyEventUpdatedOnUpdate = onDocumentUpdated(
  { ...triggerOptions, document: "events/{eventId}" },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before && after && !isCancellationTransition(before) && isCancellationTransition(after)) {
      await writeEventCancellationNotifications(event.params.eventId, await registeredUserIds(event.params.eventId), {
        eventData: after, cancelledAt: timestampField(after, "cancelledAt") ?? Timestamp.now(),
        requiresPopup: isSoon(after),
      });
      return;
    }
    if (!before || !after || isCancellationTransition(after) || !hasMeaningfulEventChange(before, after)) {
      return;
    }

    const eventId = event.params.eventId;
    const userIds = await registeredUserIds(eventId);
    if (userIds.length === 0) {
      return;
    }

    const versionPart = String(timestampField(after, "updatedAt")?.toMillis() ?? event.id);
    await writeEventNotifications(eventId, userIds, {
      type: "eventUpdated",
      severity: "info",
      requiresPopup: false,
      versionPart,
      metadata: {
        eventTitle: eventTitle(after),
        changedAt: versionPart,
      },
      eventData: after,
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

    const cancelledAt = Timestamp.now();
    const requiresPopup = isSoon(deletedEvent);
    await writeEventCancellationNotifications(eventId, userIds, {
      eventData: deletedEvent ?? {},
      cancelledAt,
      requiresPopup,
    });
  }
);

export const cancelEvent = onCall(
  callableOptions,
  async (request): Promise<EventCancellationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const actorPermissions = auth.permissions;
    const cancellationRequest = parseEventCancellationRequest(request.data);
    const eventReference = db.collection("events").doc(cancellationRequest.eventId);
    const eventSnapshot = await eventReference.get();
    if (!eventSnapshot.exists) {
      throw new HttpsError("not-found", "Event does not exist.");
    }

    const eventData = eventSnapshot.data() ?? {};
    await assertCanCancelEvent(actorPermissions, eventData);

    const eventId = cancellationRequest.eventId;
    const userIds = await registeredUserIds(eventId);
    const cancelledAt = Timestamp.now();
    const requiresPopup = isSoon(eventData);
    if (userIds.length === 0) {
      await deleteEventContent(eventId, eventData);
      return {
        eventId,
        status: "deleted",
        recipientCount: 0,
        notificationCount: 0,
        pushRecipientCount: 0,
        cancelledAt: cancelledAt.toDate().toISOString(),
      };
    }

    await eventReference.update({
      moderationStatus: "archived",
      cancellationState: "cancelled",
      cancelledAt,
      cancelledBy: auth.uid,
      cancellationReason: cancellationRequest.reason ?? FieldValue.delete(),
      updatedAt: cancelledAt,
    });

    const notificationResult = await writeEventCancellationNotifications(eventId, userIds, {
      eventData,
      cancelledAt,
      requiresPopup,
    });
    // Dispatch is asynchronous; this response must not claim device delivery.
    const pushRecipientCount = 0;

    return {
      eventId,
      status: "cancelled",
      recipientCount: notificationResult.recipientCount,
      notificationCount: notificationResult.createdNotifications.length,
      pushRecipientCount,
      cancelledAt: cancelledAt.toDate().toISOString(),
    };
  }
);

export const createSystemAnnouncement = onCall(
  callableOptions,
  async (request): Promise<{ announcementId: string; recipientCount: number }> => {
    const auth = await requireVerifiedActiveUser(request);
    const actorPermissions = auth.permissions;
    assertOwner(actorPermissions);

    const announcementRequest = parseSystemAnnouncementRequest(request.data);
    const targetUserIds = await resolveSystemAnnouncementRecipients(announcementRequest);
    const recipients = await resolveNotificationRecipients(targetUserIds);
    const inboxRecipientIds = recipients.inboxRecipientIds;
    const announcementId = randomUUID();

    await db.collection("systemAnnouncements").doc(announcementId).set({
      id: announcementId,
      title: announcementRequest.title,
      message: announcementRequest.message,
      severity: announcementRequest.severity,
      requiresPopup: announcementRequest.requiresPopup,
      targetMode: announcementRequest.targetMode,
      targetUserIds: inboxRecipientIds,
      role: announcementRequest.role ?? null,
      actionType: announcementRequest.actionType,
      actionTargetId: announcementRequest.actionTargetId ?? null,
      url: announcementRequest.url ?? null,
      createdAt: Timestamp.now(),
      createdBy: auth.uid,
    });

    await Promise.all(inboxRecipientIds.map((userId) => writeUserNotification({
      notificationId: ["systemAnnouncement", announcementId, userId].join("_"),
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
      recipientCount: inboxRecipientIds.length,
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

function notificationLanguage(data?: FirebaseFirestore.DocumentData): NotificationLanguage {
  const locale = [
    stringField(data, "language"),
    stringField(data, "appLanguage"),
    stringField(data, "locale"),
    stringField(data, "preferredLocale"),
    stringField(data, "preferredLanguage"),
  ].find((value) => value !== undefined)?.toLowerCase();

  if (locale?.startsWith("uk")) {
    return "uk";
  }

  if (locale?.startsWith("de")) {
    return "de";
  }

  return "en";
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength - 3)}...` : value;
}
