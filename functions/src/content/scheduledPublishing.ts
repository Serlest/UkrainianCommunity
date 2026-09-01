import {randomUUID} from "node:crypto";

import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Transaction,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {db} from "../firebase/admin";
import {isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";

type ScheduledCollection = "news" | "events";

const batchSize = 100;
const leaseCollection = "scheduledPublicationLeases";
const leaseDurationMilliseconds = 3 * 60 * 1000;

export const publishScheduledContent = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Europe/Vienna",
    region: "europe-west3",
    timeoutSeconds: 120,
    memory: "256MiB",
    retryCount: 3,
  },
  async () => {
    const now = Timestamp.now();
    const results = await Promise.all([
      processScheduledCollection("news", now),
      processScheduledCollection("events", now),
    ]);
    logger.info("Scheduled content publishing completed.", {
      news: results[0],
      events: results[1],
    });
  }
);

async function processScheduledCollection(collection: ScheduledCollection, now: Timestamp) {
  const snapshot = await db.collection(collection)
    .where("scheduledAt", "<=", now)
    .orderBy("scheduledAt", "asc")
    .limit(batchSize)
    .get();

  let published = 0;
  let review = 0;
  let skipped = 0;
  for (const document of snapshot.docs) {
    const outcome = await publishCandidate(collection, document.id, now);
    if (outcome === "approved") published += 1;
    else if (outcome === "pendingReview") review += 1;
    else skipped += 1;
  }
  return {published, review, skipped};
}

async function publishCandidate(
  collection: ScheduledCollection,
  documentId: string,
  now: Timestamp
): Promise<"approved" | "pendingReview" | "skipped"> {
  const reference = db.collection(collection).doc(documentId);
  const leaseReference = db.collection(leaseCollection).doc(`${collection}_${documentId}`);
  const leaseId = await claimCandidate(reference, leaseReference, collection, documentId, now);
  if (!leaseId) return "skipped";
  const planningReference = await linkedPlanningDraft(collection, documentId);
  return finalizeClaimedCandidate({
    collection,
    documentId,
    reference,
    leaseReference,
    leaseId,
    planningReference,
    now,
  });
}

async function claimCandidate(
  reference: DocumentReference,
  leaseReference: DocumentReference,
  collection: ScheduledCollection,
  documentId: string,
  now: Timestamp
): Promise<string | undefined> {
  return db.runTransaction(async (transaction) => {
    const [candidate, existingLease] = await Promise.all([
      transaction.get(reference),
      transaction.get(leaseReference),
    ]);
    const existingExpiry = existingLease.get("expiresAt");
    const data = candidate.data();
    if (!candidate.exists || !isScheduledCandidateClaimable(data, existingExpiry, now)) return undefined;
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
    return leaseId;
  });
}

interface ClaimedCandidate {
  collection: ScheduledCollection;
  documentId: string;
  reference: DocumentReference;
  leaseReference: DocumentReference;
  leaseId: string;
  planningReference: DocumentReference | undefined;
  now: Timestamp;
}

async function finalizeClaimedCandidate(input: ClaimedCandidate): Promise<"approved" | "pendingReview" | "skipped"> {
  return db.runTransaction(async (transaction) => {
    const [candidate, lease] = await Promise.all([
      transaction.get(input.reference),
      transaction.get(input.leaseReference),
    ]);
    if (!lease.exists || lease.get("leaseId") !== input.leaseId) return "skipped";
    const data = candidate.data();
    const scheduledAt = data?.scheduledAt;
    if (!candidate.exists || !data || data.moderationStatus !== "draft" ||
        !(scheduledAt instanceof Timestamp) || scheduledAt.toMillis() > input.now.toMillis()) {
      transaction.delete(input.leaseReference);
      return "skipped";
    }

    const planning = input.planningReference
      ? await transaction.get(input.planningReference)
      : undefined;
    if (planning && (!planning.exists || !isCurrentScheduledPlanningLink(
      planning.data(),
      input.collection,
      input.documentId
    ))) {
      transaction.delete(input.leaseReference);
      return "skipped";
    }

    const authorId = stringValue(data.authorId);
    const organizationId = stringValue(data.organizationId);
    if (!authorId || !organizationId) {
      applyReviewOutcome(transaction, input, "Поле «Статус публікації»: не вказано автора або організацію.");
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
      applyReviewOutcome(transaction, input, "Поле «Статус публікації»: перевірте права або статус організації.");
      return "pendingReview";
    }

    if (await hasExactDuplicateInTransaction(
      transaction,
      input.collection,
      input.documentId,
      data
    )) {
      applyReviewOutcome(transaction, input, "Поле «Статус публікації»: знайдено можливий дублікат.");
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
        transaction.update(input.planningReference, {
          state: "completed",
          completedAt: input.now,
          publicationOutcome: "approved",
          publishedContentId: input.documentId,
          publishedContentKind: input.collection === "news" ? "news" : "event",
          publishedOrganizationId: organizationId,
          publishedOrganizationName: stringValue(data.organizationName) ?? null,
          failureMessage: null,
          updatedAt: input.now,
        });
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
  documentId: string
): boolean {
  return data?.state === "scheduled" &&
    data.publishedContentId === documentId &&
    data.publishedContentKind === (collection === "news" ? "news" : "event");
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
  contentId: string
): Promise<DocumentReference | undefined> {
  const kind = collection === "news" ? "news" : "event";
  const snapshot = await db.collectionGroup("contentPlanningDrafts")
    .where("publishedContentId", "==", contentId)
    .limit(5)
    .get();
  return snapshot.docs.find((draft) => draft.get("publishedContentKind") === kind)?.ref;
}

function attentionUpdate(message: string, now: Timestamp): DocumentData {
  return {
    state: "needsAttention",
    missingFields: [message],
    failureMessage: message,
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

function normalizeText(value: string | undefined): string {
  return (value ?? "").trim().toLocaleLowerCase("uk-UA").replace(/\s+/g, " ");
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}
