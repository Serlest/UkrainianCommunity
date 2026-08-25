import { FieldPath } from "firebase-admin/firestore";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireVerifiedActiveUser } from "../auth/context";
import { db } from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";
import {
  buildNotificationDataPayload,
  type NotificationActionType,
  type NotificationSourceType,
  type NotificationType,
  resolveNotificationRecipients,
  writeUserNotification,
} from "./notificationPayloads";
import { sendPushToRegistrationDocuments } from "./pushRegistrations";

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 20,
};

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

interface TestPushResponse {
  targetCount: number;
  successCount: number;
  failureCount: number;
}

export const sendTestPushNotification = onCall(
  callableOptions,
  async (request): Promise<TestPushResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertCanSendTestPush(auth.permissions);
    const recipients = await resolveNotificationRecipients([auth.uid]);
    if (!recipients.pushRecipientIds.includes(auth.uid)) {
      throw new HttpsError(
        "failed-precondition",
        "Push notifications are disabled for this account."
      );
    }

    const registrations = await db.collection("users")
      .doc(auth.uid)
      .collection("notificationPushTokens")
      .get();
    if (registrations.empty) {
      throw new HttpsError(
        "failed-precondition",
        "No notification-enabled device is registered for this account."
      );
    }

    const delivery = await sendPushToRegistrationDocuments(registrations.docs, {
      notification: {
        title: "Ukrainian Community",
        body: "Test notification delivered successfully.",
      },
      data: buildNotificationDataPayload({
        notificationId: `pushTest_${auth.uid}_${Date.now()}`,
        type: "systemAnnouncement",
        sourceType: "system",
        sourceId: "pushTest",
        actionType: "none",
      }),
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    if (delivery.successCount === 0) {
      throw new HttpsError(
        "unavailable",
        "Firebase could not deliver the test notification to a registered device."
      );
    }
    return delivery;
  }
);

export function assertCanSendTestPush(
  permissions: Parameters<typeof assertOwner>[0]
): void {
  assertOwner(permissions);
}

const centrallyDeliveredTypes = new Set<NotificationType>([
  "accountStatusChanged",
  "eventCancelled",
  "eventUpdated",
  "legalDocumentsUpdated",
  "organizationRequestApproved",
  "organizationRequestNeedsRevision",
  "organizationRequestRejected",
  "organizationRoleAssigned",
  "organizationRoleRemoved",
  "reportReviewed",
  "roleChanged",
  "systemAnnouncement",
]);

const notificationTypes = new Set<NotificationType>([
  "accountStatusChanged",
  "feedbackSubmitted",
  "feedbackReply",
  "legalDocumentsUpdated",
  "organizationEventPublished",
  "organizationNewsPublished",
  "organizationRequestApproved",
  "organizationRequestNeedsRevision",
  "organizationRequestRejected",
  "organizationRoleAssigned",
  "organizationRoleRemoved",
  "reportReviewed",
  "roleChanged",
  "systemAnnouncement",
  "eventUpdated",
  "eventCancelled",
  "eventRegistrationConfirmed",
]);

const actionTypes = new Set<NotificationActionType>([
  "none",
  "openNews",
  "openEvent",
  "openFeedback",
  "openLegalDocuments",
  "openOrganization",
  "openOrganizationRequest",
  "openProfile",
  "openURL",
]);

const sourceTypes = new Set<NotificationSourceType>([
  "account",
  "event",
  "feedback",
  "legal",
  "organization",
  "profile",
  "system",
]);

export const deliverInboxNotificationPushOnCreate = onDocumentCreated(
  {
    ...triggerOptions,
    document: "users/{userId}/notificationInbox/{notificationId}",
  },
  async (event) => {
    const notification = event.data?.data();
    const type = enumString(notification?.type, notificationTypes);
    if (!notification || !type || !shouldDeliverInboxNotificationPush(type, notification.metadata)) {
      return;
    }

    const metadata = recordValue(notification.metadata);

    const userId = event.params.userId;
    const recipients = await resolveNotificationRecipients([userId], {
      // Account restrictions are already committed when this trigger runs.
      // The affected user must still receive the one push that explains why
      // access changed, provided they explicitly enabled notifications.
      allowRestrictedPush: type === "accountStatusChanged",
    });
    if (!recipients.pushRecipientIds.includes(userId)) {
      return;
    }

    const tokenSnapshot = await db.collection("users")
      .doc(userId)
      .collection("notificationPushTokens")
      .get();
    if (tokenSnapshot.empty) {
      console.info("Notification push skipped because the user has no registered device.", {
        userId,
        notificationId: event.params.notificationId,
        type,
      });
      return;
    }

    const sourceType = enumString(notification.sourceType, sourceTypes) ?? "system";
    const sourceId = stringValue(notification.sourceId) ?? event.params.notificationId;
    const actionType = enumString(notification.actionType, actionTypes) ?? "none";
    const actionTargetId = stringValue(notification.actionTargetId);
    const route = stringValue(metadata.route);
    const routeTargetId = stringValue(metadata.routeTargetId);
    const title = stringValue(notification.title) ?? fallbackTitle(type);
    const body = stringValue(notification.message) ?? title;
    const localizedAlert = localizedAlertKeys(type, metadata);
    const delivery = await sendPushToRegistrationDocuments(tokenSnapshot.docs, {
      notification: { title, body },
      data: buildNotificationDataPayload({
        notificationId: event.params.notificationId,
        type,
        sourceType,
        sourceId,
        actionType,
        actionTargetId,
        route,
        routeTargetId,
      }),
      apns: {
        payload: {
          aps: {
            alert: {
              titleLocKey: localizedAlert.titleLocKey,
              locKey: localizedAlert.bodyLocKey,
            },
            sound: "default",
          },
        },
      },
    });

    console.info("Notification push delivery completed.", {
      userId,
      notificationId: event.params.notificationId,
      type,
      ...delivery,
    });
  }
);

export function shouldDeliverInboxNotificationPush(
  type: NotificationType,
  metadataValue: unknown
): boolean {
  return centrallyDeliveredTypes.has(type)
    && recordValue(metadataValue).pushManagedByWriter !== true;
}

export function localizedAlertKeys(
  type: NotificationType,
  metadata: Record<string, unknown>
): {titleLocKey: string; bodyLocKey: string} {
  if (type === "accountStatusChanged") {
    switch (stringValue(metadata.newAccountStatus)) {
      case "warned":
        return {
          titleLocKey: "account_status_alert.warned.title",
          bodyLocKey: "account_status_alert.warned.message",
        };
      case "suspendedUntil":
        return {
          titleLocKey: "account_status_alert.suspended.title",
          bodyLocKey: "account_status_alert.suspended.message",
        };
      case "bannedPermanent":
        return {
          titleLocKey: "account_status_alert.banned.title",
          bodyLocKey: "account_status_alert.banned.message",
        };
      case "deactivated":
        return {
          titleLocKey: "account_status_alert.deactivated.title",
          bodyLocKey: "account_status_alert.deactivated.message",
        };
      case "active":
        return {
          titleLocKey: "account_status_alert.restored.title",
          bodyLocKey: "account_status_alert.restored.message",
        };
      default:
        break;
    }
  }

  const titleLocKeyByType: Partial<Record<NotificationType, string>> = {
    legalDocumentsUpdated: "notifications.inbox.legal_documents_updated.title",
    organizationRequestApproved: "notifications.inbox.organization_approved.title",
    organizationRequestNeedsRevision: "notifications.inbox.organization_needs_revision.title",
    organizationRequestRejected: "notifications.inbox.organization_rejected.title",
    organizationRoleAssigned: "notifications.inbox.organization_role_assigned.title",
    organizationRoleRemoved: "notifications.inbox.organization_role_removed.title",
    reportReviewed: "notifications.inbox.report_reviewed.title",
    roleChanged: "notifications.inbox.role_changed.title",
    systemAnnouncement: "notifications.inbox.system_announcement.title",
  };

  return {
    titleLocKey: titleLocKeyByType[type] ?? "notifications.inbox.title",
    bodyLocKey: "notifications.inbox.generic.body",
  };
}

export const notifyLegalDocumentsUpdatedOnPublish = onDocumentUpdated(
  {
    ...triggerOptions,
    document: "legalDocuments/{documentType}",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const activeVersion = stringValue(after?.activeVersion);
    if (!after || !activeVersion || before?.activeVersion === activeVersion || after.status !== "published") {
      return;
    }

    const documentType = event.params.documentType;
    let lastUserId: string | undefined;
    do {
      let query = db.collection("users")
        .orderBy(FieldPath.documentId())
        .limit(100);
      if (lastUserId) {
        query = query.startAfter(lastUserId);
      }
      const page = await query.get();
      if (page.empty) {
        return;
      }

      const recipients = await resolveNotificationRecipients(page.docs.map((document) => document.id));
      await Promise.all(recipients.inboxRecipientIds.map((userId) => writeUserNotification({
        notificationId: `legalDocumentsUpdated_${documentType}_${activeVersion}_${userId}`,
        targetUserId: userId,
        type: "legalDocumentsUpdated",
        title: "Legal documents updated",
        message: stringValue(after.changeSummary) ?? "Please review the updated legal documents.",
        severity: after.requiresAcceptance === true ? "warning" : "info",
        actionType: "openLegalDocuments",
        actionTargetId: documentType,
        requiresPopup: false,
        actorUserId: stringValue(after.publishedBy),
        sourceType: "legal",
        sourceId: documentType,
        metadata: {
          documentType,
          activeVersion,
          route: "openLegalDocuments",
          routeTargetId: documentType,
        },
        dedupeKey: `legalDocumentsUpdated:${documentType}:${activeVersion}:${userId}`,
      })));

      lastUserId = page.docs.at(-1)?.id;
      if (page.size < 100) {
        return;
      }
    } while (lastUserId !== undefined);
  }
);

export const notifyReportReviewedOnUpdate = onDocumentUpdated(
  {
    ...triggerOptions,
    document: "feedback/{feedbackId}",
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const userId = stringValue(after?.userId);
    if (!after || after.type !== "report" || after.status !== "closed" || before?.status === "closed" || !userId) {
      return;
    }

    await writeUserNotification({
      notificationId: `reportReviewed_${event.params.feedbackId}_${userId}`,
      targetUserId: userId,
      type: "reportReviewed",
      title: "Report reviewed",
      message: "Your report has been reviewed and closed.",
      severity: "info",
      actionType: "openFeedback",
      actionTargetId: event.params.feedbackId,
      requiresPopup: false,
      sourceType: "feedback",
      sourceId: event.params.feedbackId,
      metadata: {
        reportId: event.params.feedbackId,
        route: "openFeedback",
        routeTargetId: event.params.feedbackId,
      },
      dedupeKey: `reportReviewed:${event.params.feedbackId}:${userId}`,
    });
  }
);

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function recordValue(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function enumString<T extends string>(value: unknown, values: Set<T>): T | undefined {
  return typeof value === "string" && values.has(value as T) ? value as T : undefined;
}

function fallbackTitle(type: NotificationType): string {
  return type === "systemAnnouncement" ? "Important announcement" : "Ukrainian Community";
}
