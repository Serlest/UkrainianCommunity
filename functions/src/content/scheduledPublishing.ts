import {randomUUID} from "node:crypto";

import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {db} from "../firebase/admin";
import {isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {
  contentPlanningReceiptRetentionPolicy,
  contentPlanningRetentionExpiresAt,
} from "../contentPlanning/contentPlanningRetentionPolicy";

export type ScheduledCollection = "news" | "events";
export type ScheduledPublicationOutcome = "approved" | "pendingReview" | "skipped";
export type ScheduledCandidatePublisher = (
  collection: ScheduledCollection,
  documentId: string,
  now: Timestamp
) => Promise<ScheduledPublicationOutcome>;

export interface ScheduledCandidateDependencies {
  planningDraftLookup?: (
    collection: ScheduledCollection,
    contentId: string,
    authorId: string | undefined
  ) => Promise<DocumentReference | undefined>;
}

export interface ScheduledCollectionResult {
  found: number;
  published: number;
  review: number;
  skipped: number;
  failed: number;
}

export interface ScheduledMaintenanceResult {
  found: number;
  changed: number;
  skipped: number;
  failed: number;
}

export interface ScheduledPublishingCycleResult {
  expiredSchedulerLeases: ScheduledMaintenanceResult;
  expiredPlanningPublications: ScheduledMaintenanceResult;
  news: ScheduledCollectionResult;
  events: ScheduledCollectionResult;
}

const batchSize = 100;
const leaseCollection = "scheduledPublicationLeases";
const leaseDurationMilliseconds = 3 * 60 * 1000;
const planningTimestampToleranceMilliseconds = 1_000;
const planningRecoveryMessage =
  "Поле «Статус публікації»: попередня спроба не була завершена. Перевірте матеріал і повторіть публікацію.";
const planningMismatchMessage =
  "Поле «Статус публікації»: запланований матеріал більше не відповідає запису планування.";

export const publishScheduledContent = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Europe/Vienna",
    region: "europe-west3",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 3,
    maxInstances: 2,
    concurrency: 1,
  },
  async () => {
    const result = await runScheduledPublishingCycle();
    logger.info("Scheduled content publishing completed.", result);
    const failures = result.expiredSchedulerLeases.failed +
      result.expiredPlanningPublications.failed +
      result.news.failed +
      result.events.failed;
    if (failures > 0) {
      throw new Error(`Scheduled publishing completed with ${failures} failed operation(s).`);
    }
  }
);

export async function runScheduledPublishingCycle(
  now = Timestamp.now()
): Promise<ScheduledPublishingCycleResult> {
  const [expiredSchedulerLeases, expiredPlanningPublications] = await Promise.all([
    cleanupExpiredScheduledPublicationLeases(now),
    recoverExpiredPlanningPublications(now),
  ]);
  const [news, events] = await Promise.all([
    processScheduledCollection("news", now),
    processScheduledCollection("events", now),
  ]);
  return {
    expiredSchedulerLeases,
    expiredPlanningPublications,
    news,
    events,
  };
}

export async function processScheduledCollection(
  collection: ScheduledCollection,
  now = Timestamp.now()
): Promise<ScheduledCollectionResult> {
  let snapshot;
  try {
    snapshot = await db.collection(collection)
      .where("moderationStatus", "==", "draft")
      .where("scheduledAt", "<=", now)
      .orderBy("scheduledAt", "asc")
      .limit(batchSize)
      .get();
  } catch (error) {
    logger.error("Scheduled content query failed.", {collection, error});
    return {found: 0, published: 0, review: 0, skipped: 0, failed: 1};
  }

  const result = await processScheduledCandidateIds(
    collection,
    snapshot.docs.map((document) => document.id),
    now
  );
  return {found: snapshot.size, ...result};
}

export async function processScheduledCandidateIds(
  collection: ScheduledCollection,
  documentIds: string[],
  now: Timestamp,
  publish: ScheduledCandidatePublisher = publishScheduledCandidate
): Promise<Omit<ScheduledCollectionResult, "found">> {
  const result = {published: 0, review: 0, skipped: 0, failed: 0};
  for (const documentId of documentIds) {
    try {
      const outcome = await publish(collection, documentId, now);
      if (outcome === "approved") result.published += 1;
      else if (outcome === "pendingReview") result.review += 1;
      else result.skipped += 1;
    } catch (error) {
      result.failed += 1;
      logger.error("Scheduled content candidate failed.", {
        collection,
        documentId,
        error,
      });
    }
  }
  return result;
}

interface CandidateClaim {
  leaseId: string;
  authorId: string | undefined;
  scheduledAt: Timestamp;
}

export async function publishScheduledCandidate(
  collection: ScheduledCollection,
  documentId: string,
  now = Timestamp.now(),
  dependencies: ScheduledCandidateDependencies = {}
): Promise<ScheduledPublicationOutcome> {
  const reference = db.collection(collection).doc(documentId);
  const leaseReference = db.collection(leaseCollection).doc(`${collection}_${documentId}`);
  let claim: CandidateClaim | undefined;
  try {
    claim = await claimCandidate(reference, leaseReference, collection, documentId, now);
    if (!claim) return "skipped";
    const planningDraftLookup = dependencies.planningDraftLookup ?? linkedPlanningDraft;
    const planningReference = await planningDraftLookup(
      collection,
      documentId,
      claim.authorId
    );
    return await finalizeClaimedCandidate({
      collection,
      documentId,
      reference,
      leaseReference,
      leaseId: claim.leaseId,
      planningReference,
      scheduledAt: claim.scheduledAt,
      now,
    });
  } catch (error) {
    if (claim) {
      try {
        await releaseCandidateLease(leaseReference, claim.leaseId);
      } catch (releaseError) {
        logger.error("Scheduled publication lease release failed.", {
          collection,
          documentId,
          leaseId: claim.leaseId,
          releaseError,
        });
      }
    }
    throw error;
  }
}

async function claimCandidate(
  reference: DocumentReference,
  leaseReference: DocumentReference,
  collection: ScheduledCollection,
  documentId: string,
  now: Timestamp
): Promise<CandidateClaim | undefined> {
  return db.runTransaction(async (transaction) => {
    const [candidate, existingLease] = await Promise.all([
      transaction.get(reference),
      transaction.get(leaseReference),
    ]);
    const existingExpiry = existingLease.get("expiresAt");
    const data = candidate.data();
    if (!candidate.exists || !isScheduledCandidateClaimable(data, existingExpiry, now)) {
      return undefined;
    }
    const scheduledAt = data?.scheduledAt as Timestamp;
    const leaseId = randomUUID();
    transaction.set(leaseReference, {
      leaseId,
      collection,
      documentId,
      scheduledAt,
      claimedAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + leaseDurationMilliseconds),
    });
    return {leaseId, scheduledAt, authorId: stringValue(data?.authorId)};
  });
}

interface ClaimedCandidate {
  collection: ScheduledCollection;
  documentId: string;
  reference: DocumentReference;
  leaseReference: DocumentReference;
  leaseId: string;
  planningReference: DocumentReference | undefined;
  scheduledAt: Timestamp;
  now: Timestamp;
}

async function finalizeClaimedCandidate(
  input: ClaimedCandidate
): Promise<ScheduledPublicationOutcome> {
  return db.runTransaction(async (transaction) => {
    const [candidate, lease] = await Promise.all([
      transaction.get(input.reference),
      transaction.get(input.leaseReference),
    ]);
    if (!isOwnedSchedulerLease(lease, input)) return "skipped";
    const data = candidate.data();
    const scheduledAt = data?.scheduledAt;
    if (!candidate.exists || !data || data.moderationStatus !== "draft" ||
        !(scheduledAt instanceof Timestamp) || scheduledAt.toMillis() > input.now.toMillis() ||
        scheduledAt.toMillis() !== input.scheduledAt.toMillis()) {
      transaction.delete(input.leaseReference);
      return "skipped";
    }

    const planning = input.planningReference
      ? await transaction.get(input.planningReference)
      : undefined;
    if (planning && (!planning.exists || !isCurrentScheduledPlanningLink(
      planning.data(),
      input.collection,
      input.documentId,
      scheduledAt
    ))) {
      if (planning.exists && isActivePlanningPublication(planning.data(), input.now)) {
        transaction.delete(input.leaseReference);
        return "skipped";
      }
      applyPlanningMismatch(transaction, input, planning);
      return "skipped";
    }

    const authorId = stringValue(data.authorId);
    const organizationId = stringValue(data.organizationId);
    if (!authorId || !organizationId ||
        !isDocumentId(authorId) || !isDocumentId(organizationId)) {
      applyReviewOutcome(
        transaction,
        input,
        "Поле «Статус публікації»: не вказано автора або організацію."
      );
      return "pendingReview";
    }

    const [user, organization] = await Promise.all([
      transaction.get(db.collection("users").doc(authorId)),
      transaction.get(db.collection("organizations").doc(organizationId)),
    ]);
    const permissions = userPermissionSnapshotFromData(authorId, user.data());
    const organizationData = organization.data() ?? {};
    const isAppOwner = permissions.globalRole === "owner";
    const canPublishForOrganization = isAppOwner || hasOrganizationRole(organizationData, authorId);
    if (!user.exists || !isActiveUser(permissions) || !organization.exists ||
        !canPublishForOrganization || organizationData.moderationStatus !== "approved") {
      applyReviewOutcome(
        transaction,
        input,
        "Поле «Статус публікації»: перевірте права або статус організації."
      );
      return "pendingReview";
    }

    if (await hasExactDuplicateInTransaction(
      transaction,
      input.collection,
      input.documentId,
      data
    )) {
      applyReviewOutcome(
        transaction,
        input,
        "Поле «Статус публікації»: знайдено можливий дублікат."
      );
      return "pendingReview";
    }

    const nextStatus = input.collection === "news" && data.regionScope === "austria" && !isAppOwner
      ? "pendingReview"
      : "approved";
    transaction.update(input.reference, {
      moderationStatus: nextStatus,
      publishedAt: input.collection === "news" ? input.now : data.publishedAt ?? FieldValue.delete(),
      scheduledAt: FieldValue.delete(),
      updatedAt: input.now,
    });
    if (input.planningReference) {
      if (nextStatus === "approved") {
        transaction.update(input.planningReference, completedPlanningUpdate({
          now: input.now,
          outcome: "approved",
          contentId: input.documentId,
          kind: input.collection === "news" ? "news" : "event",
          organizationId,
          organizationName: stringValue(data.organizationName),
        }));
      } else {
        transaction.update(input.planningReference, attentionUpdate(
          "Поле «Статус публікації»: матеріал передано на модерацію замість автоматичної публікації.",
          input.now
        ));
      }
    }
    transaction.delete(input.leaseReference);
    return nextStatus;
  });
}

export async function cleanupExpiredScheduledPublicationLeases(
  now = Timestamp.now()
): Promise<ScheduledMaintenanceResult> {
  let snapshot;
  try {
    snapshot = await db.collection(leaseCollection)
      .where("expiresAt", "<=", now)
      .orderBy("expiresAt", "asc")
      .limit(batchSize)
      .get();
  } catch (error) {
    logger.error("Expired scheduled publication lease query failed.", {error});
    return {found: 0, changed: 0, skipped: 0, failed: 1};
  }

  let changed = 0;
  let skipped = 0;
  let failed = 0;
  for (const document of snapshot.docs) {
    try {
      const removed = await db.runTransaction(async (transaction) => {
        const current = await transaction.get(document.ref);
        const expiresAt = current.get("expiresAt");
        if (!current.exists || !(expiresAt instanceof Timestamp) ||
            expiresAt.toMillis() > now.toMillis()) {
          return false;
        }
        transaction.delete(document.ref);
        return true;
      });
      if (removed) changed += 1;
      else skipped += 1;
    } catch (error) {
      failed += 1;
      logger.error("Expired scheduled publication lease cleanup failed.", {
        leasePath: document.ref.path,
        error,
      });
    }
  }
  return {found: snapshot.size, changed, skipped, failed};
}

export async function recoverExpiredPlanningPublications(
  now = Timestamp.now()
): Promise<ScheduledMaintenanceResult> {
  let snapshot;
  try {
    snapshot = await db.collectionGroup("contentPlanningDrafts")
      .where("state", "==", "publishing")
      .where("publicationLeaseExpiresAt", "<=", now)
      .orderBy("publicationLeaseExpiresAt", "asc")
      .limit(batchSize)
      .get();
  } catch (error) {
    logger.error("Publishing planning record query failed.", {error});
    return {found: 0, changed: 0, skipped: 0, failed: 1};
  }

  let changed = 0;
  let skipped = 0;
  let failed = 0;
  for (const document of snapshot.docs) {
    if (isActivePlanningPublication(document.data(), now)) {
      skipped += 1;
      continue;
    }
    try {
      const outcome = await recoverExpiredPlanningPublication(document.ref, now);
      if (outcome === "changed") changed += 1;
      else skipped += 1;
    } catch (error) {
      failed += 1;
      logger.error("Publishing planning record recovery failed.", {
        planningPath: document.ref.path,
        error,
      });
    }
  }
  return {found: snapshot.size, changed, skipped, failed};
}

async function recoverExpiredPlanningPublication(
  planningReference: DocumentReference,
  now: Timestamp
): Promise<"changed" | "skipped"> {
  return db.runTransaction(async (transaction) => {
    const planning = await transaction.get(planningReference);
    const data = planning.data();
    if (!planning.exists || !data || data.state !== "publishing" ||
        isActivePlanningPublication(data, now)) {
      return "skipped";
    }

    const kind = data.publishedContentKind === "news" || data.publishedContentKind === "event"
      ? data.publishedContentKind
      : data.kind === "news" || data.kind === "event" ? data.kind : undefined;
    const contentId = stringValue(data.publishedContentId);
    const ownerUserId = planningReference.parent.parent?.id;
    const collection = kind === "news" ? "news" : kind === "event" ? "events" : undefined;
    const contentReference = collection && contentId && isDocumentId(contentId)
      ? db.collection(collection).doc(contentId)
      : undefined;
    const content = contentReference
      ? await transaction.get(contentReference)
      : undefined;
    const contentData = content?.data();
    const moderationStatus = stringValue(contentData?.moderationStatus);
    const ownsContent = Boolean(
      content?.exists && ownerUserId && stringValue(contentData?.authorId) === ownerUserId
    );

    if (ownsContent && contentId && kind &&
        (moderationStatus === "approved" || moderationStatus === "pendingReview")) {
      transaction.update(planningReference, completedPlanningUpdate({
        now,
        outcome: moderationStatus,
        contentId,
        kind,
        organizationId: stringValue(contentData?.organizationId),
        organizationName: stringValue(contentData?.organizationName),
      }));
      return "changed";
    }

    if (ownsContent && contentReference && moderationStatus === "draft") {
      transaction.update(contentReference, {
        scheduledAt: FieldValue.delete(),
        updatedAt: now,
      });
    }
    transaction.update(planningReference, attentionUpdate(planningRecoveryMessage, now));
    return "changed";
  });
}

export function isScheduledCandidateClaimable(
  data: DocumentData | undefined,
  existingLeaseExpiresAt: unknown,
  now: Timestamp
): boolean {
  if (!data || data.moderationStatus !== "draft") return false;
  const scheduledAt = data.scheduledAt;
  if (!(scheduledAt instanceof Timestamp) || scheduledAt.toMillis() > now.toMillis()) return false;
  return !(existingLeaseExpiresAt instanceof Timestamp &&
    existingLeaseExpiresAt.toMillis() > now.toMillis());
}

export function isCurrentScheduledPlanningLink(
  data: DocumentData | undefined,
  collection: ScheduledCollection,
  documentId: string,
  contentScheduledAt: Timestamp
): boolean {
  const planningScheduledAt = data?.scheduledAt;
  return data?.state === "scheduled" &&
    data.publishedContentId === documentId &&
    data.publishedContentKind === (collection === "news" ? "news" : "event") &&
    planningScheduledAt instanceof Timestamp &&
    Math.abs(planningScheduledAt.toMillis() - contentScheduledAt.toMillis()) <=
      planningTimestampToleranceMilliseconds;
}

export function isActivePlanningPublication(
  data: DocumentData | undefined,
  now: Timestamp
): boolean {
  const expiresAt = data?.publicationLeaseExpiresAt;
  return data?.state === "publishing" &&
    typeof data.publicationLeaseId === "string" &&
    data.publicationLeaseId.length > 0 &&
    expiresAt instanceof Timestamp &&
    expiresAt.toMillis() > now.toMillis();
}

function isOwnedSchedulerLease(
  lease: DocumentSnapshot,
  input: ClaimedCandidate
): boolean {
  return lease.exists &&
    lease.get("leaseId") === input.leaseId &&
    lease.get("collection") === input.collection &&
    lease.get("documentId") === input.documentId;
}

async function releaseCandidateLease(
  leaseReference: DocumentReference,
  leaseId: string
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const lease = await transaction.get(leaseReference);
    if (lease.exists && lease.get("leaseId") === leaseId) {
      transaction.delete(leaseReference);
    }
  });
}

function applyPlanningMismatch(
  transaction: Transaction,
  input: ClaimedCandidate,
  planning: DocumentSnapshot
): void {
  transaction.update(input.reference, {
    scheduledAt: FieldValue.delete(),
    updatedAt: input.now,
  });
  const state = planning.get("state");
  if (planning.exists && state !== "completed" && state !== "archived") {
    transaction.update(planning.ref, attentionUpdate(planningMismatchMessage, input.now));
  }
  transaction.delete(input.leaseReference);
}

function applyReviewOutcome(
  transaction: Transaction,
  input: ClaimedCandidate,
  message: string
): void {
  transaction.update(input.reference, {
    moderationStatus: "pendingReview",
    scheduledAt: FieldValue.delete(),
    updatedAt: input.now,
  });
  if (input.planningReference) {
    transaction.update(input.planningReference, attentionUpdate(message, input.now));
  }
  transaction.delete(input.leaseReference);
}

async function linkedPlanningDraft(
  collection: ScheduledCollection,
  contentId: string,
  authorId: string | undefined
): Promise<DocumentReference | undefined> {
  const kind = collection === "news" ? "news" : "event";
  const snapshot = await db.collectionGroup("contentPlanningDrafts")
    .where("publishedContentId", "==", contentId)
    .limit(10)
    .get();
  const matchingKind = snapshot.docs.filter((draft) => draft.get("publishedContentKind") === kind);
  const matchingOwner = authorId
    ? matchingKind.filter((draft) => draft.ref.parent.parent?.id === authorId)
    : [];
  const candidates = matchingOwner.length > 0 ? matchingOwner : matchingKind;
  return candidates.find((draft) => draft.get("state") === "scheduled")?.ref ??
    candidates.find((draft) => draft.get("state") === "publishing")?.ref ??
    candidates[0]?.ref;
}

interface CompletedPlanningInput {
  now: Timestamp;
  outcome: "approved" | "pendingReview";
  contentId: string;
  kind: "news" | "event";
  organizationId: string | undefined;
  organizationName: string | undefined;
}

export function completedPlanningUpdate(input: CompletedPlanningInput): DocumentData {
  return {
    state: "completed",
    scheduledAt: null,
    completedAt: input.now,
    publicationOutcome: input.outcome,
    publishedContentId: input.contentId,
    publishedContentKind: input.kind,
    publishedOrganizationId: input.organizationId ?? null,
    publishedOrganizationName: input.organizationName ?? null,
    retentionPolicy: contentPlanningReceiptRetentionPolicy,
    retentionExpiresAt: contentPlanningRetentionExpiresAt(input.now),
    draftMediaCleanupStatus: "pending",
    draftMediaCleanupRequestedAt: input.now,
    failureMessage: null,
    publicationAttemptId: FieldValue.delete(),
    publicationLeaseId: FieldValue.delete(),
    publicationLeaseExpiresAt: FieldValue.delete(),
    updatedAt: input.now,
  };
}

function attentionUpdate(message: string, now: Timestamp): DocumentData {
  return {
    state: "needsAttention",
    scheduledAt: null,
    missingFields: [message],
    failureMessage: message,
    publicationAttemptId: FieldValue.delete(),
    publicationLeaseId: FieldValue.delete(),
    publicationLeaseExpiresAt: FieldValue.delete(),
    updatedAt: now,
  };
}

async function hasExactDuplicateInTransaction(
  transaction: Transaction,
  collection: ScheduledCollection,
  documentId: string,
  data: DocumentData
): Promise<boolean> {
  if (collection === "news") {
    const sourceURL = stringValue(data.sourceURL);
    if (!sourceURL) return false;
    const matches = await transaction.get(
      db.collection("news").where("sourceURL", "==", sourceURL).limit(10)
    );
    return matches.docs.some((item) => item.id !== documentId &&
      ["approved", "pendingReview"].includes(item.get("moderationStatus")));
  }

  const startDate = data.startDate;
  if (!(startDate instanceof Timestamp)) return false;
  const normalizedTitle = normalizeText(stringValue(data.title));
  const organizationId = stringValue(data.organizationId);
  const matches = await transaction.get(
    db.collection("events").where("startDate", "==", startDate).limit(20)
  );
  return matches.docs.some((item) => item.id !== documentId &&
    ["approved", "pendingReview"].includes(item.get("moderationStatus")) &&
    stringValue(item.get("organizationId")) === organizationId &&
    normalizeText(stringValue(item.get("title"))) === normalizedTitle);
}

function hasOrganizationRole(data: DocumentData, userId: string): boolean {
  if (stringValue(data.ownerId) === userId) return true;
  for (const field of ["adminIds", "moderatorIds"] as const) {
    const values = Array.isArray(data[field]) ? data[field] : [];
    if (values.includes(userId)) return true;
  }
  return false;
}

function isDocumentId(value: string): boolean {
  return value.length > 0 && !value.includes("/");
}

function normalizeText(value: string | undefined): string {
  return (value ?? "").trim().toLocaleLowerCase("uk-UA").replace(/\s+/g, " ");
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}
