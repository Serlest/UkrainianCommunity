import {type DocumentData, type Query} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuth} from "../auth/context";
import {adminStorage, db} from "../firebase/admin";
import {getOrganizationRoles} from "../permissions/organizationPermissions";
import {getUserPermissions, isActiveUser, isOwner} from "../permissions/userPermissions";
import {
  type ContentKind,
  contentReferencePoliciesFor,
  contentStoragePrefixes,
  eventBlocksOrganizationDeletion,
  normalizedResourceId,
  organizationStoragePrefix,
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
};

const relatedBatchSize = 400;
const organizationContentBatchSize = 100;
const systemOrganizationId = "ukrainian-community";

export const deleteNews = onCall(
  callableOptions,
  async (request): Promise<DeletionResponse> => {
    const auth = requireAuth(request);
    const actor = await getUserPermissions(auth.uid);
    if (!isActiveUser(actor)) {
      throw new HttpsError("permission-denied", "An active account is required.");
    }
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
    const auth = requireAuth(request);
    const actor = await getUserPermissions(auth.uid);
    if (!isOwner(actor)) {
      throw new HttpsError("permission-denied", "Owner permissions are required.");
    }

    const organizationId = requestResourceId(request.data, "organizationId");
    if (organizationId === systemOrganizationId) {
      throw new HttpsError("failed-precondition", "The system organization cannot be deleted.");
    }

    const organizationReference = db.collection("organizations").doc(organizationId);
    const organizationSnapshot = await organizationReference.get();
    await deleteOrganizationContent(organizationId, organizationSnapshot.exists);
    const deletedAt = new Date().toISOString();
    logger.info("Organization deletion completed.", {
      organizationId,
      actorUserId: auth.uid,
    });

    return {
      status: organizationSnapshot.exists ? "deleted" : "alreadyDeleted",
      deletedAt,
    };
  }
);

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

  for (const prefix of contentStoragePrefixes(kind, contentId, organizationId)) {
    await deleteStoragePrefix(prefix);
  }

  for (const policy of contentReferencePoliciesFor(kind)) {
    const collection = policy.source === "collection"
      ? db.collection(policy.collectionId)
      : db.collectionGroup(policy.collectionId);
    await deleteQuery(collection.where(policy.field, "==", contentId));
  }

  await db.recursiveDelete(reference);
}

async function deleteOrganizationContent(
  organizationId: string,
  organizationExists: boolean
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

    const writer = db.bulkWriter();
    for (const document of snapshot.docs) {
      writer.delete(document.ref);
    }
    await writer.close();
  }
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
