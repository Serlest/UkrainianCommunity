import { FieldValue } from "firebase-admin/firestore";

export type NotificationType =
  | "feedbackReply"
  | "organizationRequestApproved"
  | "organizationRequestNeedsRevision"
  | "organizationRequestRejected";

export interface NotificationInput {
  id: string;
  recipientUserId: string;
  type: NotificationType;
  sourceType: "feedback" | "organization";
  sourceId: string;
  actorUserId: string;
  actorDisplayName?: string;
  payload: Record<string, unknown>;
}

export function buildNotification(input: NotificationInput) {
  return {
    ...input,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
}
