import {createHash, randomUUID} from "node:crypto";

import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {buildAuditLog} from "../audit/auditLog";
import {organizationStoragePrefix} from "../content/contentDeletionPolicy";
import {adminStorage, db} from "../firebase/admin";
import {
  buildUserNotificationDocument,
  userNotificationRef,
} from "../notifications/notificationPayloads";

export const organizationRequestRetentionDays = 30;
export const organizationRequestWarningLeadDays = 7;
export const organizationRequestRetentionJobCollection = "organizationRequestRetentionJobs";

const millisecondsPerDay = 24 * 60 * 60 * 1_000;
const eligibleStatuses = ["needsRevision", "rejected"] as const;
const claimedStatus = "retentionDeleting";
const pageSize = 200;
const leaseDurationMilliseconds = 15 * 60 * 1_000;
const completedJobRetentionMilliseconds = 90 * millisecondsPerDay;
const resumableJobStatuses = ["pending", "storageDeleted", "firestoreDeleted"] as const;

export type OrganizationRequestRetentionState = "active" | "warning" | "expired";
type RetentionJobStatus = typeof resumableJobStatuses[number] | "completed" | "cancelled";
type RetentionJobProcessingResult = "completed" | "cancelled" | "leased";

export interface OrganizationRequestRetentionDependencies {
  deleteStoragePrefix(prefix: string): Promise<void>;
  recursivelyDeleteOrganization(organizationId: string): Promise<void>;
}

interface RetentionJobDocument {
  organizationId: string;
  organizationName: string;
  userId?: string;
  activityMilliseconds: number;
  status: RetentionJobStatus;
}

interface PreparedOrganizationRequest {
  state: OrganizationRequestRetentionState | "skipped";
  jobId?: string;
}

const productionRetentionDependencies: OrganizationRequestRetentionDependencies = {
  async deleteStoragePrefix(prefix: string): Promise<void> {
    await adminStorage.bucket().deleteFiles({prefix, force: true});
  },
  async recursivelyDeleteOrganization(organizationId: string): Promise<void> {
    await db.recursiveDelete(db.collection("organizations").doc(organizationId));
  },
};

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
    const failures: unknown[] = [];
    let resumed = 0;
    let warned = 0;
    let deleted = 0;

    const outstandingJobs = await db.collection(organizationRequestRetentionJobCollection)
      .where("status", "in", [...resumableJobStatuses])
      .limit(pageSize)
      .get();
    for (const job of outstandingJobs.docs) {
      try {
        const result = await processOrganizationRequestRetentionJob(job.id, now);
        if (result === "completed") resumed += 1;
      } catch (error) {
        failures.push(error);
        logger.error("Failed to resume organization request retention job.", {
          jobId: job.id,
          error: retentionErrorMessage(error),
        });
      }
    }

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
          try {
            const result = await processOrganizationRequest(candidate.id, now);
            if (result === "warning") warned += 1;
            if (result === "expired") deleted += 1;
          } catch (error) {
            failures.push(error);
            logger.error("Failed to process organization request retention candidate.", {
              organizationId: candidate.id,
              error: retentionErrorMessage(error),
            });
          }
        }
        cursor = snapshot.docs.at(-1);
      } while (cursor);
    }

    logger.info("Organization request retention completed.", {
      resumed,
      warned,
      deleted,
      failed: failures.length,
    });
    if (failures.length > 0) {
      throw new Error(`Organization request retention failed for ${failures.length} item(s).`);
    }
  }
);

export async function processOrganizationRequest(
  organizationId: string,
  nowMilliseconds: number,
  dependencies: OrganizationRequestRetentionDependencies = productionRetentionDependencies
): Promise<OrganizationRequestRetentionState | "skipped"> {
  const prepared = await prepareOrganizationRequest(organizationId, nowMilliseconds);
  if (prepared.state !== "expired" || !prepared.jobId) return prepared.state;

  const result = await processOrganizationRequestRetentionJob(
    prepared.jobId,
    nowMilliseconds,
    dependencies
  );
  return result === "completed" ? "expired" : "skipped";
}

export async function processOrganizationRequestRetentionJob(
  jobId: string,
  nowMilliseconds: number,
  dependencies: OrganizationRequestRetentionDependencies = productionRetentionDependencies
): Promise<RetentionJobProcessingResult> {
  const jobReference = db.collection(organizationRequestRetentionJobCollection).doc(jobId);
  const leaseId = randomUUID();
  const acquired = await acquireRetentionJob(jobReference, jobId, leaseId, nowMilliseconds);
  if (acquired.result !== "acquired") return acquired.result;
  if (!acquired.job) throw new Error("Acquired retention job payload is missing.");

  let status = acquired.job.status;
  try {
    if (status === "pending") {
      await dependencies.deleteStoragePrefix(
        organizationStoragePrefix(acquired.job.organizationId)
      );
      await advanceRetentionJob(
        jobReference,
        leaseId,
        "pending",
        "storageDeleted",
        nowMilliseconds
      );
      status = "storageDeleted";
    }

    if (status === "storageDeleted") {
      await dependencies.recursivelyDeleteOrganization(acquired.job.organizationId);
      await db.collection("organizationCreationProofs")
        .doc(acquired.job.organizationId)
        .delete();
      await advanceRetentionJob(
        jobReference,
        leaseId,
        "storageDeleted",
        "firestoreDeleted",
        nowMilliseconds
      );
      status = "firestoreDeleted";
    }

    if (status === "firestoreDeleted") {
      await completeRetentionJob(jobReference, jobId, leaseId, acquired.job, nowMilliseconds);
    }
    return "completed";
  } catch (error) {
    await releaseRetentionJobLease(jobReference, leaseId, error, nowMilliseconds);
    throw error;
  }
}

async function prepareOrganizationRequest(
  organizationId: string,
  nowMilliseconds: number
): Promise<PreparedOrganizationRequest> {
  const organizationReference = db.collection("organizations").doc(organizationId);

  return db.runTransaction(async (transaction): Promise<PreparedOrganizationRequest> => {
    const organizationSnapshot = await transaction.get(organizationReference);
    if (!organizationSnapshot.exists) return {state: "skipped"};

    const organization = organizationSnapshot.data() ?? {};
    const status = typeof organization.moderationStatus === "string"
      ? organization.moderationStatus
      : "";
    if (status === claimedStatus && typeof organization.retentionDeletionJobId === "string") {
      return {state: "expired", jobId: organization.retentionDeletionJobId};
    }

    const activityMilliseconds = organizationRequestActivityMilliseconds(organization);
    if (!eligibleStatuses.includes(status as typeof eligibleStatuses[number]) || activityMilliseconds === undefined) {
      return {state: "skipped"};
    }

    const state = organizationRequestRetentionState(activityMilliseconds, nowMilliseconds);
    if (state === "active") return {state: "skipped"};

    const organizationName = typeof organization.name === "string" && organization.name.trim()
      ? organization.name.trim()
      : "Organization";
    const userId = typeof organization.submittedByUserId === "string"
      ? organization.submittedByUserId.trim()
      : "";
    const activityKey = Math.trunc(activityMilliseconds).toString(36);

    if (state === "warning") {
      if (!userId) return {state: "skipped"};
      const userReference = db.collection("users").doc(userId);
      const notificationId = `organization-request-cleanup-warning-${organizationId}-${activityKey}`;
      const notificationReference = userNotificationRef(userId, notificationId);
      const [userSnapshot, notificationSnapshot] = await transaction.getAll(
        userReference,
        notificationReference
      );
      if (!userSnapshot.exists || notificationSnapshot.exists) return {state: "skipped"};

      const deletionDate = new Date(
        activityMilliseconds + organizationRequestRetentionDays * millisecondsPerDay
      ).toISOString();
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
      return {state: "warning"};
    }

    const jobId = retentionJobId(organizationId, activityMilliseconds);
    const jobReference = db.collection(organizationRequestRetentionJobCollection).doc(jobId);
    const jobSnapshot = await transaction.get(jobReference);
    if (jobSnapshot.exists) {
      const existingStatus = jobSnapshot.data()?.status;
      if (!resumableJobStatuses.includes(existingStatus)) return {state: "skipped"};
    } else {
      transaction.set(jobReference, {
        organizationId,
        organizationName,
        userId: userId || null,
        activityMilliseconds,
        status: "pending",
        attemptCount: 0,
        leaseId: null,
        leaseExpiresAt: null,
        lastAttemptAt: null,
        lastError: null,
        completedAt: null,
        expiresAt: null,
        createdAt: Timestamp.fromMillis(nowMilliseconds),
        updatedAt: Timestamp.fromMillis(nowMilliseconds),
      });
    }
    transaction.update(organizationReference, {
      moderationStatus: claimedStatus,
      retentionDeletionJobId: jobId,
      retentionDeletionStartedAt: Timestamp.fromMillis(nowMilliseconds),
    });
    return {state: "expired", jobId};
  });
}

async function acquireRetentionJob(
  jobReference: DocumentReference,
  jobId: string,
  leaseId: string,
  nowMilliseconds: number
): Promise<{
  result: "acquired" | RetentionJobProcessingResult;
  job?: RetentionJobDocument;
}> {
  return db.runTransaction(async (transaction) => {
    const jobSnapshot = await transaction.get(jobReference);
    if (!jobSnapshot.exists) return {result: "cancelled" as const};
    const job = retentionJobDocument(jobSnapshot.data());
    if (job.status === "completed") return {result: "completed" as const};
    if (job.status === "cancelled") return {result: "cancelled" as const};

    const leaseExpiresAt = jobSnapshot.data()?.leaseExpiresAt;
    if (leaseExpiresAt instanceof Timestamp && leaseExpiresAt.toMillis() > nowMilliseconds) {
      return {result: "leased" as const};
    }

    const organizationReference = db.collection("organizations").doc(job.organizationId);
    const organizationSnapshot = await transaction.get(organizationReference);
    if (organizationSnapshot.exists) {
      const organization = organizationSnapshot.data() ?? {};
      if (organization.moderationStatus !== claimedStatus
        || organization.retentionDeletionJobId !== jobId) {
        transaction.update(jobReference, {
          status: "cancelled",
          cancellationReason: "Organization request changed after retention claim.",
          leaseId: null,
          leaseExpiresAt: null,
          completedAt: Timestamp.fromMillis(nowMilliseconds),
          expiresAt: Timestamp.fromMillis(
            nowMilliseconds + completedJobRetentionMilliseconds
          ),
          updatedAt: Timestamp.fromMillis(nowMilliseconds),
        });
        return {result: "cancelled" as const};
      }
    }

    transaction.update(jobReference, {
      leaseId,
      leaseExpiresAt: Timestamp.fromMillis(nowMilliseconds + leaseDurationMilliseconds),
      lastAttemptAt: Timestamp.fromMillis(nowMilliseconds),
      lastError: null,
      attemptCount: FieldValue.increment(1),
      updatedAt: Timestamp.fromMillis(nowMilliseconds),
    });
    return {result: "acquired" as const, job};
  });
}

async function advanceRetentionJob(
  jobReference: DocumentReference,
  leaseId: string,
  expectedStatus: RetentionJobStatus,
  nextStatus: RetentionJobStatus,
  nowMilliseconds: number
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(jobReference);
    if (!snapshot.exists
      || snapshot.data()?.leaseId !== leaseId
      || snapshot.data()?.status !== expectedStatus) {
      throw new Error("Organization request retention lease or phase changed.");
    }
    transaction.update(jobReference, {
      status: nextStatus,
      updatedAt: Timestamp.fromMillis(nowMilliseconds),
    });
  });
}

async function completeRetentionJob(
  jobReference: DocumentReference,
  jobId: string,
  leaseId: string,
  job: RetentionJobDocument,
  nowMilliseconds: number
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const jobSnapshot = await transaction.get(jobReference);
    if (!jobSnapshot.exists
      || jobSnapshot.data()?.leaseId !== leaseId
      || jobSnapshot.data()?.status !== "firestoreDeleted") {
      throw new Error("Organization request retention completion state changed.");
    }

    const userReference = job.userId ? db.collection("users").doc(job.userId) : undefined;
    const userSnapshot = userReference ? await transaction.get(userReference) : undefined;
    const notificationId = jobId;
    if (userReference && userSnapshot?.exists) {
      transaction.set(userNotificationRef(job.userId!, notificationId), buildUserNotificationDocument({
        notificationId,
        targetUserId: job.userId!,
        type: "organizationRequestExpired",
        title: "Organization request deleted",
        message: `${job.organizationName} was deleted after 30 days without changes.`,
        sourceId: job.organizationId,
        dedupeKey: notificationId,
        metadata: {
          organizationName: job.organizationName,
          titleLocKey: "notifications.inbox.organization_expired.title",
          bodyLocKey: "notifications.inbox.organization_expired.body",
        },
      }));
    }

    transaction.set(db.collection("auditLogs").doc(jobId), buildAuditLog({
      actionType: "organizationRequestExpired",
      targetUserId: job.userId ?? "unknown",
      performedBy: "system",
      reason: "Unpublished organization request expired after 30 days without activity.",
      previousValue: {
        organizationId: job.organizationId,
        organizationName: job.organizationName,
        activityMilliseconds: job.activityMilliseconds,
      },
      newValue: {deleted: true, retentionJobId: jobId},
    }));
    transaction.update(jobReference, {
      status: "completed",
      leaseId: null,
      leaseExpiresAt: null,
      lastError: null,
      completedAt: Timestamp.fromMillis(nowMilliseconds),
      expiresAt: Timestamp.fromMillis(nowMilliseconds + completedJobRetentionMilliseconds),
      updatedAt: Timestamp.fromMillis(nowMilliseconds),
    });
  });
}

async function releaseRetentionJobLease(
  jobReference: DocumentReference,
  leaseId: string,
  error: unknown,
  nowMilliseconds: number
): Promise<void> {
  try {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(jobReference);
      if (!snapshot.exists || snapshot.data()?.leaseId !== leaseId) return;
      transaction.update(jobReference, {
        leaseId: null,
        leaseExpiresAt: null,
        lastError: retentionErrorMessage(error),
        updatedAt: Timestamp.fromMillis(nowMilliseconds),
      });
    });
  } catch (releaseError) {
    logger.error("Failed to release organization request retention lease.", {
      jobId: jobReference.id,
      error: retentionErrorMessage(releaseError),
    });
  }
}

function retentionJobDocument(data: DocumentData | undefined): RetentionJobDocument {
  const organizationId = typeof data?.organizationId === "string" ? data.organizationId : "";
  const organizationName = typeof data?.organizationName === "string"
    ? data.organizationName
    : "Organization";
  const userId = typeof data?.userId === "string" && data.userId.trim()
    ? data.userId.trim()
    : undefined;
  const activityMilliseconds = typeof data?.activityMilliseconds === "number"
    ? data.activityMilliseconds
    : Number.NaN;
  const status = data?.status as RetentionJobStatus | undefined;
  const validStatuses: readonly RetentionJobStatus[] = [
    ...resumableJobStatuses,
    "completed",
    "cancelled",
  ];
  if (!organizationId
    || !Number.isFinite(activityMilliseconds)
    || !status
    || !validStatuses.includes(status)) {
    throw new Error("Organization request retention job is invalid.");
  }
  return {organizationId, organizationName, userId, activityMilliseconds, status};
}

function retentionJobId(organizationId: string, activityMilliseconds: number): string {
  const identity = createHash("sha256")
    .update(`${organizationId}:${Math.trunc(activityMilliseconds)}`)
    .digest("hex")
    .slice(0, 40);
  return `organization-request-expired-${identity}`;
}

function retentionErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.slice(0, 500);
}
