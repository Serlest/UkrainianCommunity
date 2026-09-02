import {randomUUID} from "node:crypto";
import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { type AuditActionType, auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireVerifiedActiveUser } from "../auth/context";
import { db } from "../firebase/admin";
import {
  buildUserNotificationDocument,
  notificationRecipientEligibility,
  type NotificationType,
  userNotificationRef,
} from "../notifications/notificationPayloads";
import { canManageOrganizationRequests } from "../permissions/userPermissions";
import { type OrganizationModerationStatus } from "./types";

export type ReviewAction = "approve" | "requestRevision" | "reject";

export interface OrganizationReviewRequest {
  organizationId: string;
  message?: string;
  reason?: string;
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

function reviewSnapshotFromData(
  organizationId: string,
  data: DocumentData | undefined
): OrganizationReviewSnapshot {
  const name = typeof data?.name === "string" ? data.name : "";
  const submittedByUserId = typeof data?.submittedByUserId === "string"
    ? data.submittedByUserId.trim()
    : "";
  const previousStatus = typeof data?.moderationStatus === "string"
    ? data.moderationStatus as OrganizationModerationStatus
    : "pendingReview";

  if (submittedByUserId.length === 0) {
    throw new HttpsError("failed-precondition", "Organization request submitter is missing.");
  }

  return {
    organizationId,
    name,
    submittedByUserId,
    previousStatus,
  };
}

export function assertReviewableStatus(status: OrganizationModerationStatus): void {
  if (!["pendingReview", "needsRevision", "rejected"].includes(status)) {
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

  const reviewId = randomUUID();
  return db.runTransaction(async (transaction): Promise<OrganizationReviewCommitResult> => {
    const organizationDocument = await transaction.get(organizationReference);
    if (!organizationDocument.exists) {
      throw new HttpsError("not-found", "Organization does not exist.");
    }

    const organization = reviewSnapshotFromData(
      reviewRequest.organizationId,
      organizationDocument.data()
    );
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

    return {notificationTarget, notificationId};
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
    const committedAt = new Date().toISOString();
    const committed = await commitOrganizationReview(auth.uid, reviewRequest, workflow, text);

    return {
      organizationId: reviewRequest.organizationId,
      moderationStatus: workflow.moderationStatus,
      notificationId: committed.notificationId,
      updatedAt: committedAt,
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
