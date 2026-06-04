import { FieldValue } from "firebase-admin/firestore";

import { db } from "../firebase/admin";

export type NotificationType =
  | "accountStatusChanged"
  | "feedbackReply"
  | "guideMaterialUpdated"
  | "legalDocumentsUpdated"
  | "organizationRequestApproved"
  | "organizationRequestNeedsRevision"
  | "organizationRequestRejected"
  | "organizationRequestRevisionRequested"
  | "organizationRoleAssigned"
  | "organizationRoleRemoved"
  | "reportReviewed"
  | "roleChanged"
  | "systemAnnouncement"
  | "eventUpdated"
  | "eventCancelled";

export type NotificationSeverity = "info" | "success" | "warning" | "critical";

export type NotificationActionType =
  | "none"
  | "openEvent"
  | "openFeedback"
  | "openGuideMaterial"
  | "openGuideReport"
  | "openLegalDocuments"
  | "openOrganization"
  | "openOrganizationRequest"
  | "openProfile"
  | "openURL";

type NotificationSourceType =
  | "account"
  | "event"
  | "feedback"
  | "guide"
  | "legal"
  | "organization"
  | "profile"
  | "system";

interface NotificationDocumentInput {
  id: string;
  targetUserId: string;
  type: NotificationType;
  title: string;
  message: string;
  severity: NotificationSeverity;
  actionType: NotificationActionType;
  actionTargetId?: string;
  requiresPopup: boolean;
  metadata?: Record<string, unknown>;
  dedupeKey?: string;
  actorUserId?: string;
  actorDisplayName?: string;
  sourceType?: NotificationSourceType;
  sourceId?: string;
  payload?: Record<string, unknown>;
}

export interface WriteNotificationInput {
  targetUserId: string;
  type: NotificationType;
  title: string;
  message: string;
  severity?: NotificationSeverity;
  actionType?: NotificationActionType;
  actionTargetId?: string;
  requiresPopup?: boolean;
  metadata?: Record<string, unknown>;
  dedupeKey?: string;
  actorUserId?: string;
  actorDisplayName?: string;
  sourceType?: NotificationSourceType;
  sourceId?: string;
}

export interface WriteNotificationResult {
  notificationId: string;
  didCreate: boolean;
}

export interface NotificationInput {
  id: string;
  recipientUserId: string;
  type:
    | "feedbackReply"
    | "organizationRequestApproved"
    | "organizationRequestNeedsRevision"
    | "organizationRequestRejected";
  sourceType: "feedback" | "organization";
  sourceId: string;
  actorUserId: string;
  actorDisplayName?: string;
  payload: Record<string, unknown>;
}

export function buildNotification(input: NotificationInput) {
  return {
    ...input,
    userId: input.recipientUserId,
    severity: defaultSeverity(input.type),
    actionType: defaultActionType(input.type),
    actionTargetId: input.sourceId,
    requiresPopup: false,
    readAt: null,
    popupPresentedAt: null,
    archivedAt: null,
    deletedAt: null,
    metadata: input.payload,
    isRead: false,
    createdAt: FieldValue.serverTimestamp(),
  };
}

export async function writeUserNotification(
  input: WriteNotificationInput
): Promise<WriteNotificationResult> {
  const inboxReference = db
    .collection("users")
    .doc(input.targetUserId)
    .collection("notificationInbox");

  if (input.dedupeKey) {
    const existingNotification = await inboxReference
      .where("dedupeKey", "==", input.dedupeKey)
      .limit(1)
      .get();

    if (!existingNotification.empty) {
      return {
        notificationId: existingNotification.docs[0].id,
        didCreate: false,
      };
    }
  }

  const notificationReference = inboxReference.doc();
  await notificationReference.set(buildNotificationDocument({
    id: notificationReference.id,
    targetUserId: input.targetUserId,
    type: input.type,
    title: input.title,
    message: input.message,
    severity: input.severity ?? defaultSeverity(input.type),
    actionType: input.actionType ?? defaultActionType(input.type),
    actionTargetId: input.actionTargetId,
    requiresPopup: input.requiresPopup ?? false,
    metadata: input.metadata,
    dedupeKey: input.dedupeKey,
    actorUserId: input.actorUserId,
    actorDisplayName: input.actorDisplayName,
    sourceType: input.sourceType ?? defaultSourceType(input.type),
    sourceId: input.sourceId ?? input.actionTargetId,
  }));

  return {
    notificationId: notificationReference.id,
    didCreate: true,
  };
}

function buildNotificationDocument(input: NotificationDocumentInput) {
  const metadata = {
    ...(input.metadata ?? {}),
    title: input.title,
    message: input.message,
  };
  const document: Record<string, unknown> = {
    id: input.id,
    userId: input.targetUserId,
    recipientUserId: input.targetUserId,
    type: input.type,
    title: input.title,
    message: input.message,
    severity: input.severity,
    actionType: input.actionType,
    actionTargetId: input.actionTargetId ?? null,
    requiresPopup: input.requiresPopup,
    popupPresentedAt: null,
    expiresAt: null,
    archivedAt: null,
    deletedAt: null,
    readAt: null,
    metadata,
    payload: input.payload ?? metadata,
    isRead: false,
    sourceType: input.sourceType ?? defaultSourceType(input.type),
    sourceId: input.sourceId ?? input.actionTargetId ?? input.targetUserId,
    createdAt: FieldValue.serverTimestamp(),
  };

  if (input.actorUserId) {
    document.actorUserId = input.actorUserId;
  }

  if (input.actorDisplayName) {
    document.actorDisplayName = input.actorDisplayName;
  }

  if (input.dedupeKey) {
    document.dedupeKey = input.dedupeKey;
  }

  return document;
}

function defaultSeverity(type: NotificationType): NotificationSeverity {
  switch (type) {
    case "accountStatusChanged":
    case "organizationRequestNeedsRevision":
    case "organizationRequestRejected":
    case "organizationRequestRevisionRequested":
    case "eventCancelled":
      return "warning";
    case "organizationRequestApproved":
      return "success";
    case "systemAnnouncement":
      return "critical";
    case "feedbackReply":
    case "eventUpdated":
    case "guideMaterialUpdated":
    case "legalDocumentsUpdated":
    case "organizationRoleAssigned":
    case "organizationRoleRemoved":
    case "reportReviewed":
    case "roleChanged":
      return "info";
  }
}

function defaultActionType(type: NotificationType): NotificationActionType {
  switch (type) {
    case "feedbackReply":
      return "openFeedback";
    case "guideMaterialUpdated":
      return "openGuideMaterial";
    case "eventUpdated":
    case "eventCancelled":
      return "openEvent";
    case "legalDocumentsUpdated":
      return "openLegalDocuments";
    case "organizationRequestApproved":
    case "organizationRequestNeedsRevision":
    case "organizationRequestRejected":
    case "organizationRequestRevisionRequested":
      return "openOrganizationRequest";
    case "organizationRoleAssigned":
    case "organizationRoleRemoved":
      return "openOrganization";
    case "reportReviewed":
      return "openGuideReport";
    case "accountStatusChanged":
    case "roleChanged":
      return "openProfile";
    case "systemAnnouncement":
      return "none";
  }
}

function defaultSourceType(type: NotificationType): NotificationSourceType {
  switch (type) {
    case "feedbackReply":
      return "feedback";
    case "eventUpdated":
    case "eventCancelled":
      return "event";
    case "guideMaterialUpdated":
    case "reportReviewed":
      return "guide";
    case "legalDocumentsUpdated":
      return "legal";
    case "organizationRequestApproved":
    case "organizationRequestNeedsRevision":
    case "organizationRequestRejected":
    case "organizationRequestRevisionRequested":
    case "organizationRoleAssigned":
    case "organizationRoleRemoved":
      return "organization";
    case "accountStatusChanged":
      return "account";
    case "roleChanged":
      return "profile";
    case "systemAnnouncement":
      return "system";
  }
}
