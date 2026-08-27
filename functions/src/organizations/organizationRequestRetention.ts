import {Timestamp, type DocumentData, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {db} from "../firebase/admin";
import {
  buildUserNotificationDocument,
  userNotificationRef,
} from "../notifications/notificationPayloads";

export const organizationRequestRetentionDays = 30;
export const organizationRequestWarningLeadDays = 7;
const millisecondsPerDay = 24 * 60 * 60 * 1_000;
const eligibleStatuses = ["needsRevision", "rejected"] as const;
const pageSize = 200;

export type OrganizationRequestRetentionState = "active" | "warning" | "expired";

export function organizationRequestActivityMilliseconds(
  data: Record<string, unknown>
): number | undefined {
  for (const field of ["updatedAt", "reviewedAt", "submittedAt", "createdAt"] as const) {
    const value = data[field];
    if (value instanceof Timestamp) return value.toMillis();
    if (value instanceof Date) return value.getTime();
  }
  return undefined;
}

export function organizationRequestRetentionState(
  activityMilliseconds: number,
  nowMilliseconds: number
): OrganizationRequestRetentionState {
  const age = nowMilliseconds - activityMilliseconds;
  if (age >= organizationRequestRetentionDays * millisecondsPerDay) return "expired";
  if (age >= (organizationRequestRetentionDays - organizationRequestWarningLeadDays) * millisecondsPerDay) {
    return "warning";
  }
  return "active";
}

export const cleanupAbandonedOrganizationRequests = onSchedule(
  {
    schedule: "every day 04:23",
    timeZone: "Europe/Vienna",
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 3,
  },
  async () => {
    const now = Date.now();
    const warningCutoff = Timestamp.fromMillis(
      now - (organizationRequestRetentionDays - organizationRequestWarningLeadDays) * millisecondsPerDay
    );
    let warned = 0;
    let deleted = 0;

    for (const status of eligibleStatuses) {
      let cursor: QueryDocumentSnapshot<DocumentData> | undefined;
      do {
        let query = db.collection("organizations")
          .where("moderationStatus", "==", status)
          .where("updatedAt", "<=", warningCutoff)
          .orderBy("updatedAt", "asc")
          .limit(pageSize);
        if (cursor) query = query.startAfter(cursor);
        const snapshot = await query.get();

        for (const candidate of snapshot.docs) {
          const result = await processOrganizationRequest(candidate.id, now);
          if (result === "warning") warned += 1;
          if (result === "expired") deleted += 1;
        }
        cursor = snapshot.docs.at(-1);
      } while (cursor);
    }

    logger.info("Organization request retention completed.", {warned, deleted});
  }
);

export async function processOrganizationRequest(
  organizationId: string,
  nowMilliseconds: number
): Promise<OrganizationRequestRetentionState | "skipped"> {
  const organizationReference = db.collection("organizations").doc(organizationId);
  let shouldRecursivelyDelete = false;

  const result = await db.runTransaction(async (transaction) => {
    const organizationSnapshot = await transaction.get(organizationReference);
    if (!organizationSnapshot.exists) return "skipped" as const;

    const organization = organizationSnapshot.data() ?? {};
    const status = typeof organization.moderationStatus === "string" ? organization.moderationStatus : "";
    const userId = typeof organization.submittedByUserId === "string" ? organization.submittedByUserId : "";
    const activityMilliseconds = organizationRequestActivityMilliseconds(organization);
    if (!eligibleStatuses.includes(status as typeof eligibleStatuses[number]) || !userId || activityMilliseconds === undefined) {
      return "skipped" as const;
    }

    const state = organizationRequestRetentionState(activityMilliseconds, nowMilliseconds);
    if (state === "active") return "skipped" as const;

    const organizationName = typeof organization.name === "string" && organization.name.trim()
      ? organization.name.trim()
      : "Organization";
    const activityKey = Math.trunc(activityMilliseconds).toString(36);
    const userReference = db.collection("users").doc(userId);
    const userSnapshot = await transaction.get(userReference);
    if (!userSnapshot.exists) return "skipped" as const;

    if (state === "warning") {
      const deletionDate = new Date(
        activityMilliseconds + organizationRequestRetentionDays * millisecondsPerDay
      ).toISOString();
      const notificationId = `organization-request-cleanup-warning-${organizationId}-${activityKey}`;
      const notificationReference = userNotificationRef(userId, notificationId);
      const notificationSnapshot = await transaction.get(notificationReference);
      if (notificationSnapshot.exists) return "skipped" as const;

      transaction.set(notificationReference, buildUserNotificationDocument({
        notificationId,
        targetUserId: userId,
        type: "organizationRequestCleanupWarning",
        title: "Organization request will be deleted soon",
        message: `${organizationName} will be deleted if it is not updated or resubmitted.`,
        actionTargetId: organizationId,
        sourceId: organizationId,
        dedupeKey: notificationId,
        metadata: {
          organizationName,
          deletionDate,
          titleLocKey: "notifications.inbox.organization_cleanup_warning.title",
          bodyLocKey: "notifications.inbox.organization_cleanup_warning.body",
        },
      }));
      return "warning" as const;
    }

    const notificationId = `organization-request-expired-${organizationId}-${activityKey}`;
    transaction.set(userNotificationRef(userId, notificationId), buildUserNotificationDocument({
      notificationId,
      targetUserId: userId,
      type: "organizationRequestExpired",
      title: "Organization request deleted",
      message: `${organizationName} was deleted after 30 days without changes.`,
      sourceId: organizationId,
      dedupeKey: notificationId,
      metadata: {
        organizationName,
        titleLocKey: "notifications.inbox.organization_expired.title",
        bodyLocKey: "notifications.inbox.organization_expired.body",
      },
    }));
    transaction.set(auditLogRef(), buildAuditLog({
      actionType: "organizationRequestExpired",
      targetUserId: userId,
      performedBy: "system",
      reason: "Unpublished organization request expired after 30 days without activity.",
      previousValue: {organizationId, moderationStatus: status, organizationName},
      newValue: {deleted: true},
    }));
    transaction.delete(db.collection("organizationCreationProofs").doc(organizationId));
    transaction.delete(organizationReference);
    shouldRecursivelyDelete = true;
    return "expired" as const;
  });

  if (shouldRecursivelyDelete) await db.recursiveDelete(organizationReference);
  return result;
}
