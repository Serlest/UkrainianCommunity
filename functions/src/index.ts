import {FieldValue} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

import {db} from "./firebase/admin";

export * from "./counters/aggregation";
export * from "./analytics/trackAnalyticsEvent";
export * from "./legal/legalDocuments";
export * from "./notifications/backendWriters";
export * from "./organizations/approvalWorkflow";
export * from "./organizations/roleManagement";
export * from "./users/accountStatusManagement";
export * from "./users/platformRoleManagement";

const feedbackManagers = ["owner", "admin", "moderator"];

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
    feedbackManagers.map((role) =>
      db.collection("users").where("globalRole", "==", role).get()
    )
  );

  return Array.from(
    new Set(
      snapshots
        .flatMap((snapshot) => snapshot.docs.map((document) => document.id))
        .filter((userId) => userId !== excludedUserId)
    )
  );
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
  const notificationReference = db
    .collection("users")
    .doc(input.recipientUserId)
    .collection("notificationInbox")
    .doc(input.notificationId);

  await notificationReference.set(
    {
      id: input.notificationId,
      recipientUserId: input.recipientUserId,
      type: input.type,
      sourceType: "feedback",
      sourceId: input.sourceId,
      actionType: "openFeedback",
      actionTargetId: input.sourceId,
      metadata: {
        titleLocKey: input.titleLocKey,
        bodyLocKey: input.bodyLocKey,
      },
      payload: input.payload,
      actorUserId: input.actorUserId ?? null,
      actorDisplayName: input.actorDisplayName ?? null,
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  try {
    await sendPushIfEnabled(input.recipientUserId, input.notificationId, input.titleLocKey, input.bodyLocKey, input.bodyLocArgs, {
      type: input.type,
      sourceType: "feedback",
      sourceId: input.sourceId,
      actionType: "openFeedback",
      actionTargetId: input.sourceId,
    });
  } catch (error) {
    console.error("Feedback push delivery failed after inbox notification was created.", {
      notificationId: input.notificationId,
      recipientUserId: input.recipientUserId,
      error,
    });
  }
}

async function sendPushIfEnabled(
  userId: string,
  notificationId: string,
  titleLocKey: string,
  bodyLocKey: string,
  bodyLocArgs: string[],
  data: Record<string, string>
) {
  const preferencesSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("notificationPreferences")
    .doc("settings")
    .get();
  if (preferencesSnapshot.data()?.notificationsEnabled !== true) {
    return;
  }

  const tokensSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("notificationPushTokens")
    .get();
  const tokens = tokensSnapshot.docs
    .map((document) => document.data().token)
    .filter((token): token is string => typeof token === "string" && token.length > 0);
  if (tokens.length === 0) {
    return;
  }

  await getMessaging().sendEachForMulticast({
    tokens,
    data: {
      notificationId,
      ...data,
    },
    apns: {
      payload: {
        aps: {
          alert: {
            titleLocKey,
            locKey: bodyLocKey,
            locArgs: bodyLocArgs,
          },
          sound: "default",
        },
      },
    },
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
