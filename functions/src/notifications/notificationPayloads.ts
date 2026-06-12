import { FieldValue } from "firebase-admin/firestore";

import { db } from "../firebase/admin";

export type NotificationType =
  | "accountStatusChanged"
  | "feedbackSubmitted"
  | "feedbackReply"
  | "guideMaterialUpdated"
  | "legalDocumentsUpdated"
  | "organizationEventPublished"
  | "organizationNewsPublished"
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
  | "eventCancelled"
  | "eventRegistrationConfirmed";

export type NotificationSeverity = "info" | "success" | "warning" | "critical";

export type NotificationActionType =
  | "none"
  | "openNews"
  | "openEvent"
  | "openFeedback"
  | "openGuideMaterial"
  | "openGuideReport"
  | "openLegalDocuments"
  | "openOrganization"
  | "openOrganizationRequest"
  | "openProfile"
  | "openURL";

export type NotificationSourceType =
  | "account"
  | "event"
  | "feedback"
  | "guide"
  | "legal"
  | "news"
  | "organization"
  | "profile"
  | "system";

export interface NotificationDataPayloadInput {
  notificationId: string;
  type: NotificationType;
  sourceType: NotificationSourceType;
  sourceId: string;
  actionType: NotificationActionType;
  actionTargetId?: string;
  route?: string;
  routeTargetId?: string;
}

export interface NotificationRecipientResolution {
  inboxRecipientIds: string[];
  pushRecipientIds: string[];
}

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
  notificationId: string;
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

export function buildNotificationDataPayload(
  input: NotificationDataPayloadInput
): Record<string, string> {
  const route = input.route ?? defaultRoute(input.actionType, input.sourceType);
  const routeTargetId = input.routeTargetId ?? input.actionTargetId ?? input.sourceId;

  return {
    notificationId: input.notificationId,
    type: input.type,
    sourceType: input.sourceType,
    sourceId: input.sourceId,
    actionType: input.actionType,
    actionTargetId: input.actionTargetId ?? "",
    route,
    routeTargetId,
  };
}

export async function resolveNotificationRecipients(
  candidateUserIds: string[]
): Promise<NotificationRecipientResolution> {
  const uniqueUserIds = Array.from(new Set(candidateUserIds.filter((userId) => userId.length > 0)));
  const recipientStates = await Promise.all(uniqueUserIds.map(async (userId) => {
    const [userSnapshot, preferencesSnapshot] = await Promise.all([
      db.collection("users").doc(userId).get(),
      db.collection("users")
        .doc(userId)
        .collection("notificationPreferences")
        .doc("settings")
        .get(),
    ]);

    const userData = userSnapshot.data();
    const accountStatus = typeof userData?.accountStatus === "string"
      ? userData.accountStatus
      : "active";
    const blockState = typeof userData?.blockState === "string"
      ? userData.blockState
      : accountStatus;
    const canReceiveInbox = ["active", "warned"].includes(accountStatus)
      && ["active", "warned"].includes(blockState);

    return {
      userId,
      canReceiveInbox,
      canReceivePush: canReceiveInbox
        && preferencesSnapshot.data()?.notificationsEnabled === true,
    };
  }));

  return {
    inboxRecipientIds: recipientStates
      .filter((state) => state.canReceiveInbox)
      .map((state) => state.userId),
    pushRecipientIds: recipientStates
      .filter((state) => state.canReceivePush)
      .map((state) => state.userId),
  };
}

export async function writeUserNotification(
  input: WriteNotificationInput
): Promise<WriteNotificationResult> {
  const notificationReference = db
    .collection("users")
    .doc(input.targetUserId)
    .collection("notificationInbox")
    .doc(input.notificationId);

  const didCreate = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(notificationReference);
    if (snapshot.exists) {
      return {
        didCreate: false,
      };
    }

    transaction.set(notificationReference, buildNotificationDocument({
      id: input.notificationId,
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
      didCreate: true,
    };
  });

  return {
    notificationId: input.notificationId,
    didCreate: didCreate.didCreate,
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
    case "feedbackSubmitted":
    case "feedbackReply":
    case "eventUpdated":
    case "eventRegistrationConfirmed":
    case "organizationEventPublished":
    case "organizationNewsPublished":
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
    case "feedbackSubmitted":
    case "feedbackReply":
      return "openFeedback";
    case "organizationNewsPublished":
      return "openNews";
    case "organizationEventPublished":
    case "eventRegistrationConfirmed":
      return "openEvent";
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
    case "feedbackSubmitted":
    case "feedbackReply":
      return "feedback";
    case "eventUpdated":
    case "eventCancelled":
    case "eventRegistrationConfirmed":
      return "event";
    case "organizationNewsPublished":
    case "organizationEventPublished":
      return "organization";
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

function defaultRoute(
  actionType: NotificationActionType,
  sourceType: NotificationSourceType
): string {
  switch (actionType) {
    case "openNews":
      return "openNews";
    case "openEvent":
      return "openEvent";
    case "openFeedback":
      return "openFeedback";
    case "openOrganization":
    case "openOrganizationRequest":
      return "openOrganization";
    case "openProfile":
      return "openProfile";
    case "openURL":
      return "openURL";
    case "none":
    case "openGuideMaterial":
    case "openGuideReport":
    case "openLegalDocuments":
      break;
  }

  switch (sourceType) {
    case "news":
      return "openNews";
    case "event":
      return "openEvent";
    case "feedback":
      return "openFeedback";
    case "organization":
      return "openOrganization";
    case "account":
    case "profile":
      return "openProfile";
    case "system":
      return "systemAnnouncement";
    case "guide":
    case "legal":
      return "none";
  }
}
