import {createHash} from "node:crypto";

import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {canAccessModerationTools} from "../permissions/userPermissions";

type ModeratedContentType = "news" | "event";
type ModerationDecision = "approved" | "rejected";

interface ModerationRequest {
  contentType: ModeratedContentType;
  contentId: string;
  decision: ModerationDecision;
  operationId: string;
  expectedRevision: string;
}

const collections: Record<ModeratedContentType, string> = {news: "news", event: "events"};
const receiptRetentionMilliseconds = 30 * 24 * 60 * 60 * 1_000;

function requiredString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be a string.`);
  const normalized = value.trim();
  if (!normalized || normalized.length > maximumLength || normalized.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return normalized;
}

function parseRequest(value: unknown): ModerationRequest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Moderation request is required.");
  }
  const data = value as Record<string, unknown>;
  const contentType = requiredString(data.contentType, "contentType", 20) as ModeratedContentType;
  const decision = requiredString(data.decision, "decision", 20) as ModerationDecision;
  if (!["news", "event"].includes(contentType) || !["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "Moderation request contains an unsupported value.");
  }
  const expectedRevision = requiredString(data.expectedRevision, "expectedRevision", 80);
  if (!/^\d+:\d+$/.test(expectedRevision)) {
    throw new HttpsError("invalid-argument", "expectedRevision is invalid.");
  }
  return {
    contentType,
    contentId: requiredString(data.contentId, "contentId", 256),
    decision,
    operationId: requiredString(data.operationId, "operationId", 200),
    expectedRevision,
  };
}

function timestampRevision(value: unknown): string | undefined {
  return value instanceof Timestamp ? `${value.seconds}:${value.nanoseconds}` : undefined;
}

function requestFingerprint(request: ModerationRequest): string {
  return createHash("sha256").update(JSON.stringify(request)).digest("hex");
}

export const reviewContentModeration = onCall(
  {region: "europe-west3", maxInstances: 20, enforceAppCheck: false},
  async (call) => {
    const actor = await requireVerifiedActiveUser(call);
    if (!canAccessModerationTools(actor.permissions)) {
      throw new HttpsError("permission-denied", "Moderation permissions are required.");
    }
    const request = parseRequest(call.data);
    const fingerprint = requestFingerprint(request);
    const receiptId = createHash("sha256")
      .update(`content-moderation\0${actor.uid}\0${request.contentType}\0${request.contentId}\0${request.operationId}`)
      .digest("hex");
    const receiptReference = db.collection("contentModerationOperations").doc(receiptId);
    const contentReference = db.collection(collections[request.contentType]).doc(request.contentId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async transaction => {
      const [receipt, content] = await Promise.all([
        transaction.get(receiptReference), transaction.get(contentReference),
      ]);
      if (receipt.exists) {
        if (receipt.get("fingerprint") !== fingerprint) {
          throw new HttpsError("already-exists", "The operation ID was already used for another decision.");
        }
        return {replayed: true, updatedAt: receipt.get("updatedAt") as Timestamp};
      }
      if (!content.exists) throw new HttpsError("not-found", "Content was not found.");
      if (timestampRevision(content.get("updatedAt")) !== request.expectedRevision) {
        throw new HttpsError("aborted", "Content changed after this moderation screen was loaded.");
      }
      if (content.get("moderationStatus") !== "pendingReview") {
        throw new HttpsError("failed-precondition", "Only pending content can be reviewed.");
      }
      transaction.update(contentReference, {
        moderationStatus: request.decision,
        updatedAt: now,
        moderationOperationId: request.operationId,
        moderatedByUserId: actor.uid,
        moderatedAt: now,
      });
      transaction.create(receiptReference, {
        fingerprint,
        contentType: request.contentType,
        contentId: request.contentId,
        decision: request.decision,
        actorUserId: actor.uid,
        updatedAt: now,
        createdAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + receiptRetentionMilliseconds),
      });
      return {replayed: false, updatedAt: now};
    });

    if (!result.replayed) {
      const logReference = db.collection("systemLogs").doc();
      try {
        await logReference.set({
          id: logReference.id,
          createdAt: now,
          category: "moderation",
          severity: "info",
          severityRank: 1,
          eventType: "contentModerationReviewed",
          actorUserId: actor.uid,
          actorRole: actor.permissions.globalRole ?? "admin",
          targetType: request.contentType,
          targetId: request.contentId,
          outcome: "success",
          summary: `${request.contentType} moderation decided: ${request.decision}`,
          isReviewed: true,
          reviewedAt: now,
          reviewedByUserId: actor.uid,
          metadata: {decision: request.decision, operationId: request.operationId},
          retentionPolicy: "moderationDispute",
          isAppAdminReadable: true,
        });
      } catch (error) {
        console.error("Committed content moderation but failed to write its diagnostic log.", error);
      }
    }

    return {
      contentType: request.contentType,
      contentId: request.contentId,
      moderationStatus: request.decision,
      operationId: request.operationId,
      updatedAt: result.updatedAt.toDate().toISOString(),
      replayed: result.replayed,
    };
  }
);
