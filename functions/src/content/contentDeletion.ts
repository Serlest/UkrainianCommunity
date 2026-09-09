import {CheckedBulkWriter} from "../firebase/checkedBulkWriter";
import {
  FieldPath,
  FieldValue,
  Timestamp,
  type DocumentData,
  type Query,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireLegacyCallableUser as requireVerifiedActiveUser} from "../auth/legacyCallableContext";
import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {adminStorage, db} from "../firebase/admin";
import {getOrganizationRoles} from "../permissions/organizationPermissions";
import {isOwner} from "../permissions/userPermissions";
import {
  writeUserNotification,
} from "../notifications/notificationPayloads";
import {
  type ContentKind,
  contentReferencePoliciesFor,
  contentStoragePrefixes,
  canDiscardOrganizationRequest,
  eventBlocksOrganizationDeletion,
  featuredBannerActionType,
  normalizedResourceId,
  organizationStoragePrefix,
  referenceDataMatchesPolicy,
} from "./contentDeletionPolicy";

interface DeletionResponse {
  status: "deleted" | "alreadyDeleted";
  deletedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  timeoutSeconds: 300,
  memory: "512MiB" as const,
  maxInstances: 10,
  enforceAppCheck: false,
};

const relatedBatchSize = 400;
const organizationContentBatchSize = 100;
const systemOrganizationId = "ukrainian-community";
export const organizationDeletionOperationCollection = "organizationDeletionOperations";
const organizationDeletionOperationRetentionMilliseconds = 7 * 24 * 60 * 60 * 1_000;

type OrganizationDeletionRecipientRole =
  | "communityOwner"
  | "communityAdmin"
  | "communityModerator";

interface OrganizationDeletionRecipient {
  userId: string;
  role: OrganizationDeletionRecipientRole;
}

export interface OrganizationDeletionNotificationPlan {
  organizationId: string;
  organizationName: string;
  organizationExisted: boolean;
  actorUserId: string;
  recipients: OrganizationDeletionRecipient[];
  localeHint?: string;
}

export const deleteNews = onCall(
  callableOptions,
  async (request): Promise<DeletionResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const actor = auth.permissions;
    const newsId = requestResourceId(request.data, "newsId");
    const newsReference = db.collection("news").doc(newsId);
    const newsSnapshot = await newsReference.get();

    if (!newsSnapshot.exists && !isOwner(actor)) {
      throw new HttpsError("not-found", "News post does not exist.");
    }
    if (newsSnapshot.exists) {
      await assertCanDeleteOrganizationContent(actor.uid, newsSnapshot.data(), isOwner(actor));
    }

    await deleteNewsContent(newsId, newsSnapshot.data());
    const deletedAt = new Date().toISOString();
    logger.info("News content deletion completed.", {newsId, actorUserId: auth.uid});

    return {
      status: newsSnapshot.exists ? "deleted" : "alreadyDeleted",
      deletedAt,
    };
  }
);

export const deleteOrganization = onCall(
  callableOptions,
  async (request): Promise<DeletionResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const actor = auth.permissions;
    const organizationId = requestResourceId(request.data, "organizationId");
    if (organizationId === systemOrganizationId) {
      throw new HttpsError("failed-precondition", "The system organization cannot be deleted.");
    }

    const organizationReference = db.collection("organizations").doc(organizationId);
    let organizationExisted: boolean;
    let notificationPlan: OrganizationDeletionNotificationPlan | undefined;
    await preflightOrganizationDeletionHistory(organizationId);
    if (isOwner(actor)) {
      await assertOrganizationHasNoBlockingEvents(organizationId);
      notificationPlan = await prepareOrganizationDeletionNotificationPlan(
        organizationId,
        auth.uid
      );
      organizationExisted = notificationPlan.organizationExisted;
      await deleteOrganizationContent(organizationId, organizationExisted);
    } else {
      organizationExisted = await discardUnpublishedOrganizationRequest(
        organizationId,
        auth.uid
      );
      await deleteStoragePrefix(organizationStoragePrefix(organizationId));
      await db.recursiveDelete(organizationReference);
    }
    await deleteOrganizationHistoryReferences(organizationId);
    if (notificationPlan) {
      await completeOrganizationDeletionNotifications(notificationPlan);
    }
    const deletedAt = new Date().toISOString();
    logger.info("Organization deletion completed.", {
      organizationId,
      actorUserId: auth.uid,
    });

    return {
      status: organizationExisted ? "deleted" : "alreadyDeleted",
      deletedAt,
    };
  }
);

export async function discardUnpublishedOrganizationRequest(
  organizationId: string,
  actorUserId: string
): Promise<boolean> {
  const organizationReference = db.collection("organizations").doc(organizationId);
  return db.runTransaction(async (transaction) => {
    const organizationSnapshot = await transaction.get(organizationReference);
    if (!organizationSnapshot.exists) {
      return false;
    }
    if (!canDiscardOrganizationRequest(actorUserId, organizationSnapshot.data())) {
      throw new HttpsError(
        "permission-denied",
        "Only the submitter of an unpublished request may discard it."
      );
    }

    const organization = organizationSnapshot.data() ?? {};
    transaction.set(auditLogRef(), buildAuditLog({
      actionType: "organizationRequestDiscarded",
      targetUserId: actorUserId,
      performedBy: actorUserId,
      reason: "Organization request discarded by its submitter.",
      previousValue: {
        organizationId,
        moderationStatus: organization.moderationStatus ?? null,
        organizationName: organization.name ?? null,
      },
      newValue: {deleted: true},
    }));
    transaction.delete(db.collection("organizationCreationProofs").doc(organizationId));
    transaction.delete(organizationReference);
    return true;
  });
}

/**
 * Persists the role recipients before the organization document is removed.
 * A callable retry can therefore finish deterministic notifications even when
 * the Firestore deletion succeeded before the first invocation returned.
 */
export async function prepareOrganizationDeletionNotificationPlan(
  organizationId: string,
  actorUserId: string
): Promise<OrganizationDeletionNotificationPlan> {
  const operationReference = db.collection(organizationDeletionOperationCollection)
    .doc(organizationId);
  const organizationReference = db.collection("organizations").doc(organizationId);

  return db.runTransaction(async (transaction) => {
    const [operationSnapshot, organizationSnapshot] = await transaction.getAll(
      operationReference,
      organizationReference
    );
    if (operationSnapshot.exists && !organizationSnapshot.exists) {
      return organizationDeletionNotificationPlanFromData(
        organizationId,
        operationSnapshot.data()
      );
    }

    const organization = organizationSnapshot.data() ?? {};
    const plan: OrganizationDeletionNotificationPlan = {
      organizationId,
      organizationName: nonEmptyString(organization.name) ?? "Organization",
      organizationExisted: organizationSnapshot.exists,
      actorUserId,
      recipients: organizationDeletionRecipients(organization),
    };
    transaction.set(operationReference, {
      ...plan,
      status: "prepared",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        Date.now() + organizationDeletionOperationRetentionMilliseconds
      ),
    });
    return plan;
  });
}

export async function completeOrganizationDeletionNotifications(
  plan: OrganizationDeletionNotificationPlan
): Promise<void> {
  await Promise.all(plan.recipients.map(async (recipient) => {
    const user = await db.collection("users").doc(recipient.userId).get();
    const copy = organizationDeletionNotificationCopy(
      plan.organizationName,
      user.data(),
      plan.localeHint
    );
    await writeUserNotification({
      notificationId: organizationDeletionNotificationId(
        plan.organizationId,
        recipient.userId
      ),
      targetUserId: recipient.userId,
      type: "organizationRoleRemoved",
      title: copy.title,
      message: copy.message,
      severity: "info",
      actionType: "none",
      requiresPopup: false,
      actorUserId: plan.actorUserId,
      sourceType: "organization",
      sourceId: plan.organizationId,
      metadata: {
        organizationId: plan.organizationId,
        organizationName: plan.organizationName,
        previousRole: recipient.role,
        newRole: "none",
        reason: copy.message,
        reasonCode: "organizationDeleted",
      },
      dedupeKey: `organizationDeleted:${plan.organizationId}:${recipient.userId}`,
    });
  }));

  await db.collection(organizationDeletionOperationCollection)
    .doc(plan.organizationId)
    .delete();
}

function organizationDeletionNotificationCopy(
  organizationName: string,
  user: DocumentData | undefined,
  localeHint?: string
): {title: string; message: string} {
  const locale = [
    user?.appLanguage,
    user?.language,
    user?.locale,
    user?.preferredLanguage,
    localeHint,
  ]
    .find((value) => typeof value === "string" && value.trim().length > 0);
  if (typeof locale === "string" && locale.toLowerCase().startsWith("de")) {
    return {
      title: "Organisation gelöscht",
      message: `${organizationName} wurde gelöscht. Ihre Organisationsrolle wurde entfernt.`,
    };
  }
  return {
    title: "Організацію видалено",
    message: `${organizationName} видалено. Вашу роль в організації скасовано.`,
  };
}

/**
 * One-time maintenance entry point for a deletion completed before recipient
 * snapshots existed. The retained, unexpired creation proof is the required
 * evidence tying the deleted organization to its original owner.
 */
export async function repairDeletedOrganizationLifecycleFromCreationProof(
  organizationId: string,
  actorUserId: string
): Promise<void> {
  const operationReference = db.collection(organizationDeletionOperationCollection)
    .doc(organizationId);
  const organizationReference = db.collection("organizations").doc(organizationId);
  const proofReference = db.collection("organizationCreationProofs").doc(organizationId);
  const plan = await db.runTransaction(async (transaction) => {
    const [organizationSnapshot, proofSnapshot, operationSnapshot] =
      await transaction.getAll(
        organizationReference,
        proofReference,
        operationReference
      );
    if (organizationSnapshot.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Historical repair requires an already deleted organization."
      );
    }
    if (operationSnapshot.exists) {
      return organizationDeletionNotificationPlanFromData(
        organizationId,
        operationSnapshot.data()
      );
    }

    const proof = proofSnapshot.data();
    const proofUserId = nonEmptyString(proof?.userId);
    const proofOrganizationId = nonEmptyString(proof?.organizationId);
    const proofExpiresAt = proof?.expiresAt;
    if (!proofSnapshot.exists
      || !proofUserId
      || proofOrganizationId !== organizationId
      || !(proofExpiresAt instanceof Timestamp)
      || proofExpiresAt.toMillis() <= Date.now()) {
      throw new HttpsError(
        "failed-precondition",
        "A matching unexpired organization creation proof is required."
      );
    }

    const repairPlan: OrganizationDeletionNotificationPlan = {
      organizationId,
      organizationName: nonEmptyString(proof?.organizationName) ?? "Organization",
      organizationExisted: true,
      actorUserId,
      recipients: [{userId: proofUserId, role: "communityOwner"}],
      localeHint: nonEmptyString(proof?.locale),
    };
    transaction.create(operationReference, {
      ...repairPlan,
      status: "preparedHistoricalRepair",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(
        Date.now() + organizationDeletionOperationRetentionMilliseconds
      ),
    });
    return repairPlan;
  });

  await deleteOrganizationHistoryReferences(organizationId);
  await completeOrganizationDeletionNotifications(plan);
}

function organizationDeletionNotificationId(
  organizationId: string,
  userId: string
): string {
  return `organizationDeleted_${organizationId}_${userId}`;
}

function organizationDeletionRecipients(data: DocumentData): OrganizationDeletionRecipient[] {
  const recipients = new Map<string, OrganizationDeletionRecipientRole>();
  const add = (value: unknown, role: OrganizationDeletionRecipientRole): void => {
    const userId = nonEmptyString(value);
    if (userId && !recipients.has(userId)) recipients.set(userId, role);
  };

  add(data.ownerId, "communityOwner");
  for (const userId of stringArray(data.adminIds)) add(userId, "communityAdmin");
  for (const userId of stringArray(data.moderatorIds)) add(userId, "communityModerator");
  return Array.from(recipients, ([userId, role]) => ({userId, role}));
}

function organizationDeletionNotificationPlanFromData(
  organizationId: string,
  data: DocumentData | undefined
): OrganizationDeletionNotificationPlan {
  const recipients = Array.isArray(data?.recipients) ? data.recipients.flatMap((value) => {
    if (!isRecord(value)) return [];
    const userId = nonEmptyString(value.userId);
    const role = value.role;
    if (!userId || !isOrganizationDeletionRecipientRole(role)) return [];
    return [{userId, role}];
  }) : [];
  return {
    organizationId,
    organizationName: nonEmptyString(data?.organizationName) ?? "Organization",
    organizationExisted: data?.organizationExisted === true,
    actorUserId: nonEmptyString(data?.actorUserId) ?? "system",
    recipients,
    localeHint: nonEmptyString(data?.localeHint),
  };
}

function isOrganizationDeletionRecipientRole(
  value: unknown
): value is OrganizationDeletionRecipientRole {
  return value === "communityOwner"
    || value === "communityAdmin"
    || value === "communityModerator";
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.flatMap((entry) => {
    const normalized = nonEmptyString(entry);
    return normalized ? [normalized] : [];
  }) : [];
}

function nonEmptyString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

export async function deleteNewsContent(
  newsId: string,
  knownData?: DocumentData
): Promise<void> {
  await deleteContentDocument("news", newsId, knownData);
}

export async function deleteEventContent(
  eventId: string,
  knownData?: DocumentData
): Promise<void> {
  await deleteContentDocument("events", eventId, knownData);
}

async function deleteContentDocument(
  kind: ContentKind,
  contentIdValue: string,
  knownData?: DocumentData
): Promise<void> {
  const contentId = safeResourceId(contentIdValue, "contentId");
  const reference = db.collection(kind).doc(contentId);
  const data = knownData ?? (await reference.get()).data();
  const organizationId = optionalResourceId(data?.organizationId);

  await cleanupDeletedContentReferences(kind, contentId);
  await db.recursiveDelete(reference);

  // Firestore is the publishing source of truth. Storage is deliberately
  // removed last so a transient Storage failure can leave only an invisible
  // orphan, never a visible content document with a broken cover.
  for (const prefix of contentStoragePrefixes(kind, contentId, organizationId)) {
    await deleteStoragePrefix(prefix);
  }
}

export async function cleanupDeletedContentReferences(
  kind: ContentKind,
  contentIdValue: string
): Promise<void> {
  const contentId = safeResourceId(contentIdValue, "contentId");
  for (const policy of contentReferencePoliciesFor(kind)) {
    const collection = policy.source === "collection"
      ? db.collection(policy.collectionId)
      : db.collectionGroup(policy.collectionId);
    await deletePolicyQuery(
      collection.where(policy.field, "==", contentId),
      (document) => referenceDataMatchesPolicy(document.data(), policy)
    );
  }

  await disableFeaturedBanners(kind, contentId);
}

async function deleteOrganizationContent(
  organizationId: string,
  organizationExists: boolean
): Promise<void> {
  const organizationReference = db.collection("organizations").doc(organizationId);
  if (organizationExists) {
    await organizationReference.delete();
  }

  await deleteOrganizationContentDocuments("news", organizationId);
  await deleteOrganizationContentDocuments("events", organizationId);
  await deleteQuery(db.collection("likes").where("organizationId", "==", organizationId));
  await deleteQuery(db.collection("likes").where(
    "subscribedOrganizationId",
    "==",
    organizationId
  ));
  await deleteQuery(db.collectionGroup("organizationBookmarks").where(
    "organizationId",
    "==",
    organizationId
  ));
  await deleteStoragePrefix(organizationStoragePrefix(organizationId));
  await db.recursiveDelete(organizationReference);
}

async function assertOrganizationHasNoBlockingEvents(
  organizationId: string
): Promise<void> {
  const eventSnapshot = await db.collection("events")
    .where("organizationId", "==", organizationId)
    .get();
  const blockingEvents = eventSnapshot.docs
    .filter((document) => eventBlocksOrganizationDeletion(document.data()))
    .map((document) => document.id);
  if (blockingEvents.length > 0) {
    throw new HttpsError(
      "failed-precondition",
      "Cancel active organization events before deleting the organization.",
      {blockingEventIds: blockingEvents.slice(0, 20)}
    );
  }
}

export const organizationDeletionHistoryQueries = [
  ["organizationBookmarks", "organizationId"],
  ["recentViews", "itemId"],
  ["activityLog", "targetId"],
  ["notificationInbox", "actionTargetId"],
  ["notificationInbox", "sourceId"],
] as const;

async function preflightOrganizationDeletionHistory(organizationId: string): Promise<void> {
  try {
    await Promise.all(organizationDeletionHistoryQueries.map(([collection, field]) =>
      db.collectionGroup(collection).where(field, "==", organizationId).limit(1).select().get()
    ));
  } catch (error) {
    logger.error("Organization deletion query preflight failed.", error);
    throw new HttpsError("unavailable", "Organization deletion is temporarily unavailable. Please retry later.");
  }
}

async function deleteOrganizationHistoryReferences(
  organizationId: string
): Promise<void> {
  await deletePolicyQuery(
    db.collectionGroup("recentViews").where("itemId", "==", organizationId),
    (document) => document.get("itemType") === "organization"
  );
  await deletePolicyQuery(
    db.collectionGroup("activityLog").where("targetId", "==", organizationId),
    (document) => document.get("targetType") === "organization"
  );
  await deletePolicyQuery(
    db.collectionGroup("notificationInbox").where(
      "actionTargetId",
      "==",
      organizationId
    ),
    (document) => ["openOrganization", "openOrganizationRequest"].includes(
      document.get("actionType")
    )
  );
  await deletePolicyQuery(
    db.collectionGroup("notificationInbox").where("sourceId", "==", organizationId),
    (document) => ["openOrganization", "openOrganizationRequest"].includes(
      document.get("actionType")
    )
  );
}

async function deleteOrganizationContentDocuments(
  kind: ContentKind,
  organizationId: string
): Promise<void> {
  while (true) {
    const snapshot = await db.collection(kind)
      .where("organizationId", "==", organizationId)
      .limit(organizationContentBatchSize)
      .get();
    if (snapshot.empty) {
      return;
    }

    for (const document of snapshot.docs) {
      if (kind === "news") {
        await deleteNewsContent(document.id, document.data());
      } else {
        await deleteEventContent(document.id, document.data());
      }
    }
  }
}

async function assertCanDeleteOrganizationContent(
  actorUserId: string,
  contentData: DocumentData | undefined,
  hasOwnerOverride: boolean
): Promise<void> {
  if (hasOwnerOverride) {
    return;
  }
  if (contentData?.sourceType !== "organization") {
    throw new HttpsError("permission-denied", "Content deletion permissions are required.");
  }

  const organizationId = optionalResourceId(contentData.organizationId);
  if (!organizationId || organizationId === systemOrganizationId) {
    throw new HttpsError("permission-denied", "Content organization is missing.");
  }

  const roles = await getOrganizationRoles(organizationId);
  if (roles.ownerId !== actorUserId) {
    throw new HttpsError("permission-denied", "Organization owner permissions are required.");
  }
}

async function deleteQuery(query: Query<DocumentData>): Promise<void> {
  while (true) {
    const snapshot = await query.limit(relatedBatchSize).get();
    if (snapshot.empty) {
      return;
    }

    const writer = new CheckedBulkWriter();
    for (const document of snapshot.docs) {
      writer.delete(document.ref);
    }
    await writer.close();
  }
}

async function deletePolicyQuery(
  query: Query<DocumentData>,
  shouldDelete: (document: QueryDocumentSnapshot<DocumentData>) => boolean
): Promise<void> {
  let cursor: QueryDocumentSnapshot<DocumentData> | undefined;
  while (true) {
    let pageQuery = query.orderBy(FieldPath.documentId()).limit(relatedBatchSize);
    if (cursor) {
      pageQuery = pageQuery.startAfter(cursor);
    }
    const snapshot = await pageQuery.get();
    if (snapshot.empty) {
      return;
    }

    const matchingDocuments = snapshot.docs.filter(shouldDelete);
    if (matchingDocuments.length > 0) {
      const writer = new CheckedBulkWriter();
      for (const document of matchingDocuments) {
        writer.delete(document.ref);
      }
      await writer.close();
    }

    cursor = snapshot.docs.at(-1);
    if (snapshot.size < relatedBatchSize) {
      return;
    }
  }
}

async function disableFeaturedBanners(kind: ContentKind, contentId: string): Promise<void> {
  const actionType = featuredBannerActionType(kind);
  const snapshot = await db.collection("featuredBanners")
    .where("actionTargetID", "==", contentId)
    .get();
  const matchingBanners = snapshot.docs.filter(
    (document) => document.get("actionType") === actionType
  );
  if (matchingBanners.length === 0) {
    return;
  }

  const writer = new CheckedBulkWriter();
  const updatedAt = Timestamp.now();
  for (const banner of matchingBanners) {
    writer.update(banner.ref, {
      isActive: false,
      actionType: "none",
      actionTargetID: FieldValue.delete(),
      updatedAt,
      updatedBy: "system-content-lifecycle",
    });
  }
  await writer.close();
}

async function deleteStoragePrefix(prefix: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({prefix, force: true});
}

function requestResourceId(data: unknown, field: string): string {
  if (!isRecord(data) || typeof data[field] !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  return safeResourceId(data[field], field);
}

function safeResourceId(value: string, field: string): string {
  try {
    return normalizedResourceId(value, field);
  } catch {
    throw new HttpsError("invalid-argument", `${field} must be a valid document ID.`);
  }
}

function optionalResourceId(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  try {
    return normalizedResourceId(value, "organizationId");
  } catch {
    return undefined;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
