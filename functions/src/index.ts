import {FieldValue} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {db} from "./firebase/admin";
import {
  resolveNotificationRecipients,
} from "./notifications/notificationPayloads";
import {feedbackManagerGlobalRoles} from "./permissions/userPermissions";

export * from "./counters/aggregation";
export * from "./analytics/analyticsConsent";
export * from "./analytics/trackAnalyticsEvent";
export * from "./content/contentDeletion";
export * from "./content/contentCoverUpload";
export * from "./content/legacyContentMediaMigration";
export * from "./content/scheduledPublishing";
export * from "./content/storageOrphanCleanup";
export * from "./contentPlanning/contentPlanningMediaLifecycle";
export * from "./contentPlanning/ownerContentDrafts";
export * from "./events/eventRegistration";
export * from "./featured/featuredBannerCleanup";
export * from "./featured/featuredBannerMutations";
export * from "./feedback/feedbackManagement";
export * from "./legal/legalDocuments";
export * from "./legal/legalEvidence";
export * from "./legal/organizationRulesAcceptance";
export * from "./notifications/backendWriters";
export * from "./notifications/eventRegistrationNotifications";
export * from "./notifications/inboxPushDelivery";
export * from "./notifications/organizationFollowerNotifications";
export * from "./notifications/pushRegistrationMutations";
export * from "./organizations/approvalWorkflow";
export * from "./organizations/organizationRequestRetention";
export * from "./organizations/organizationPhotoMutations";
export * from "./organizations/roleManagement";
export * from "./retention/dataRetention";
export * from "./safety/contentReports";
export * from "./safety/commentModeration";
export * from "./safety/dsaCases";
export * from "./safety/userBlocks";
export * from "./systemLogs/clientDiagnostics";
export * from "./systemLogs/systemLogManagement";
export * from "./users/accountStatusManagement";
export * from "./users/accountDeletion";
export * from "./users/platformRoleManagement";
export * from "./users/userManagementQueries";
export {updateUserPresence, getManagedUserPresence} from "./users/userPresence";

type FeedbackData = {
  id?: string;
  type?: string;
  subject?: string;
  message?: string;
  userId?: string;
  userDisplayName?: string;
  lastMessageText?: string;
};

type FeedbackMessageData = {
  senderId?: string;
  senderDisplayName?: string;
  senderRole?: string;
  text?: string;
};

export const notifyFeedbackCreated = onDocumentCreated(
  {
    document: "feedback/{feedbackId}",
    region: "europe-west3",
    retry: true,
  },
  async (event) => {
    const feedback = event.data?.data() as FeedbackData | undefined;
    if (!feedback) {
      return;
    }

    const feedbackId = event.params.feedbackId;
    const recipients = await feedbackManagerUserIds(feedback.userId);
    await Promise.all(
      recipients.map((recipientUserId) =>
        createInboxNotificationAndPush({
          recipientUserId,
          notificationId: `feedbackSubmitted_${feedbackId}_${recipientUserId}`,
          type: "feedbackSubmitted",
          sourceId: feedbackId,
          titleLocKey: "notifications.push.feedback_submitted.title",
          bodyLocKey: "notifications.push.feedback_submitted.body",
          bodyLocArgs: [displayName(feedback.userDisplayName)],
          actorUserId: feedback.userId,
          actorDisplayName: feedback.userDisplayName,
          payload: {
            subject: feedback.subject ?? feedback.type ?? "",
            messagePreview: preview(feedback.message ?? feedback.lastMessageText),
          },
        })
      )
    );
  }
);

export const notifyFeedbackMessageCreated = onDocumentCreated(
  {
    document: "feedback/{feedbackId}/messages/{messageId}",
    region: "europe-west3",
    retry: true,
  },
  async (event) => {
    const message = event.data?.data() as FeedbackMessageData | undefined;
    if (!message) {
      return;
    }

    const feedbackId = event.params.feedbackId;
    const feedbackSnapshot = await db.collection("feedback").doc(feedbackId).get();
    const feedback = feedbackSnapshot.data() as FeedbackData | undefined;
    if (!feedback) {
      return;
    }

    if (message.senderRole === "owner") {
      const recipientUserId = feedback.userId;
      if (!recipientUserId || recipientUserId === message.senderId) {
        return;
      }

      await createInboxNotificationAndPush({
        recipientUserId,
        notificationId: `feedbackReply_${feedbackId}_${event.params.messageId}_${recipientUserId}`,
        type: "feedbackReply",
        sourceId: feedbackId,
        titleLocKey: "notifications.push.feedback_reply.title",
        bodyLocKey: "notifications.push.feedback_reply.body",
        bodyLocArgs: [],
        actorUserId: message.senderId,
        actorDisplayName: message.senderDisplayName,
        payload: {
          subject: feedback.subject ?? feedback.type ?? "",
          messagePreview: preview(message.text),
        },
      });
      return;
    }

    if (message.senderRole === "user") {
      const recipients = await feedbackManagerUserIds(message.senderId);
      await Promise.all(
        recipients.map((recipientUserId) =>
          createInboxNotificationAndPush({
            recipientUserId,
            notificationId: `feedbackSubmitted_${feedbackId}_${event.params.messageId}_${recipientUserId}`,
            type: "feedbackSubmitted",
            sourceId: feedbackId,
            titleLocKey: "notifications.push.feedback_submitted.title",
            bodyLocKey: "notifications.push.feedback_message_added.body",
            bodyLocArgs: [displayName(message.senderDisplayName)],
            actorUserId: message.senderId,
            actorDisplayName: message.senderDisplayName,
            payload: {
              subject: feedback.subject ?? feedback.type ?? "",
              messagePreview: preview(message.text),
            },
          })
        )
      );
    }
  }
);

async function feedbackManagerUserIds(excludedUserId?: string): Promise<string[]> {
  const snapshots = await Promise.all(
    feedbackManagerGlobalRoles.map((role) =>
      db.collection("users").where("globalRole", "==", role).get()
    )
  );

  const managerUserIds = Array.from(
    new Set(
      snapshots
        .flatMap((snapshot) => snapshot.docs.map((document) => document.id))
        .filter((userId) => userId !== excludedUserId)
    )
  );
  const recipients = await resolveNotificationRecipients(managerUserIds);
  return recipients.inboxRecipientIds;
}

async function createInboxNotificationAndPush(input: {
  recipientUserId: string;
  notificationId: string;
  type: "feedbackSubmitted" | "feedbackReply";
  sourceId: string;
  titleLocKey: string;
  bodyLocKey: string;
  bodyLocArgs: string[];
  actorUserId?: string;
  actorDisplayName?: string;
  payload: Record<string, string>;
}) {
  const recipients = await resolveNotificationRecipients([input.recipientUserId]);
  if (!recipients.inboxRecipientIds.includes(input.recipientUserId)) {
    return;
  }

  const notificationReference = db
    .collection("users")
    .doc(input.recipientUserId)
    .collection("notificationInbox")
    .doc(input.notificationId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(notificationReference);
    if (snapshot.exists) {
      return false;
    }

    transaction.set(notificationReference, {
      id: input.notificationId,
      userId: input.recipientUserId,
      recipientUserId: input.recipientUserId,
      type: input.type,
      title: input.titleLocKey,
      message: input.bodyLocKey,
      severity: "info",
      sourceType: "feedback",
      sourceId: input.sourceId,
      actionType: "openFeedback",
      actionTargetId: input.sourceId,
      requiresPopup: false,
      popupPresentedAt: null,
      expiresAt: null,
      archivedAt: null,
      deletedAt: null,
      readAt: null,
      metadata: {
        pushDelivery: "central",
        titleLocKey: input.titleLocKey,
        bodyLocArgs: input.bodyLocArgs,
        bodyLocKey: input.bodyLocKey,
        ...input.payload,
      },
      payload: input.payload,
      actorUserId: input.actorUserId ?? null,
      actorDisplayName: input.actorDisplayName ?? null,
      dedupeKey: input.notificationId,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });

    return true;
  });

}

function preview(value?: string): string {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 140 ? `${trimmed.slice(0, 137)}...` : trimmed;
}

function displayName(value?: string): string {
  const trimmed = value?.trim() ?? "";
  return trimmed.length > 0 ? trimmed : "A user";
}
export { cleanupAnalyticsAggregates } from "./analytics/cleanupAnalyticsAggregates";
export {notifyOrganizationRequestSubmitted, notifyNewsCommentCreated, notifyEventCommentCreated,
  notifyOrganizationCommentCreated, notifyNewsModerationChanged, notifyEventModerationChanged,
  notifyEventParticipationChanged} from "./notifications/workflowNotifications";
