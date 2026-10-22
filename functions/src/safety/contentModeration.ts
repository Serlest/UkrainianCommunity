import {createHash} from "node:crypto";

import {FieldPath, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {canAccessModerationTools, isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";

type ModeratedContentType = "news" | "event";
type ModerationDecision = "approved" | "needsRevision" | "rejected";

interface ModerationRequest {
  contentType: ModeratedContentType;
  contentId: string;
  decision: ModerationDecision;
  operationId: string;
  expectedRevision: string;
  reason?: string;
  principalId?: string;
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
  if (!["news", "event"].includes(contentType) || !["approved", "needsRevision", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "Moderation request contains an unsupported value.");
  }
  const expectedRevision = requiredString(data.expectedRevision, "expectedRevision", 80);
  if (!/^\d+:\d+$/.test(expectedRevision)) {
    throw new HttpsError("invalid-argument", "expectedRevision is invalid.");
  }
  const reason = data.reason === undefined ? undefined : typeof data.reason === "string" ? data.reason.trim() : null;
  if (reason === null || (reason?.length ?? 0) > 2000 || (decision === "needsRevision" && !reason)) {
    throw new HttpsError("invalid-argument", "A reason of at most 2000 characters is required.");
  }
  if (data.principalId !== undefined && typeof data.principalId !== "string") throw new HttpsError("invalid-argument", "Invalid principal.");
  // Keep omitted fields absent so existing operation receipts retain their original fingerprint.
  return {
    ...(reason !== undefined ? {reason} : {}),
    ...(data.principalId !== undefined ? {principalId: data.principalId as string} : {}),
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
    if (request.principalId !== undefined && request.principalId !== actor.uid) throw new HttpsError("permission-denied", "Account changed.");
    if (request.principalId && request.decision !== "approved" && !request.reason) throw new HttpsError("invalid-argument", "Explain the decision.");
    const fingerprint = requestFingerprint(request);
    const receiptId = createHash("sha256")
      .update(`content-moderation\0${actor.uid}\0${request.contentType}\0${request.contentId}\0${request.operationId}`)
      .digest("hex");
    const receiptReference = db.collection("contentModerationOperations").doc(receiptId);
    const contentReference = db.collection(collections[request.contentType]).doc(request.contentId);
    const now = Timestamp.now();

    const result = await db.runTransaction(async transaction => {
      const [receipt, content, reviewer] = await Promise.all([
        transaction.get(receiptReference), transaction.get(contentReference), transaction.get(db.doc(`users/${actor.uid}`)),
      ]);
      if (!canAccessModerationTools(userPermissionSnapshotFromData(actor.uid, reviewer.data()))) throw new HttpsError("permission-denied", "Reviewer access changed.");
      if (receipt.exists) {
        if (receipt.get("fingerprint") !== fingerprint) {
          throw new HttpsError("already-exists", "The operation ID was already used for another decision.");
        }
        return {replayed: true, updatedAt: receipt.get("updatedAt") as Timestamp};
      }
      if (!content.exists) throw new HttpsError("not-found", "Content was not found.");
      const storedRevision = timestampRevision(content.get("updatedAt"));
      // Installed pre-migration clients reconstruct Timestamp through Date (sub-microsecond loss).
      // Keep their comparison within half one Firestore microsecond; new clients use strict exact CAS.
      let matchesRevision = storedRevision === request.expectedRevision;
      if (!matchesRevision && !request.principalId && storedRevision) {
        const [s, n] = storedRevision.split(":").map(BigInt);
        const [rs, rn] = request.expectedRevision.split(":").map(BigInt);
        const delta = (s - rs) * 1_000_000_000n + n - rn;
        matchesRevision = rn < 1_000_000_000n && delta >= -500n && delta <= 500n;
      }
      if (!matchesRevision) {
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
        moderationReason: request.reason ?? "",
      });
      transaction.create(receiptReference, {
        fingerprint,
        contentType: request.contentType,
        contentId: request.contentId,
        decision: request.decision,
        actorUserId: actor.uid,
        reviewerName: reviewer.get("displayName") ?? reviewer.get("fullName") ?? "",
        title: content.get("title") ?? "",
        organizationId: content.get("organizationId") ?? "",
        organizationName: content.get("organizationName") ?? "",
        reason: request.reason ?? "",
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
          eventType: request.decision === "approved" ? "contentApproved" : request.decision === "rejected" ? "contentRejected" : "contentUpdated",
          actorUserId: actor.uid,
          actorRole: actor.permissions.globalRole ?? "admin",
          targetType: request.contentType === "news" ? "newsPost" : "event",
          targetId: request.contentId,
          outcome: request.decision === "approved" ? "approved" : request.decision === "rejected" ? "rejected" : "success",
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

// Read and resubmission API; decisions continue through the existing compatible callable.
const text = (value: unknown): string => typeof value === "string" ? value : "";
const member = (data: FirebaseFirestore.DocumentData | undefined, uid: string): boolean => !!data &&
  (data.ownerId === uid || [data.adminIds, data.moderatorIds].some(v => Array.isArray(v) && v.includes(uid)));
const millis = (value: unknown): number | null => value instanceof Timestamp ? value.toMillis() : null;
function preview(id: string, type: ModeratedContentType, d: FirebaseFirestore.DocumentData, canReview: boolean) {
  const translations = Object.fromEntries(["uk", "de"].map(language => {
    const localized = d.localizations?.[language] ?? {};
    return [language, {title: text(localized.title) || text(d.title),
      summary: text(localized.subtitle ?? localized.summary) || text(d.subtitle ?? d.summary),
      body: text(localized.body ?? localized.details) || text(d.body ?? d.details)}];
  }));
  return {id, contentType: type, revision: timestampRevision(d.updatedAt) ?? "", status: text(d.moderationStatus),
    title: text(d.title), translations, organizationId: text(d.organizationId), organizationName: text(d.organizationName),
    authorName: text(d.authorName), createdAt: millis(d.createdAt) ?? 0, imageURL: text(d.imageURL),
    sourceName: text(d.sourceName), sourceURL: text(d.sourceURL), region: text(d.federalState),
    venue: text(d.venue), city: text(d.city), address: text(d.address), startDate: millis(d.startDate), endDate: millis(d.endDate),
    reason: text(d.moderationReason), canReview: canReview && d.moderationStatus === "pendingReview"};
}
export const manageContentModeration = onCall(
  {region: "europe-west3", maxInstances: 20, enforceAppCheck: false}, async call => {
    const actor = await requireVerifiedActiveUser(call);
    const data = call.data as Record<string, unknown>;
    if (!data || typeof data !== "object") throw new HttpsError("invalid-argument", "Request required.");
    const moderator = canAccessModerationTools(actor.permissions);
    if (data.action === "preview" || data.action === "resubmit") {
      const type = data.contentType as ModeratedContentType;
      if (!["news", "event"].includes(type)) throw new HttpsError("invalid-argument", "Invalid content type.");
      const id = requiredString(data.contentId, "contentId", 256);
      const ref = db.collection(collections[type]).doc(id);
      return db.runTransaction(async tx => {
        const doc = await tx.get(ref);
        if (!doc.exists) throw new HttpsError("not-found", "Content unavailable.");
        const d = doc.data()!;
        const organization = text(d.organizationId) ? await tx.get(db.doc(`organizations/${d.organizationId}`)) : undefined;
        const user = await tx.get(db.doc(`users/${actor.uid}`));
        const permissions = userPermissionSnapshotFromData(actor.uid, user.data());
        if (!isActiveUser(permissions)) throw new HttpsError("permission-denied", "Account access changed.");
        const currentModerator = canAccessModerationTools(permissions);
        const contributor = d.authorId === actor.uid || member(organization?.data(), actor.uid);
        if (!currentModerator && !contributor) throw new HttpsError("permission-denied", "Content access required.");
        if (data.action === "resubmit") {
          if (!member(organization?.data(), actor.uid) && !currentModerator) throw new HttpsError("permission-denied", "Current organization access required.");
          if (d.moderationStatus === "pendingReview" && d.resubmittedByUserId === actor.uid && d.resubmittedFromRevision === data.expectedRevision) {
            return {item: preview(id, type, d, currentModerator)};
          }
          if (timestampRevision(d.updatedAt) !== data.expectedRevision) throw new HttpsError("aborted", "Content changed.");
          if (!["needsRevision", "rejected"].includes(d.moderationStatus)) throw new HttpsError("failed-precondition", "Only returned content can be resubmitted.");
          const now = Timestamp.now();
          tx.update(ref, {moderationStatus: "pendingReview", updatedAt: now, moderationReason: "", resubmittedByUserId: actor.uid, resubmittedFromRevision: data.expectedRevision});
          return {item: preview(id, type, {...d, moderationStatus: "pendingReview", updatedAt: now, moderationReason: ""}, currentModerator)};
        }
        return {item: {...preview(id, type, d, currentModerator), canEdit: member(organization?.data(), actor.uid) || permissions.globalRole === "owner"}};
      });
    }
    if (!moderator) throw new HttpsError("permission-denied", "Reviewer access required.");
    const limit = data.limit === undefined ? 30 : data.limit;
    if (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 50) throw new HttpsError("invalid-argument", "Invalid page size.");
    let cursor: {seconds: number; nanoseconds: number; id: string} | undefined;
    if (data.cursor !== undefined && data.cursor !== null) {
      const c = data.cursor as Record<string, unknown>;
      if (!c || !Number.isSafeInteger(c.seconds) || (c.seconds as number) < -62135596800 || (c.seconds as number) > 253402300799 || !Number.isInteger(c.nanoseconds) || (c.nanoseconds as number) < 0 || (c.nanoseconds as number) >= 1e9) throw new HttpsError("invalid-argument", "Invalid cursor.");
      cursor = {seconds: c.seconds as number, nanoseconds: c.nanoseconds as number, id: requiredString(c.id, "cursor.id", 256)};
    }
    if (data.action === "history") {
      let q = db.collection("contentModerationOperations").orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc");
      if (cursor) q = q.startAfter(new Timestamp(cursor.seconds, cursor.nanoseconds), cursor.id);
      const docs = await q.limit((limit as number) + 1).get();
      const selected = docs.docs.slice(0, limit as number); const last = selected.at(-1);
      return {history: selected.map(doc => {const d = doc.data(); return {id: doc.id, contentId: text(d.contentId), contentType: text(d.contentType), title: text(d.title),
        status: text(d.decision), reason: text(d.reason), reviewerName: text(d.reviewerName), organizationName: text(d.organizationName), createdAt: millis(d.createdAt) ?? 0};}),
        cursor: docs.size > (limit as number) && last ? {seconds: last.get("createdAt").seconds, nanoseconds: last.get("createdAt").nanoseconds, id: last.id} : null};
    }
    if (data.action !== "list") throw new HttpsError("invalid-argument", "Unsupported action.");
    const type = data.contentType as ModeratedContentType;
    if (!["news", "event"].includes(type)) throw new HttpsError("invalid-argument", "Invalid content type.");
    let q = db.collection(collections[type]).where("moderationStatus", "==", "pendingReview").orderBy("createdAt", "desc").orderBy(FieldPath.documentId(), "desc");
    if (cursor) q = q.startAfter(new Timestamp(cursor.seconds, cursor.nanoseconds), cursor.id);
    const [docs, newsCount, eventCount] = await Promise.all([q.select("title", "summary", "subtitle", "createdAt", "updatedAt", "moderationStatus", "authorName", "organizationId", "organizationName",
      "localizations.uk.title", "localizations.uk.subtitle", "localizations.uk.summary", "localizations.de.title", "localizations.de.subtitle", "localizations.de.summary").limit((limit as number) + 1).get(),
      db.collection("news").where("moderationStatus", "==", "pendingReview").count().get(),
      db.collection("events").where("moderationStatus", "==", "pendingReview").count().get()]);
    const selected = docs.docs.slice(0, limit as number); const last = selected.at(-1);
    return {items: selected.map(doc => preview(doc.id, type, doc.data(), true)), counts: {news: newsCount.data().count, event: eventCount.data().count},
      cursor: docs.size > (limit as number) && last ? {seconds: last.get("createdAt").seconds, nanoseconds: last.get("createdAt").nanoseconds, id: last.id} : null};
  }
);
