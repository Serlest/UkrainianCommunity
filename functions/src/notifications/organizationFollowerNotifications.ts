import { FieldPath, FieldValue } from "firebase-admin/firestore";
import type { Query, QueryDocumentSnapshot } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";

import { db } from "../firebase/admin";
import {
  buildNotificationDataPayload,
  resolveNotificationRecipients,
} from "./notificationPayloads";

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const followerPageSize = 250;
const concurrentRecipientWrites = 50;
const fcmMulticastLimit = 500;

type PublishedContentKind = "news" | "event";
type NotificationLanguage = "uk" | "de" | "en";

interface PublishedOrganizationContent {
  kind: PublishedContentKind;
  contentId: string;
  organizationId: string;
  organizationName: string;
  title: string;
  excludedUserIds: string[];
}

interface CreatedRecipientNotification {
  recipientUserId: string;
  notificationId: string;
}

interface FollowerNotificationCopy {
  title: string;
  body: string;
}

export const notifyOrganizationFollowersForNewsCreated = onDocumentCreated(
  { ...triggerOptions, document: "news/{newsId}" },
  async (event) => {
    const content = publishedOrganizationContent(
      "news",
      event.params.newsId,
      event.data?.data()
    );
    if (!content) {
      return;
    }

    await notifyOrganizationFollowers(content);
  }
);

export const notifyOrganizationFollowersForNewsPublished = onDocumentUpdated(
  { ...triggerOptions, document: "news/{newsId}" },
  async (event) => {
    const before = publishedOrganizationContent(
      "news",
      event.params.newsId,
      event.data?.before.data()
    );
    const after = publishedOrganizationContent(
      "news",
      event.params.newsId,
      event.data?.after.data()
    );
    if (before || !after) {
      return;
    }

    await notifyOrganizationFollowers(after);
  }
);

export const notifyOrganizationFollowersForEventCreated = onDocumentCreated(
  { ...triggerOptions, document: "events/{eventId}" },
  async (event) => {
    const content = publishedOrganizationContent(
      "event",
      event.params.eventId,
      event.data?.data()
    );
    if (!content) {
      return;
    }

    await notifyOrganizationFollowers(content);
  }
);

export const notifyOrganizationFollowersForEventPublished = onDocumentUpdated(
  { ...triggerOptions, document: "events/{eventId}" },
  async (event) => {
    const before = publishedOrganizationContent(
      "event",
      event.params.eventId,
      event.data?.before.data()
    );
    const after = publishedOrganizationContent(
      "event",
      event.params.eventId,
      event.data?.after.data()
    );
    if (before || !after) {
      return;
    }

    await notifyOrganizationFollowers(after);
  }
);

async function notifyOrganizationFollowers(content: PublishedOrganizationContent): Promise<void> {
  const excludedUserIds = new Set(content.excludedUserIds);
  let lastDocument: QueryDocumentSnapshot | undefined;

  do {
    const page = await followerPage(content.organizationId, lastDocument);
    if (page.docs.length === 0) {
      return;
    }

    const candidateUserIds = page.docs
      .map((document) => stringField(document.data(), "userId"))
      .filter((userId): userId is string => userId !== undefined)
      .filter((userId) => !excludedUserIds.has(userId));
    const recipients = await resolveNotificationRecipients(candidateUserIds);
    const createdNotifications = await writeFollowerInboxNotifications(
      content,
      recipients.inboxRecipientIds
    );
    const pushRecipientIds = new Set(recipients.pushRecipientIds);
    await sendFollowerPushes(
      content,
      createdNotifications.filter((notification) => pushRecipientIds.has(notification.recipientUserId))
    );

    lastDocument = page.docs.at(-1);
  } while (lastDocument !== undefined);
}

async function followerPage(
  organizationId: string,
  after?: QueryDocumentSnapshot
): Promise<FirebaseFirestore.QuerySnapshot> {
  let query: Query = db.collection("likes")
    .where("subscribedOrganizationId", "==", organizationId)
    .orderBy("createdAt", "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(followerPageSize);

  if (after) {
    query = query.startAfter(after);
  }

  return query.get();
}

async function writeFollowerInboxNotifications(
  content: PublishedOrganizationContent,
  recipientUserIds: string[]
): Promise<CreatedRecipientNotification[]> {
  const createdNotifications: CreatedRecipientNotification[] = [];

  for (const chunk of chunks(recipientUserIds, concurrentRecipientWrites)) {
    const bulkWriter = db.bulkWriter();
    const writeResults = Promise.all(chunk.map(async (recipientUserId) => {
      const notificationId = followerNotificationId(content, recipientUserId);
      const userSnapshot = await db.collection("users").doc(recipientUserId).get();
      const copy = followerNotificationCopy(content, notificationLanguage(userSnapshot.data()));
      const notificationReference = db.collection("users")
        .doc(recipientUserId)
        .collection("notificationInbox")
        .doc(notificationId);

      try {
        await bulkWriter.create(
          notificationReference,
          followerNotificationDocument(content, recipientUserId, notificationId, copy)
        );
      } catch (error) {
        if (isAlreadyExistsError(error)) {
          return undefined;
        }
        throw error;
      }

      return {
        recipientUserId,
        notificationId,
      };
    }));
    await bulkWriter.close();
    const results = await writeResults;

    createdNotifications.push(...results.filter(
      (result): result is CreatedRecipientNotification => result !== undefined
    ));
  }

  return createdNotifications;
}

function followerNotificationDocument(
  content: PublishedOrganizationContent,
  recipientUserId: string,
  notificationId: string,
  copy: FollowerNotificationCopy
): Record<string, unknown> {
  const route = content.kind === "news" ? "openNews" : "openEvent";
  const type = content.kind === "news"
    ? "organizationNewsPublished"
    : "organizationEventPublished";
  const metadata = {
    organizationId: content.organizationId,
    organizationName: content.organizationName,
    contentId: content.contentId,
    contentTitle: content.title,
    route,
    routeTargetId: content.contentId,
  };

  return {
    id: notificationId,
    userId: recipientUserId,
    recipientUserId,
    type,
    title: copy.title,
    message: copy.body,
    severity: "info",
    actionType: route,
    actionTargetId: content.contentId,
    requiresPopup: false,
    popupPresentedAt: null,
    expiresAt: null,
    archivedAt: null,
    deletedAt: null,
    readAt: null,
    sourceType: "organization",
    sourceId: content.organizationId,
    metadata,
    payload: metadata,
    dedupeKey: notificationId,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
}

function isAlreadyExistsError(error: unknown): boolean {
  const code = typeof error === "object" && error !== null && "code" in error
    ? (error as { code?: unknown }).code
    : undefined;

  return code === 6 || code === "already-exists" || code === "ALREADY_EXISTS";
}

async function sendFollowerPushes(
  content: PublishedOrganizationContent,
  createdNotifications: CreatedRecipientNotification[]
): Promise<void> {
  await Promise.all(createdNotifications.map(async (notification) => {
    const [userSnapshot, tokenSnapshot] = await Promise.all([
      db.collection("users").doc(notification.recipientUserId).get(),
      db.collection("users")
        .doc(notification.recipientUserId)
        .collection("notificationPushTokens")
        .get(),
    ]);
    const tokens = tokenSnapshot.docs
      .map((document) => stringField(document.data(), "token"))
      .filter((token): token is string => token !== undefined);
    if (tokens.length === 0) {
      return;
    }

    const data = buildNotificationDataPayload({
      notificationId: notification.notificationId,
      type: content.kind === "news"
        ? "organizationNewsPublished"
        : "organizationEventPublished",
      sourceType: "organization",
      sourceId: content.organizationId,
      actionType: content.kind === "news" ? "openNews" : "openEvent",
      actionTargetId: content.contentId,
      route: content.kind === "news" ? "openNews" : "openEvent",
      routeTargetId: content.contentId,
    });
    const copy = followerNotificationCopy(content, notificationLanguage(userSnapshot.data()));

    await Promise.all(chunks(tokens, fcmMulticastLimit).map((tokenChunk) =>
      getMessaging().sendEachForMulticast({
        tokens: tokenChunk,
        notification: {
          title: copy.title,
          body: copy.body,
        },
        data,
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      })
    ));
  }));
}

function publishedOrganizationContent(
  kind: PublishedContentKind,
  contentId: string,
  data?: FirebaseFirestore.DocumentData
): PublishedOrganizationContent | undefined {
  if (!data || !isPublicOrganizationContent(kind, data)) {
    return undefined;
  }

  const organizationId = stringField(data, "organizationId");
  if (!organizationId) {
    return undefined;
  }

  return {
    kind,
    contentId,
    organizationId,
    organizationName: stringField(data, "organizationName") ?? "An organization you follow",
    title: stringField(data, "title") ?? (kind === "news" ? "News" : "Event"),
    excludedUserIds: [
      stringField(data, "authorId"),
      stringField(data, "createdBy"),
      stringField(data, "createdByUserId"),
      stringField(data, "submittedByUserId"),
      stringField(data, "updatedBy"),
      stringField(data, "updatedByUserId"),
    ].filter((userId): userId is string => userId !== undefined),
  };
}

function isPublicOrganizationContent(
  kind: PublishedContentKind,
  data: FirebaseFirestore.DocumentData
): boolean {
  if (data.sourceType !== "organization" || data.moderationStatus !== "approved") {
    return false;
  }

  if (kind === "event") {
    const visibility = stringField(data, "visibility");
    return visibility === undefined || visibility === "public";
  }

  return true;
}

function followerNotificationId(
  content: PublishedOrganizationContent,
  recipientUserId: string
): string {
  const prefix = content.kind === "news"
    ? "organizationNewsPublished"
    : "organizationEventPublished";
  return `${prefix}_${content.contentId}_${recipientUserId}`;
}

function followerNotificationCopy(
  content: PublishedOrganizationContent,
  language: NotificationLanguage
): FollowerNotificationCopy {
  const body = truncate(content.title, 120);
  switch (language) {
    case "uk":
      return {
        title: content.kind === "news"
          ? `Нова новина від ${content.organizationName}`
          : `Нова подія від ${content.organizationName}`,
        body,
      };
    case "de":
      return {
        title: content.kind === "news"
          ? `Neue Nachricht von ${content.organizationName}`
          : `Neue Veranstaltung von ${content.organizationName}`,
        body,
      };
    case "en":
      return {
        title: content.kind === "news"
          ? `New news from ${content.organizationName}`
          : `New event from ${content.organizationName}`,
        body,
      };
  }
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

function stringField(
  data: FirebaseFirestore.DocumentData | undefined,
  field: string
): string | undefined {
  const value = data?.[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? `${value.slice(0, maxLength - 3)}...` : value;
}

function chunks<T>(values: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < values.length; index += size) {
    result.push(values.slice(index, index + size));
  }
  return result;
}
