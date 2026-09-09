import {createHash, randomUUID} from "node:crypto";
import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {type AuditActionType, auditLogRef, buildAuditLog} from "../audit/auditLog";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {
  buildUserNotificationDocument,
  notificationRecipientEligibility,
  type NotificationType,
  userNotificationRef,
} from "../notifications/notificationPayloads";
import {canManageOrganizationRequests} from "../permissions/userPermissions";
import {type OrganizationModerationStatus} from "./types";

export type ReviewAction = "approve" | "requestRevision" | "reject";

export interface OrganizationReviewRequest {
  organizationId: string;
  message?: string;
  reason?: string;
  operationId?: string;
  expectedRevision?: string | null;
}

interface OrganizationReviewResponse {
  organizationId: string;
  moderationStatus: OrganizationModerationStatus;
  notificationId: string;
  updatedAt: string;
}

export interface ReviewWorkflow {
  action: ReviewAction;
  moderationStatus: "approved" | "needsRevision" | "rejected";
  auditActionType: AuditActionType;
  notificationType: NotificationType;
  requiredTextField?: "message" | "reason";
}

interface OrganizationReviewSnapshot {
  organizationId: string;
  name: string;
  submittedByUserId: string;
  previousStatus: OrganizationModerationStatus;
}

interface OrganizationReviewNotificationTarget {
  organizationId: string;
  submittedByUserId: string;
  name: string;
}

interface OrganizationReviewCommitResult {
  notificationTarget: OrganizationReviewNotificationTarget;
  notificationId: string;
  updatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  enforceAppCheck: false,
};

export function parseReviewRequest(data: unknown): OrganizationReviewRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    organizationId: normalizedRequiredString(data.organizationId, "organizationId"),
    message: optionalTrimmedString(data.message, "message"),
    reason: optionalTrimmedString(data.reason, "reason"),
    operationId: optionalIdentifier(data.operationId, "operationId"),
    expectedRevision: optionalNullableString(data.expectedRevision, "expectedRevision"),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedRequiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return trimmedValue;
}

function optionalTrimmedString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : undefined;
}

function optionalIdentifier(value: unknown, field: string): string | undefined {
  const normalized = optionalTrimmedString(value, field);
  if (normalized !== undefined && (normalized.length > 200 || normalized.includes("/"))) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return normalized;
}

function optionalNullableString(value: unknown, field: string): string | null | undefined {
  if (value === null) return null;
  return optionalTrimmedString(value, field);
}

function organizationRevision(data: DocumentData | undefined): string | null {
  const updatedAt = data?.updatedAt;
  return updatedAt instanceof Timestamp ? `${updatedAt.seconds}:${updatedAt.nanoseconds}` : null;
}

function reviewSnapshotFromData(
  organizationId: string,
  data: DocumentData | undefined
): OrganizationReviewSnapshot {
  const name = typeof data?.name === "string" ? data.name : "";
  const submittedByUserId = typeof data?.submittedByUserId === "string"
    ? data.submittedByUserId.trim()
    : "";
  if (submittedByUserId.length === 0) {
    throw new HttpsError("failed-precondition", "Organization request submitter is missing.");
  }
  if (typeof data?.moderationStatus !== "string") {
    throw new HttpsError("failed-precondition", "Organization request status is missing.");
  }
  const previousStatus = data.moderationStatus as OrganizationModerationStatus;

  return {
    organizationId,
    name,
    submittedByUserId,
    previousStatus,
  };
}

export function assertReviewableStatus(status: OrganizationModerationStatus): void {
  if (status !== "pendingReview") {
    throw new HttpsError("failed-precondition", "Organization request is not reviewable.");
  }
}

export function requiredReviewText(
  request: OrganizationReviewRequest,
  field: "message" | "reason"
): string {
  const value = field === "message" ? request.message : request.reason;
  if (!value) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return value;
}

export function notificationPayload(
  organization: OrganizationReviewNotificationTarget,
  workflow: ReviewWorkflow,
  text?: string
): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    organizationId: organization.organizationId,
    organizationName: organization.name,
  };

  if (text && workflow.requiredTextField === "message") {
    payload.reviewMessage = text;
  }

  if (text && workflow.requiredTextField === "reason") {
    payload.rejectionReason = text;
  }

  return payload;
}

export function notificationTitle(workflow: ReviewWorkflow): string {
  switch (workflow.action) {
    case "approve":
      return "Organization request approved";
    case "requestRevision":
      return "Organization request needs revision";
    case "reject":
      return "Organization request rejected";
  }
}

export function notificationMessage(
  organization: OrganizationReviewNotificationTarget,
  workflow: ReviewWorkflow,
  text?: string
): string {
  const organizationName = organization.name || "Your organization";

  switch (workflow.action) {
    case "approve":
      return `${organizationName} was approved.`;
    case "requestRevision":
      return text
        ? `${organizationName} needs changes: ${text}`
        : `${organizationName} needs changes before approval.`;
    case "reject":
      return text
        ? `${organizationName} was rejected: ${text}`
        : `${organizationName} was rejected.`;
  }
}

export function organizationUpdate(
  workflow: ReviewWorkflow,
  actorUid: string,
  submittedByUserId: string,
  text?: string
) {
  const update: Record<string, unknown> = {
    moderationStatus: workflow.moderationStatus,
    reviewedByUserId: actorUid,
    reviewedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  switch (workflow.action) {
    case "approve":
      update.ownerId = submittedByUserId;
      update.reviewMessage = FieldValue.delete();
      update.rejectionReason = FieldValue.delete();
      break;
    case "requestRevision":
      update.reviewMessage = text;
      update.rejectionReason = FieldValue.delete();
      break;
    case "reject":
      update.rejectionReason = text;
      update.reviewMessage = FieldValue.delete();
      break;
  }

  return update;
}

export async function commitOrganizationReview(
  actorUid: string,
  reviewRequest: OrganizationReviewRequest,
  workflow: ReviewWorkflow,
  text?: string
): Promise<OrganizationReviewCommitResult> {
  const organizationReference = db.collection("organizations").doc(reviewRequest.organizationId);
  const operationId = reviewRequest.operationId;
  const receiptReference = operationId
    ? db.collection("organizationMutationReceipts").doc(createHash("sha256")
      .update(`review\0${actorUid}\0${reviewRequest.organizationId}\0${operationId}`)
      .digest("hex"))
    : null;
  const fingerprint = createHash("sha256").update(JSON.stringify({
    action: workflow.action,
    organizationId: reviewRequest.organizationId,
    expectedRevision: reviewRequest.expectedRevision,
    text: text ?? null,
  })).digest("hex");
  const reviewId = receiptReference?.id ?? randomUUID();
  return db.runTransaction(async (transaction): Promise<OrganizationReviewCommitResult> => {
    const [organizationDocument, receiptDocument] = receiptReference
      ? await transaction.getAll(organizationReference, receiptReference)
      : [await transaction.get(organizationReference), null];
    if (!organizationDocument.exists) {
      throw new HttpsError("not-found", "Organization does not exist.");
    }

    if (receiptDocument?.exists) {
      if (receiptDocument.get("fingerprint") !== fingerprint) {
        throw new HttpsError("already-exists", "Operation ID was reused.");
      }
      return {
        notificationTarget: {
          organizationId: reviewRequest.organizationId,
          submittedByUserId: receiptDocument.get("submittedByUserId"),
          name: receiptDocument.get("organizationName"),
        },
        notificationId: receiptDocument.get("notificationId"),
        updatedAt: receiptDocument.get("updatedAt"),
      };
    }

    const organization = reviewSnapshotFromData(
      reviewRequest.organizationId,
      organizationDocument.data()
    );
    if (reviewRequest.expectedRevision !== undefined &&
        organizationRevision(organizationDocument.data()) !== reviewRequest.expectedRevision) {
      throw new HttpsError("aborted", "Organization request changed. Reload before reviewing.");
    }
    assertReviewableStatus(organization.previousStatus);

    const submitterReference = db.collection("users").doc(organization.submittedByUserId);
    const submitterDocument = await transaction.get(submitterReference);
    const submitterData = submitterDocument.data();
    const accountStatus = typeof submitterData?.accountStatus === "string"
      ? submitterData.accountStatus
      : "active";
    const blockState = typeof submitterData?.blockState === "string"
      ? submitterData.blockState
      : accountStatus;
    const canReceiveInbox = notificationRecipientEligibility({
      userExists: submitterDocument.exists,
      accountStatus,
      blockState,
      notificationsEnabled: false,
    }).canReceiveInbox;
    const notificationTarget = {
      organizationId: organization.organizationId,
      submittedByUserId: organization.submittedByUserId,
      name: organization.name,
    };
    const notificationId = [
      workflow.notificationType,
      reviewId,
      organization.organizationId,
      organization.submittedByUserId,
    ].join("_");
    const now = Timestamp.now();
    const updatedAt = now.toDate().toISOString();

    transaction.update(
      organizationReference,
      organizationUpdate(workflow, actorUid, organization.submittedByUserId, text)
    );

    transaction.set(auditLogRef(), buildAuditLog({
      actionType: workflow.auditActionType,
      targetUserId: organization.submittedByUserId,
      performedBy: actorUid,
      reason: text ?? "Organization request review",
      previousValue: {
        organizationId: organization.organizationId,
        moderationStatus: organization.previousStatus,
      },
      newValue: {
        organizationId: organization.organizationId,
        moderationStatus: workflow.moderationStatus,
      },
    }));

    if (canReceiveInbox) {
      transaction.set(
        userNotificationRef(organization.submittedByUserId, notificationId),
        buildUserNotificationDocument({
          notificationId,
          targetUserId: organization.submittedByUserId,
          type: workflow.notificationType,
          title: notificationTitle(workflow),
          message: notificationMessage(notificationTarget, workflow, text),
          severity: workflow.action === "approve" ? "success" : "warning",
          actionType: "openOrganizationRequest",
          actionTargetId: organization.organizationId,
          requiresPopup: false,
          actorUserId: actorUid,
          sourceType: "organization",
          sourceId: organization.organizationId,
          metadata: notificationPayload(notificationTarget, workflow, text),
          dedupeKey: [
            "organizationRequest",
            organization.organizationId,
            workflow.moderationStatus,
          ].join(":"),
        })
      );
    }

    if (receiptReference) {
      transaction.create(receiptReference, {
        userId: actorUid,
        organizationId: organization.organizationId,
        submittedByUserId: organization.submittedByUserId,
        organizationName: organization.name,
        fingerprint,
        notificationId,
        updatedAt,
        completedAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + 30 * 24 * 60 * 60 * 1000),
      });
    }

    return {notificationTarget, notificationId, updatedAt};
  });
}

function createReviewCallable(workflow: ReviewWorkflow) {
  return onCall(callableOptions, async (request): Promise<OrganizationReviewResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const reviewRequest = parseReviewRequest(request.data);
    const actorPermissions = auth.permissions;

    if (!canManageOrganizationRequests(actorPermissions)) {
      throw new HttpsError("permission-denied", "Owner or App Admin permissions are required.");
    }

    const text = workflow.requiredTextField
      ? requiredReviewText(reviewRequest, workflow.requiredTextField)
      : undefined;
    const committed = await commitOrganizationReview(auth.uid, reviewRequest, workflow, text);

    return {
      organizationId: reviewRequest.organizationId,
      moderationStatus: workflow.moderationStatus,
      notificationId: committed.notificationId,
      updatedAt: committed.updatedAt,
    };
  });
}

export const approveOrganizationWorkflow: ReviewWorkflow = {
  action: "approve",
  moderationStatus: "approved",
  auditActionType: "organizationRequestApproved",
  notificationType: "organizationRequestApproved",
};

export const requestOrganizationRevisionWorkflow: ReviewWorkflow = {
  action: "requestRevision",
  moderationStatus: "needsRevision",
  auditActionType: "organizationRequestNeedsRevision",
  notificationType: "organizationRequestNeedsRevision",
  requiredTextField: "message",
};

export const rejectOrganizationWorkflow: ReviewWorkflow = {
  action: "reject",
  moderationStatus: "rejected",
  auditActionType: "organizationRequestRejected",
  notificationType: "organizationRequestRejected",
  requiredTextField: "reason",
};

export const approveOrganization = createReviewCallable(approveOrganizationWorkflow);
export const requestOrganizationRevision = createReviewCallable(
  requestOrganizationRevisionWorkflow
);
export const rejectOrganization = createReviewCallable(rejectOrganizationWorkflow);
