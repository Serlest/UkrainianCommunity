import { randomUUID } from "node:crypto";

import { FieldValue, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { type AuditActionType, auditLogRef, buildAuditLog } from "../audit/auditLog";
import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import { buildNotification, type NotificationType } from "../notifications/notificationPayloads";
import { getUserPermissions, isOwner } from "../permissions/userPermissions";
import { type OrganizationModerationStatus } from "./types";

type ReviewAction = "approve" | "requestRevision" | "reject";

interface OrganizationReviewRequest {
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

interface ReviewWorkflow {
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

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

function parseReviewRequest(data: unknown): OrganizationReviewRequest {
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

function assertReviewableStatus(status: OrganizationModerationStatus): void {
  if (!["pendingReview", "needsRevision", "rejected"].includes(status)) {
    throw new HttpsError("failed-precondition", "Organization request is not reviewable.");
  }
}

function requiredReviewText(
  request: OrganizationReviewRequest,
  field: "message" | "reason"
): string {
  const value = field === "message" ? request.message : request.reason;
  if (!value) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return value;
}

function notificationPayload(
  organization: OrganizationReviewSnapshot,
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

function organizationUpdate(
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

function createReviewCallable(workflow: ReviewWorkflow) {
  return onCall(callableOptions, async (request): Promise<OrganizationReviewResponse> => {
    const auth = requireAuth(request);
    const reviewRequest = parseReviewRequest(request.data);
    const actorPermissions = await getUserPermissions(auth.uid);

    if (!isOwner(actorPermissions)) {
      throw new HttpsError("permission-denied", "Owner permissions are required.");
    }

    const text = workflow.requiredTextField
      ? requiredReviewText(reviewRequest, workflow.requiredTextField)
      : undefined;
    const organizationReference = db.collection("organizations").doc(reviewRequest.organizationId);
    const notificationId = randomUUID();
    const committedAt = new Date().toISOString();

    await db.runTransaction(async (transaction) => {
      const organizationDocument = await transaction.get(organizationReference);
      if (!organizationDocument.exists) {
        throw new HttpsError("not-found", "Organization does not exist.");
      }

      const organization = reviewSnapshotFromData(
        reviewRequest.organizationId,
        organizationDocument.data()
      );
      assertReviewableStatus(organization.previousStatus);

      transaction.update(
        organizationReference,
        organizationUpdate(workflow, auth.uid, organization.submittedByUserId, text)
      );

      transaction.set(auditLogRef(), buildAuditLog({
        actionType: workflow.auditActionType,
        targetUserId: auth.uid,
        performedBy: auth.uid,
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

      const notificationReference = db
        .collection("users")
        .doc(organization.submittedByUserId)
        .collection("notificationInbox")
        .doc(notificationId);
      transaction.set(notificationReference, buildNotification({
        id: notificationId,
        recipientUserId: organization.submittedByUserId,
        type: workflow.notificationType,
        sourceType: "organization",
        sourceId: organization.organizationId,
        actorUserId: auth.uid,
        payload: notificationPayload(organization, workflow, text),
      }));
    });

    return {
      organizationId: reviewRequest.organizationId,
      moderationStatus: workflow.moderationStatus,
      notificationId,
      updatedAt: committedAt,
    };
  });
}

export const approveOrganization = createReviewCallable({
  action: "approve",
  moderationStatus: "approved",
  auditActionType: "organizationRequestApproved",
  notificationType: "organizationRequestApproved",
});

export const requestOrganizationRevision = createReviewCallable({
  action: "requestRevision",
  moderationStatus: "needsRevision",
  auditActionType: "organizationRequestNeedsRevision",
  notificationType: "organizationRequestNeedsRevision",
  requiredTextField: "message",
});

export const rejectOrganization = createReviewCallable({
  action: "reject",
  moderationStatus: "rejected",
  auditActionType: "organizationRequestRejected",
  notificationType: "organizationRequestRejected",
  requiredTextField: "reason",
});
