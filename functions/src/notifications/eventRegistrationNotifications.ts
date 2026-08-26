import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db } from "../firebase/admin";
import {
  resolveNotificationRecipients,
  writeUserNotification,
} from "./notificationPayloads";

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
  retry: true,
};


type NotificationLanguage = "uk" | "de" | "en";

interface EventRegistrationCopy {
  title: string;
  body: string;
}

export const notifyEventRegistrationConfirmedOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "registrations/{registrationId}" },
  async (event) => {
    const registration = event.data?.data();
    const eventId = stringField(registration, "eventId");
    const userId = stringField(registration, "userId");

    if (!eventId || !userId) {
      return;
    }

    const eventSnapshot = await db.collection("events").doc(eventId).get();
    const eventData = eventSnapshot.data();
    if (!eventSnapshot.exists || !isPublicApprovedEvent(eventData)) {
      return;
    }

    const recipients = await resolveNotificationRecipients([userId]);
    if (!recipients.inboxRecipientIds.includes(userId)) {
      return;
    }

    const userSnapshot = await db.collection("users").doc(userId).get();
    const eventTitle = stringField(eventData, "title") ?? "Event";
    const copy = eventRegistrationCopy(
      eventTitle,
      notificationLanguage(userSnapshot.data())
    );
    const notificationId = `eventRegistrationConfirmed_${event.id}_${userId}`;

    await writeUserNotification({
      notificationId,
      targetUserId: userId,
      type: "eventRegistrationConfirmed",
      title: copy.title,
      message: copy.body,
      severity: "info",
      actionType: "openEvent",
      actionTargetId: eventId,
      requiresPopup: false,
      sourceType: "event",
      sourceId: eventId,
      metadata: {
        eventId,
        eventTitle,
        route: "openEvent",
        routeTargetId: eventId,
      },
      dedupeKey: notificationId,
    });

  }
);

function isPublicApprovedEvent(data?: FirebaseFirestore.DocumentData): boolean {
  if (!data || data.moderationStatus !== "approved") {
    return false;
  }

  const visibility = stringField(data, "visibility");
  return visibility === undefined || visibility === "public";
}

function eventRegistrationCopy(
  eventTitle: string,
  language: NotificationLanguage
): EventRegistrationCopy {
  const body = truncate(eventTitle, 120);
  switch (language) {
    case "uk":
      return {
        title: "Реєстрацію підтверджено",
        body,
      };
    case "de":
      return {
        title: "Registrierung bestätigt",
        body,
      };
    case "en":
      return {
        title: "Registration confirmed",
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
