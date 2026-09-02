import {createHash, randomBytes} from "node:crypto";

import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall, onRequest} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";
import {writeUserNotification} from "../notifications/notificationPayloads";

export type DsaLanguage = "de" | "uk";
export type DsaNoticeCategory =
  | "hate"
  | "terrorism"
  | "childSafety"
  | "privacy"
  | "defamation"
  | "fraud"
  | "intellectualProperty"
  | "consumerProtection"
  | "other";
export type DsaDecisionOutcome = "noAction" | "restricted" | "removed";

export interface DsaNoticeInput {
  exactLocation: string;
  contentDescription: string;
  illegalExplanation: string;
  legalBasis?: string;
  evidence?: string;
  category: DsaNoticeCategory;
  reporterName?: string;
  reporterEmail?: string;
  contactException: boolean;
  goodFaithConfirmed: true;
  preferredLanguage: DsaLanguage;
}

interface CreateDsaCaseInput extends DsaNoticeInput {
  reporterUserId?: string;
  targetType?: string;
  targetId?: string;
  parentType?: string;
  parentId?: string;
  targetAuthorId?: string;
  targetTitle?: string;
  targetExcerpt?: string;
  reason?: string;
  isUrgent?: boolean;
}

interface DsaCaseReceipt {
  reportId: string;
  caseNumber: string;
  accessToken: string;
  status: "submitted";
  submittedAt: string;
  acknowledgementAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  invoker: "public" as const,
  enforceAppCheck: false,
};
const categories = new Set<DsaNoticeCategory>([
  "hate", "terrorism", "childSafety", "privacy", "defamation", "fraud",
  "intellectualProperty", "consumerProtection", "other",
]);
const languages = new Set<DsaLanguage>(["de", "uk"]);
const decisionOutcomes = new Set<DsaDecisionOutcome>(["noAction", "restricted", "removed"]);
const appealWindowMilliseconds = 183 * 24 * 60 * 60 * 1_000;
const caseRetentionMilliseconds = 183 * 24 * 60 * 60 * 1_000;
const evidenceRetentionMilliseconds = 1_095 * 24 * 60 * 60 * 1_000;
const portalRateLimitPerDay = 10;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.replace(/\s+/g, " ").trim();
  if (normalized.length === 0 || normalized.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${field} has an invalid length.`);
  }
  return normalized;
}

function optionalString(value: unknown, field: string, maximumLength: number): string | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return requiredString(value, field, maximumLength);
}

function enumValue<T extends string>(value: unknown, field: string, values: Set<T>): T {
  if (typeof value !== "string" || !values.has(value as T)) {
    throw new HttpsError("invalid-argument", `${field} is not supported.`);
  }
  return value as T;
}

function validEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

export function parseDsaNoticeInput(value: unknown): DsaNoticeInput {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "The notice must be an object.");
  }
  const category = enumValue(value.category, "category", categories);
  const contactException = value.contactException === true;
  const reporterName = optionalString(value.reporterName, "reporterName", 160);
  const reporterEmail = optionalString(value.reporterEmail, "reporterEmail", 254)?.toLowerCase();

  if (contactException && category !== "childSafety") {
    throw new HttpsError("invalid-argument", "The contact exception is only available for child-safety notices.");
  }
  if (!contactException && (!reporterName || !reporterEmail)) {
    throw new HttpsError("invalid-argument", "Reporter name and email are required.");
  }
  if (reporterEmail && !validEmail(reporterEmail)) {
    throw new HttpsError("invalid-argument", "reporterEmail is invalid.");
  }
  if (value.goodFaithConfirmed !== true) {
    throw new HttpsError("failed-precondition", "The good-faith declaration is required.");
  }

  return {
    exactLocation: requiredString(value.exactLocation, "exactLocation", 2_048),
    contentDescription: requiredString(value.contentDescription, "contentDescription", 500),
    illegalExplanation: requiredString(value.illegalExplanation, "illegalExplanation", 5_000),
    legalBasis: optionalString(value.legalBasis, "legalBasis", 1_000),
    evidence: optionalString(value.evidence, "evidence", 5_000),
    category,
    reporterName,
    reporterEmail,
    contactException,
    goodFaithConfirmed: true,
    preferredLanguage: enumValue(value.preferredLanguage, "preferredLanguage", languages),
  };
}

function caseNumber(now: Date): string {
  const day = now.toISOString().slice(0, 10).replaceAll("-", "");
  return `UC-${day}-${randomBytes(4).toString("hex").toUpperCase()}`;
}

function tokenHash(token: string): string {
  return createHash("sha256").update(`ukrainiancommunity:dsa:${token}`).digest("hex");
}

function publicReportMessage(input: DsaNoticeInput): string {
  return `${input.contentDescription}\n\n${input.illegalExplanation}`.slice(0, 2_000);
}

export async function createDsaCase(input: CreateDsaCaseInput): Promise<DsaCaseReceipt> {
  const now = Timestamp.now();
  const reportId = db.collection("feedback").doc().id;
  const number = caseNumber(now.toDate());
  const accessToken = randomBytes(24).toString("base64url");
  const caseReference = db.collection("dsaCases").doc(reportId);
  const feedbackReference = db.collection("feedback").doc(reportId);
  const slaHours = input.isUrgent === true ? 24 : 72;
  const slaDueAt = Timestamp.fromMillis(now.toMillis() + slaHours * 60 * 60 * 1_000);
  const reporterLabel = input.reporterName ?? "Protected reporter";
  const targetTitle = input.targetTitle ?? input.contentDescription;
  const reportContext = {
    targetType: input.targetType ?? "external",
    targetId: input.targetId ?? reportId,
    parentType: input.parentType ?? null,
    parentId: input.parentId ?? null,
    targetAuthorId: input.targetAuthorId ?? null,
    targetTitle: targetTitle.slice(0, 160),
    targetExcerpt: (input.targetExcerpt ?? input.contentDescription).slice(0, 280),
    reason: input.reason ?? "other",
    isUrgent: input.isUrgent === true,
    slaDueAt,
  };
  const dsaSummary = {
    caseNumber: number,
    status: "submitted",
    category: input.category,
    exactLocation: input.exactLocation,
    legalBasis: input.legalBasis ?? null,
    illegalExplanation: input.illegalExplanation,
    evidence: input.evidence ?? null,
    goodFaithConfirmed: true,
    acknowledgementAt: now,
    preferredLanguage: input.preferredLanguage,
  };
  const canonicalCase: Record<string, unknown> = {
    id: reportId,
    caseNumber: number,
    accessTokenHash: tokenHash(accessToken),
    status: "submitted",
    submittedAt: now,
    acknowledgementAt: now,
    acknowledgementChannel: input.reporterUserId ? "inApp" : "securePortal",
    updatedAt: now,
    reporterUserId: input.reporterUserId ?? null,
    reporterName: input.reporterName ?? null,
    reporterEmail: input.reporterEmail ?? null,
    contactException: input.contactException,
    preferredLanguage: input.preferredLanguage,
    category: input.category,
    exactLocation: input.exactLocation,
    contentDescription: input.contentDescription,
    illegalExplanation: input.illegalExplanation,
    legalBasis: input.legalBasis ?? null,
    evidence: input.evidence ?? null,
    goodFaithConfirmed: true,
    targetType: input.targetType ?? null,
    targetId: input.targetId ?? null,
    parentType: input.parentType ?? null,
    parentId: input.parentId ?? null,
    targetAuthorId: input.targetAuthorId ?? null,
    automationUsedForSubmission: false,
    expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
    evidenceExpiresAt: Timestamp.fromMillis(now.toMillis() + evidenceRetentionMilliseconds),
  };

  await db.runTransaction(async (transaction) => {
    transaction.create(caseReference, canonicalCase);
    transaction.create(feedbackReference, {
      id: reportId,
      type: "report",
      subject: `DSA ${number}: ${targetTitle}`.slice(0, 200),
      message: publicReportMessage(input),
      status: "open",
      createdAt: now,
      updatedAt: now,
      lastMessageText: publicReportMessage(input),
      lastMessageAt: now,
      lastMessageByUserId: input.reporterUserId ?? "public-dsa-portal",
      lastMessageByRole: "user",
      unreadForOwner: true,
      unreadForUser: false,
      userId: input.reporterUserId ?? "",
      userDisplayName: reporterLabel,
      reportContext,
      occurrenceCount: 1,
      dsaCase: dsaSummary,
    });
  });

  return {
    reportId,
    caseNumber: number,
    accessToken,
    status: "submitted",
    submittedAt: now.toDate().toISOString(),
    acknowledgementAt: now.toDate().toISOString(),
  };
}

function portalCredentials(value: unknown): {caseNumber: string; accessToken: string} {
  if (!isRecord(value)) throw new HttpsError("invalid-argument", "Case credentials are required.");
  return {
    caseNumber: requiredString(value.caseNumber, "caseNumber", 40).toUpperCase(),
    accessToken: requiredString(value.accessToken, "accessToken", 200),
  };
}

async function authorizedPublicCase(value: unknown) {
  const credentials = portalCredentials(value);
  const snapshot = await db.collection("dsaCases").where("caseNumber", "==", credentials.caseNumber).limit(1).get();
  const document = snapshot.docs[0];
  if (!document || document.get("accessTokenHash") !== tokenHash(credentials.accessToken)) {
    throw new HttpsError("not-found", "The case or access code is invalid.");
  }
  return document;
}

function publicCaseResponse(data: FirebaseFirestore.DocumentData) {
  const decision = isRecord(data.decision) ? data.decision : undefined;
  const appeal = isRecord(data.appeal) ? data.appeal : undefined;
  return {
    caseNumber: data.caseNumber,
    status: data.status,
    submittedAt: data.submittedAt?.toDate?.().toISOString(),
    acknowledgementAt: data.acknowledgementAt?.toDate?.().toISOString(),
    decision: decision ? {
      outcome: decision.outcome,
      factsAndCircumstances: decision.factsAndCircumstances,
      legalBasis: decision.legalBasis,
      termsBasis: decision.termsBasis,
      territorialScope: decision.territorialScope,
      duration: decision.duration,
      automationUsed: decision.automationUsed,
      redressInformation: decision.redressInformation,
      decidedAt: (decision.decidedAt as Timestamp | undefined)?.toDate().toISOString(),
      appealDeadline: (decision.appealDeadline as Timestamp | undefined)?.toDate().toISOString(),
    } : null,
    appeal: appeal ? {
      status: appeal.status,
      submittedAt: (appeal.submittedAt as Timestamp | undefined)?.toDate().toISOString(),
      outcome: appeal.outcome,
      reason: appeal.decisionReason,
      decidedAt: (appeal.decidedAt as Timestamp | undefined)?.toDate().toISOString(),
    } : null,
  };
}

async function submitPublicAppeal(value: unknown) {
  if (!isRecord(value)) throw new HttpsError("invalid-argument", "Appeal data is required.");
  const document = await authorizedPublicCase(value);
  const reason = requiredString(value.reason, "reason", 5_000);
  const now = Timestamp.now();
  const feedbackReference = db.collection("feedback").doc(document.id);
  const messageReference = feedbackReference.collection("messages").doc();

  await db.runTransaction(async (transaction) => {
    const fresh = await transaction.get(document.ref);
    const data = fresh.data() ?? {};
    const decision = isRecord(data.decision) ? data.decision : {};
    const deadline = decision.appealDeadline as Timestamp | undefined;
    if (!deadline || deadline.toMillis() < now.toMillis()) {
      throw new HttpsError("failed-precondition", "The appeal period is unavailable or has expired.");
    }
    if (isRecord(data.appeal) && data.appeal.status === "pending") {
      throw new HttpsError("already-exists", "An appeal is already pending.");
    }
    transaction.update(document.ref, {
      status: "appealed",
      appeal: {
        status: "pending",
        reason,
        submittedAt: now,
        humanReviewRequired: true,
      },
      updatedAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
    });
    transaction.set(messageReference, {
      id: messageReference.id,
      feedbackId: document.id,
      senderId: data.reporterUserId ?? "public-dsa-portal",
      senderDisplayName: "DSA portal",
      senderRole: "user",
      text: `DSA appeal: ${reason}`.slice(0, 2_000),
      createdAt: now,
      isSystem: true,
    });
    transaction.update(feedbackReference, {
      status: "open",
      updatedAt: now,
      lastMessageText: `DSA appeal: ${reason}`.slice(0, 2_000),
      lastMessageAt: now,
      lastMessageByUserId: data.reporterUserId ?? "public-dsa-portal",
      lastMessageByRole: "user",
      unreadForOwner: true,
      unreadForUser: false,
      "dsaCase.status": "appealed",
      "dsaCase.appeal": {status: "pending", reason, submittedAt: now},
    });
  });
  return {caseNumber: document.get("caseNumber"), status: "appealed"};
}

async function enforcePortalRateLimit(
  request: {ip?: string; headers: Record<string, unknown>},
  scope: "submit" | "caseAccess"
): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);
  const forwarded = typeof request.headers["x-forwarded-for"] === "string"
    ? request.headers["x-forwarded-for"].split(",")[0].trim()
    : "";
  const networkIdentifier = forwarded || request.ip || "unknown";
  const identifier = createHash("sha256")
    .update(`ukrainiancommunity:dsa-rate:${scope}:${day}:${networkIdentifier}`)
    .digest("hex");
  const reference = db.collection("dsaPortalRateLimits").doc(identifier);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const count = typeof snapshot.get("count") === "number" ? snapshot.get("count") + 1 : 1;
    const maximum = scope === "submit" ? portalRateLimitPerDay : 60;
    if (count > maximum) {
      throw new HttpsError("resource-exhausted", "Too many requests. Please try again later.");
    }
    transaction.set(reference, {
      count,
      day,
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 2 * 24 * 60 * 60 * 1_000),
    });
  });
}

function statusForHttpError(error: unknown): number {
  if (!(error instanceof HttpsError)) return 500;
  switch (error.code) {
  case "invalid-argument": return 400;
  case "failed-precondition": return 409;
  case "already-exists": return 409;
  case "resource-exhausted": return 429;
  case "not-found": return 404;
  default: return 500;
  }
}

export const dsaCasePortal = onRequest(
  {...callableOptions, cors: false},
  async (request, response) => {
    response.set("Cache-Control", "no-store");
    response.set("X-Content-Type-Options", "nosniff");
    if (request.method !== "POST" || !isRecord(request.body)) {
      response.status(405).json({error: "POST JSON required."});
      return;
    }
    try {
      const action = requiredString(request.body.action, "action", 30);
      if (typeof request.body.website === "string" && request.body.website.trim().length > 0) {
        response.status(201).json({status: "submitted"});
        return;
      }
      await enforcePortalRateLimit(request, action === "submit" ? "submit" : "caseAccess");
      if (action === "submit") {
        const receipt = await createDsaCase(parseDsaNoticeInput(request.body));
        response.status(201).json(receipt);
      } else if (action === "status") {
        const document = await authorizedPublicCase(request.body);
        response.status(200).json(publicCaseResponse(document.data()));
      } else if (action === "appeal") {
        response.status(201).json(await submitPublicAppeal(request.body));
      } else {
        throw new HttpsError("invalid-argument", "Unsupported portal action.");
      }
    } catch (error) {
      console.error("DSA portal request failed.", error);
      response.status(statusForHttpError(error)).json({
        error: error instanceof Error ? error.message : "The request failed.",
      });
    }
  }
);

interface DsaDecisionRequest {
  reportId: string;
  outcome: DsaDecisionOutcome;
  factsAndCircumstances: string;
  legalBasis?: string;
  termsBasis?: string;
  territorialScope: string;
  duration: string;
  redressInformation: string;
  humanReviewConfirmed: true;
}

export function parseDsaDecision(value: unknown): DsaDecisionRequest {
  if (!isRecord(value)) throw new HttpsError("invalid-argument", "Decision data is required.");
  const legalBasis = optionalString(value.legalBasis, "legalBasis", 2_000);
  const termsBasis = optionalString(value.termsBasis, "termsBasis", 2_000);
  if (!legalBasis && !termsBasis) {
    throw new HttpsError("invalid-argument", "At least one legal or terms basis is required.");
  }
  if (value.humanReviewConfirmed !== true) {
    throw new HttpsError("failed-precondition", "Human review must be confirmed.");
  }
  return {
    reportId: requiredString(value.reportId, "reportId", 200),
    outcome: enumValue(value.outcome, "outcome", decisionOutcomes),
    factsAndCircumstances: requiredString(value.factsAndCircumstances, "factsAndCircumstances", 5_000),
    legalBasis,
    termsBasis,
    territorialScope: requiredString(value.territorialScope, "territorialScope", 500),
    duration: requiredString(value.duration, "duration", 500),
    redressInformation: requiredString(value.redressInformation, "redressInformation", 2_000),
    humanReviewConfirmed: true,
  };
}

async function verifyModerationAction(
  caseData: FirebaseFirestore.DocumentData,
  outcome: DsaDecisionOutcome
): Promise<void> {
  if (outcome === "noAction") return;
  const targetType = typeof caseData.targetType === "string" ? caseData.targetType : undefined;
  const targetId = typeof caseData.targetId === "string" ? caseData.targetId : undefined;
  if (!targetType || !targetId || targetType === "external") {
    throw new HttpsError(
      "failed-precondition",
      "A restrictive decision requires a linked in-app target and a completed moderation action."
    );
  }
  let snapshot: FirebaseFirestore.DocumentSnapshot;
  if (targetType === "comment") {
    const parentType = typeof caseData.parentType === "string" ? caseData.parentType : undefined;
    const parentId = typeof caseData.parentId === "string" ? caseData.parentId : undefined;
    const parentCollections: Record<string, string> = {news: "news", event: "events", organization: "organizations"};
    if (!parentType || !parentId || !parentCollections[parentType]) {
      throw new HttpsError("failed-precondition", "The linked comment location is incomplete.");
    }
    snapshot = await db.collection(parentCollections[parentType]).doc(parentId).collection("comments").doc(targetId).get();
  } else {
    const collections: Record<string, string> = {news: "news", event: "events", organization: "organizations"};
    if (!collections[targetType]) throw new HttpsError("failed-precondition", "The linked target is unsupported.");
    snapshot = await db.collection(collections[targetType]).doc(targetId).get();
  }
  if (outcome === "removed" && snapshot.exists) {
    const data = snapshot.data() ?? {};
    if (data.isDeleted !== true && !data.deletedAt && data.moderationStatus !== "archived") {
      throw new HttpsError("failed-precondition", "Remove the linked content before recording a removal decision.");
    }
  }
  if (outcome === "restricted") {
    const data = snapshot.data() ?? {};
    if (!snapshot.exists || (data.visibilityRestricted !== true && data.moderationStatus === "approved")) {
      throw new HttpsError("failed-precondition", "Restrict the linked content before recording a restriction decision.");
    }
  }
}

export const decideDsaCase = onCall(
  callableOptions,
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    const decisionInput = parseDsaDecision(request.data);
    const caseReference = db.collection("dsaCases").doc(decisionInput.reportId);
    const feedbackReference = db.collection("feedback").doc(decisionInput.reportId);
    const now = Timestamp.now();
    const appealDeadline = Timestamp.fromMillis(now.toMillis() + appealWindowMilliseconds);
    const preflightCaseSnapshot = await caseReference.get();
    if (!preflightCaseSnapshot.exists) throw new HttpsError("not-found", "DSA case was not found.");
    await verifyModerationAction(preflightCaseSnapshot.data() ?? {}, decisionInput.outcome);
    const decision = {
      outcome: decisionInput.outcome,
      factsAndCircumstances: decisionInput.factsAndCircumstances,
      legalBasis: decisionInput.legalBasis ?? null,
      termsBasis: decisionInput.termsBasis ?? null,
      territorialScope: decisionInput.territorialScope,
      duration: decisionInput.duration,
      automationUsed: false,
      humanReviewConfirmed: true,
      actionVerifiedAt: now,
      redressInformation: decisionInput.redressInformation,
      decidedAt: now,
      decidedByUserId: actor.uid,
      appealDeadline,
    };

    const result = await db.runTransaction(async (transaction) => {
      const [caseSnapshot, feedbackSnapshot] = await Promise.all([
        transaction.get(caseReference), transaction.get(feedbackReference),
      ]);
      if (!caseSnapshot.exists || !feedbackSnapshot.exists) {
        throw new HttpsError("not-found", "DSA case was not found.");
      }
      const data = caseSnapshot.data() ?? {};
      if (!['submitted', 'underReview'].includes(String(data.status))) {
        throw new HttpsError("failed-precondition", "Only an undecided case can be decided.");
      }
      transaction.update(caseReference, {
        status: "decided",
        decision,
        ...(data.appeal ? {previousAppeal: data.appeal, appeal: FieldValue.delete()} : {}),
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
      });
      const summary = `${decisionInput.outcome}: ${decisionInput.factsAndCircumstances}`.slice(0, 2_000);
      transaction.update(feedbackReference, {
        status: "closed",
        updatedAt: now,
        ownerReply: summary,
        repliedAt: now,
        repliedByUserId: actor.uid,
        lastMessageText: summary,
        lastMessageAt: now,
        lastMessageByUserId: actor.uid,
        lastMessageByRole: "owner",
        unreadForOwner: false,
        unreadForUser: true,
        "dsaCase.status": "decided",
        "dsaCase.decision": decision,
        ...(data.appeal ? {"dsaCase.appeal": FieldValue.delete()} : {}),
      });
      const targetAuthorId = typeof data.targetAuthorId === "string" ? data.targetAuthorId : undefined;
      if (targetAuthorId) {
        transaction.set(
          db.collection("users").doc(targetAuthorId).collection("dsaStatements").doc(decisionInput.reportId),
          {
            id: decisionInput.reportId,
            caseNumber: String(data.caseNumber),
            status: "decided",
            sourceType: data.targetType ?? "content",
            sourceId: data.targetId ?? "",
            decision,
            updatedAt: now,
            expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
          }
        );
      }
      return {
        reporterUserId: typeof data.reporterUserId === "string" ? data.reporterUserId : undefined,
        targetAuthorId,
        caseNumber: String(data.caseNumber),
      };
    });

    const notifications: Promise<unknown>[] = [];
    if (result.reporterUserId) notifications.push(writeUserNotification({
      notificationId: `dsaDecision_${decisionInput.reportId}_${result.reporterUserId}`,
      targetUserId: result.reporterUserId,
      type: "reportReviewed",
      title: "DSA decision",
      message: `A reasoned decision is available for case ${result.caseNumber}.`,
      severity: "info",
      actionType: "openFeedback",
      actionTargetId: decisionInput.reportId,
      sourceType: "feedback",
      sourceId: decisionInput.reportId,
      metadata: {reportId: decisionInput.reportId, caseNumber: result.caseNumber},
      dedupeKey: `dsaDecision:${decisionInput.reportId}:${result.reporterUserId}`,
    }));
    if (result.targetAuthorId && result.targetAuthorId !== result.reporterUserId) {
      notifications.push(writeUserNotification({
        notificationId: `dsaStatement_${decisionInput.reportId}_${result.targetAuthorId}`,
        targetUserId: result.targetAuthorId,
        type: "reportReviewed",
        title: "Content moderation decision",
        message: `A reasoned decision is available for case ${result.caseNumber}.`,
        severity: "info",
        actionType: "openDsaStatement",
        actionTargetId: decisionInput.reportId,
        sourceType: "feedback",
        sourceId: decisionInput.reportId,
        metadata: {reportId: decisionInput.reportId, caseNumber: result.caseNumber},
        dedupeKey: `dsaStatement:${decisionInput.reportId}:${result.targetAuthorId}`,
      }));
    }
    await Promise.all(notifications);

    const logReference = db.collection("systemLogs").doc();
    await logReference.set({
      id: logReference.id,
      createdAt: now,
      category: "moderation",
      severity: "info",
      severityRank: 1,
      eventType: "dsaDecisionRecorded",
      actorUserId: actor.uid,
      actorRole: "owner",
      targetType: "dsaCase",
      targetId: decisionInput.reportId,
      outcome: "success",
      summary: `DSA case ${result.caseNumber} decided: ${decisionInput.outcome}`,
      isReviewed: true,
      reviewedAt: now,
      reviewedByUserId: actor.uid,
      metadata: {caseNumber: result.caseNumber, outcome: decisionInput.outcome, automationUsed: false},
      retentionPolicy: "moderationDispute",
      isAppAdminReadable: false,
    });

    return {
      reportId: decisionInput.reportId,
      caseNumber: result.caseNumber,
      status: "decided",
      decidedAt: now.toDate().toISOString(),
      appealDeadline: appealDeadline.toDate().toISOString(),
    };
  }
);

export const submitDsaAppeal = onCall(
  callableOptions,
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    if (!isRecord(request.data)) throw new HttpsError("invalid-argument", "Appeal data is required.");
    const reportId = requiredString(request.data.reportId, "reportId", 200);
    const reason = requiredString(request.data.reason, "reason", 5_000);
    const reference = db.collection("dsaCases").doc(reportId);
    const feedbackReference = db.collection("feedback").doc(reportId);
    const messageReference = feedbackReference.collection("messages").doc();
    const now = Timestamp.now();
    let number = "";
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const data = snapshot.data() ?? {};
      if (!snapshot.exists || data.reporterUserId !== actor.uid) {
        throw new HttpsError("permission-denied", "Only the reporter can appeal this case.");
      }
      const decision = isRecord(data.decision) ? data.decision : {};
      const deadline = decision.appealDeadline as Timestamp | undefined;
      if (!deadline || deadline.toMillis() < now.toMillis()) {
        throw new HttpsError("failed-precondition", "The appeal period is unavailable or has expired.");
      }
      if (isRecord(data.appeal) && data.appeal.status === "pending") {
        throw new HttpsError("already-exists", "An appeal is already pending.");
      }
      number = String(data.caseNumber);
      transaction.update(reference, {
        status: "appealed",
        appeal: {status: "pending", reason, submittedAt: now, humanReviewRequired: true},
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
      });
      transaction.set(messageReference, {
        id: messageReference.id,
        feedbackId: reportId,
        senderId: actor.uid,
        senderDisplayName: "Reporter",
        senderRole: "user",
        text: `DSA appeal: ${reason}`.slice(0, 2_000),
        createdAt: now,
        isSystem: true,
      });
      transaction.update(feedbackReference, {
        status: "open",
        updatedAt: now,
        lastMessageText: `DSA appeal: ${reason}`.slice(0, 2_000),
        lastMessageAt: now,
        lastMessageByUserId: actor.uid,
        lastMessageByRole: "user",
        unreadForOwner: true,
        unreadForUser: false,
        "dsaCase.status": "appealed",
        "dsaCase.appeal": {status: "pending", reason, submittedAt: now},
      });
    });
    return {reportId, caseNumber: number, status: "appealed", submittedAt: now.toDate().toISOString()};
  }
);

export const getMyDsaStatement = onCall(
  callableOptions,
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    if (!isRecord(request.data)) throw new HttpsError("invalid-argument", "Statement request is required.");
    const reportId = requiredString(request.data.reportId, "reportId", 200);
    const snapshot = await db.collection("dsaCases").doc(reportId).get();
    const data = snapshot.data() ?? {};
    if (!snapshot.exists || data.targetAuthorId !== actor.uid) {
      throw new HttpsError("not-found", "The DSA statement was not found.");
    }
    const decision = isRecord(data.decision) ? data.decision : undefined;
    const appeal = isRecord(data.appeal) && data.appeal.status === "decided" ? data.appeal : undefined;
    return {
      id: reportId,
      caseNumber: String(data.caseNumber ?? reportId),
      status: String(data.status ?? "underReview"),
      sourceType: String(data.targetType ?? "content"),
      sourceId: String(data.targetId ?? ""),
      decision: decision ? {
        outcome: String(decision.outcome ?? ""),
        factsAndCircumstances: String(decision.factsAndCircumstances ?? ""),
        legalBasis: typeof decision.legalBasis === "string" ? decision.legalBasis : null,
        termsBasis: typeof decision.termsBasis === "string" ? decision.termsBasis : null,
        territorialScope: String(decision.territorialScope ?? ""),
        duration: String(decision.duration ?? ""),
        redressInformation: String(decision.redressInformation ?? ""),
        automationUsed: decision.automationUsed === true,
      } : null,
      appealDecision: appeal ? {
        outcome: String(appeal.outcome ?? ""),
        reason: String(appeal.decisionReason ?? ""),
        automationUsed: appeal.automationUsed === true,
      } : null,
    };
  }
);

export const decideDsaAppeal = onCall(
  callableOptions,
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    if (!isRecord(request.data)) throw new HttpsError("invalid-argument", "Appeal decision is required.");
    const reportId = requiredString(request.data.reportId, "reportId", 200);
    const outcome = enumValue(request.data.outcome, "outcome", new Set(["upheld", "changed"] as const));
    const reason = requiredString(request.data.reason, "reason", 5_000);
    if (request.data.humanReviewConfirmed !== true) {
      throw new HttpsError("failed-precondition", "Human review must be confirmed.");
    }
    const reference = db.collection("dsaCases").doc(reportId);
    const now = Timestamp.now();
    const result = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      const data = snapshot.data() ?? {};
      const appeal = isRecord(data.appeal) ? data.appeal : {};
      if (!snapshot.exists || appeal.status !== "pending") {
        throw new HttpsError("failed-precondition", "No pending appeal was found.");
      }
      const reopened = outcome === "changed";
      transaction.update(reference, {
        status: reopened ? "submitted" : "appealDecided",
        appeal: {
          ...appeal,
          status: "decided",
          outcome,
          decisionReason: reason,
          decidedAt: now,
          decidedByUserId: actor.uid,
          automationUsed: false,
          humanReviewConfirmed: true,
        },
        updatedAt: now,
        expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
        ...(reopened ? {
          previousDecision: data.decision ?? null,
          decision: FieldValue.delete(),
        } : {}),
      });
      transaction.update(db.collection("feedback").doc(reportId), {
        status: reopened ? "open" : "closed",
        updatedAt: now,
        lastMessageText: `Appeal ${outcome}: ${reason}`.slice(0, 2_000),
        lastMessageAt: now,
        lastMessageByUserId: actor.uid,
        lastMessageByRole: "owner",
        unreadForOwner: false,
        unreadForUser: true,
        "dsaCase.status": reopened ? "submitted" : "appealDecided",
        "dsaCase.appeal": {status: "decided", outcome, reason, decidedAt: now},
        ...(reopened ? {"dsaCase.decision": FieldValue.delete()} : {}),
      });
      const targetAuthorId = typeof data.targetAuthorId === "string" ? data.targetAuthorId : undefined;
      if (targetAuthorId) {
        transaction.set(
          db.collection("users").doc(targetAuthorId).collection("dsaStatements").doc(reportId),
          {
            id: reportId,
            caseNumber: String(data.caseNumber),
            status: reopened ? "underReview" : "appealDecided",
            sourceType: data.targetType ?? "content",
            sourceId: data.targetId ?? "",
            appealDecision: {
              outcome,
              reason,
              decidedAt: now,
              automationUsed: false,
              humanReviewConfirmed: true,
            },
            ...(reopened ? {decision: FieldValue.delete()} : {}),
            updatedAt: now,
            expiresAt: Timestamp.fromMillis(now.toMillis() + caseRetentionMilliseconds),
          },
          {merge: true}
        );
      }
      return {
        caseNumber: String(data.caseNumber),
        reporterUserId: typeof data.reporterUserId === "string" ? data.reporterUserId : undefined,
        targetAuthorId,
      };
    });
    const notifications: Promise<unknown>[] = [];
    if (result.reporterUserId) notifications.push(writeUserNotification({
      notificationId: `dsaAppealDecision_${reportId}_${result.reporterUserId}`,
      targetUserId: result.reporterUserId,
      type: "reportReviewed",
      title: "DSA appeal decision",
      message: `The appeal decision is available for case ${result.caseNumber}.`,
      severity: "info",
      actionType: "openFeedback",
      actionTargetId: reportId,
      sourceType: "feedback",
      sourceId: reportId,
      metadata: {reportId, caseNumber: result.caseNumber},
      dedupeKey: `dsaAppealDecision:${reportId}:${result.reporterUserId}`,
    }));
    if (result.targetAuthorId && result.targetAuthorId !== result.reporterUserId) {
      notifications.push(writeUserNotification({
        notificationId: `dsaAppealStatement_${reportId}_${result.targetAuthorId}`,
        targetUserId: result.targetAuthorId,
        type: "reportReviewed",
        title: "Content moderation appeal decision",
        message: `The appeal decision is available for case ${result.caseNumber}.`,
        severity: "info",
        actionType: "openDsaStatement",
        actionTargetId: reportId,
        sourceType: "feedback",
        sourceId: reportId,
        metadata: {reportId, caseNumber: result.caseNumber},
        dedupeKey: `dsaAppealStatement:${reportId}:${result.targetAuthorId}`,
      }));
    }
    await Promise.all(notifications);
    const logReference = db.collection("systemLogs").doc();
    await logReference.set({
      id: logReference.id,
      createdAt: now,
      category: "moderation",
      severity: "info",
      severityRank: 1,
      eventType: "dsaAppealDecisionRecorded",
      actorUserId: actor.uid,
      actorRole: "owner",
      targetType: "dsaCase",
      targetId: reportId,
      outcome: "success",
      summary: `DSA appeal ${result.caseNumber} decided: ${outcome}`,
      isReviewed: true,
      reviewedAt: now,
      reviewedByUserId: actor.uid,
      metadata: {caseNumber: result.caseNumber, outcome, automationUsed: false},
      retentionPolicy: "moderationDispute",
      isAppAdminReadable: false,
    });
    return {
      reportId,
      caseNumber: result.caseNumber,
      status: outcome === "changed" ? "submitted" : "appealDecided",
      decidedAt: now.toDate().toISOString(),
    };
  }
);
