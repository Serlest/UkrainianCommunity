import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {db} from "../firebase/admin";
import {isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";

type ScheduledCollection = "news" | "events";

const batchSize = 100;

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
  const candidate = await reference.get();
  const data = candidate.data();
  if (!candidate.exists || !data || data.moderationStatus !== "draft") return "skipped";
  const scheduledAt = data.scheduledAt;
  if (!(scheduledAt instanceof Timestamp) || scheduledAt.toMillis() > now.toMillis()) return "skipped";

  const authorId = stringValue(data.authorId);
  const organizationId = stringValue(data.organizationId);
  if (!authorId || !organizationId) return moveToReview(reference, now);

  const [user, organization] = await Promise.all([
    db.collection("users").doc(authorId).get(),
    db.collection("organizations").doc(organizationId).get(),
  ]);
  const permissions = userPermissionSnapshotFromData(authorId, user.data());
  if (!user.exists || !isActiveUser(permissions) || !organization.exists) {
    return moveToReview(reference, now);
  }

  const organizationData = organization.data() ?? {};
  const isAppOwner = permissions.globalRole === "owner";
  const canPublishForOrganization = isAppOwner || hasOrganizationRole(organizationData, authorId);
  if (!canPublishForOrganization || organizationData.moderationStatus !== "approved") {
    return moveToReview(reference, now);
  }

  if (await hasExactDuplicate(collection, documentId, data)) {
    return moveToReview(reference, now);
  }

  const nextStatus = collection === "news" && data.regionScope === "austria" && !isAppOwner
    ? "pendingReview"
    : "approved";
  await reference.update({
    moderationStatus: nextStatus,
    publishedAt: collection === "news" ? now : data.publishedAt ?? FieldValue.delete(),
    scheduledAt: FieldValue.delete(),
    updatedAt: now,
  });
  return nextStatus;
}

async function moveToReview(
  reference: FirebaseFirestore.DocumentReference,
  now: Timestamp
): Promise<"pendingReview"> {
  await reference.update({
    moderationStatus: "pendingReview",
    scheduledAt: FieldValue.delete(),
    updatedAt: now,
  });
  return "pendingReview";
}

async function hasExactDuplicate(
  collection: ScheduledCollection,
  documentId: string,
  data: DocumentData
): Promise<boolean> {
  if (collection === "news") {
    const sourceURL = stringValue(data.sourceURL);
    if (!sourceURL) return false;
    const matches = await db.collection("news").where("sourceURL", "==", sourceURL).limit(10).get();
    return matches.docs.some((item) => item.id !== documentId &&
      ["approved", "pendingReview"].includes(item.get("moderationStatus")));
  }

  const startDate = data.startDate;
  if (!(startDate instanceof Timestamp)) return false;
  const normalizedTitle = normalizeText(stringValue(data.title));
  const organizationId = stringValue(data.organizationId);
  const matches = await db.collection("events").where("startDate", "==", startDate).limit(20).get();
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
