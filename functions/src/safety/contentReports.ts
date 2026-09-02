import { createHash } from "node:crypto";

import { type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireVerifiedActiveUser } from "../auth/context";
import { db } from "../firebase/admin";
import {createDsaCase, type DsaNoticeCategory} from "./dsaCases";

export type ContentReportTargetType = "news" | "event" | "organization" | "comment";
export type ContentReportParentType = "news" | "event" | "organization";
export type ContentReportReason =
  | "harassment"
  | "hate"
  | "violence"
  | "sexual"
  | "spam"
  | "misinformation"
  | "privacy"
  | "other";

export interface ContentReportRequest {
  targetType: ContentReportTargetType;
  targetId: string;
  parentType?: ContentReportParentType;
  parentId?: string;
  reason: ContentReportReason;
  illegalExplanation: string;
  legalBasis?: string;
  evidence?: string;
  goodFaithConfirmed: true;
}

interface ResolvedReportTarget {
  authorId?: string;
  title: string;
  excerpt: string;
}

interface ContentReportResponse {
  reportId: string;
  status: "open";
  submittedAt: string;
  wasDuplicate: boolean;
  caseNumber: string;
  accessToken: string;
  acknowledgementAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: false,
};
const contentTypes = new Set<ContentReportTargetType>([
  "news",
  "event",
  "organization",
  "comment",
]);
const parentTypes = new Set<ContentReportParentType>([
  "news",
  "event",
  "organization",
]);
const reportReasons = new Set<ContentReportReason>([
  "harassment",
  "hate",
  "violence",
  "sexual",
  "spam",
  "misinformation",
  "privacy",
  "other",
]);
const urgentReasons = new Set<ContentReportReason>([
  "harassment",
  "hate",
  "violence",
  "sexual",
  "privacy",
]);
const parentCollections: Record<ContentReportParentType, string> = {
  news: "news",
  event: "events",
  organization: "organizations",
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${field} has an invalid length.`);
  }
  return normalized;
}

function optionalString(value: unknown, field: string, maximumLength: number): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return normalized.length > 0 ? normalized : undefined;
}

function documentId(value: unknown, field: string): string {
  const id = requiredString(value, field, 256);
  if (id.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} contains unsupported characters.`);
  }
  return id;
}

function enumValue<T extends string>(value: unknown, field: string, values: Set<T>): T {
  if (typeof value !== "string" || !values.has(value as T)) {
    throw new HttpsError("invalid-argument", `${field} is not supported.`);
  }
  return value as T;
}

export function parseContentReportRequest(value: unknown): ContentReportRequest {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "The report must be an object.");
  }

  const targetType = enumValue(value.targetType, "targetType", contentTypes);
  const parentType = value.parentType === undefined || value.parentType === null
    ? undefined
    : enumValue(value.parentType, "parentType", parentTypes);
  const parentId = value.parentId === undefined || value.parentId === null
    ? undefined
    : documentId(value.parentId, "parentId");

  if (targetType === "comment" && (!parentType || !parentId)) {
    throw new HttpsError(
      "invalid-argument",
      "parentType and parentId are required when reporting a comment."
    );
  }
  if (targetType !== "comment" && (parentType || parentId)) {
    throw new HttpsError(
      "invalid-argument",
      "Parent fields are only supported when reporting a comment."
    );
  }
  if (value.goodFaithConfirmed !== true) {
    throw new HttpsError("failed-precondition", "The good-faith declaration is required.");
  }

  return {
    targetType,
    targetId: documentId(value.targetId, "targetId"),
    parentType,
    parentId,
    reason: enumValue(value.reason, "reason", reportReasons),
    illegalExplanation: requiredString(value.illegalExplanation, "illegalExplanation", 5_000),
    legalBasis: optionalString(value.legalBasis, "legalBasis", 1_000),
    evidence: optionalString(value.evidence, "evidence", 5_000),
    goodFaithConfirmed: true,
  };
}

export function reportSlaHours(reason: ContentReportReason): number {
  return urgentReasons.has(reason) ? 24 : 72;
}

export function contentReportDocumentId(
  reporterId: string,
  report: Pick<ContentReportRequest, "targetType" | "targetId" | "parentType" | "parentId">
): string {
  const identity = [
    reporterId,
    report.targetType,
    report.parentType ?? "-",
    report.parentId ?? "-",
    report.targetId,
  ].join("|");
  return `report_${createHash("sha256").update(identity).digest("hex").slice(0, 40)}`;
}

function normalizedText(value: unknown, fallback: string, maximumLength: number): string {
  if (typeof value !== "string") {
    return fallback;
  }
  const valueWithoutExtraWhitespace = value.replace(/\s+/g, " ").trim();
  return valueWithoutExtraWhitespace.length > 0
    ? valueWithoutExtraWhitespace.slice(0, maximumLength)
    : fallback;
}

function ensureTargetIsAvailable(data: DocumentData | undefined): DocumentData {
  if (!data || data.isDeleted === true || data.deletedAt) {
    throw new HttpsError("not-found", "The reported content is no longer available.");
  }
  return data;
}

function ensurePublicTarget(data: DocumentData | undefined): DocumentData {
  const available = ensureTargetIsAvailable(data);
  if (available.moderationStatus !== "approved") {
    throw new HttpsError("not-found", "The reported content is not publicly available.");
  }
  return available;
}

function resolvedParentTarget(type: ContentReportParentType, data: DocumentData): ResolvedReportTarget {
  switch (type) {
  case "news":
    return {
      authorId: optionalDocumentValue(data.authorId),
      title: normalizedText(data.title, "News", 160),
      excerpt: normalizedText(data.summary ?? data.subtitle ?? data.body, "", 280),
    };
  case "event":
    return {
      authorId: optionalDocumentValue(data.authorId),
      title: normalizedText(data.title, "Event", 160),
      excerpt: normalizedText(data.summary ?? data.details, "", 280),
    };
  case "organization":
    return {
      authorId: optionalDocumentValue(data.ownerId ?? data.submittedByUserId),
      title: normalizedText(data.name, "Organization", 160),
      excerpt: normalizedText(data.shortDescription ?? data.description, "", 280),
    };
  }
}

function optionalDocumentValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

async function resolveReportTarget(report: ContentReportRequest): Promise<ResolvedReportTarget> {
  if (report.targetType === "comment") {
    const parentType = report.parentType as ContentReportParentType;
    const parentId = report.parentId as string;
    const parentReference = db.collection(parentCollections[parentType]).doc(parentId);
    const [parentSnapshot, commentSnapshot] = await Promise.all([
      parentReference.get(),
      parentReference.collection("comments").doc(report.targetId).get(),
    ]);
    const parent = resolvedParentTarget(parentType, ensurePublicTarget(parentSnapshot.data()));
    const comment = ensureTargetIsAvailable(commentSnapshot.data());
    if (comment.moderationStatus !== undefined && comment.moderationStatus !== "approved") {
      throw new HttpsError("not-found", "The reported comment is not publicly available.");
    }
    if (comment.parentType !== parentType || comment.parentId !== parentId) {
      throw new HttpsError("failed-precondition", "The comment parent does not match the report.");
    }
    return {
      authorId: optionalDocumentValue(comment.authorId),
      title: parent.title,
      excerpt: normalizedText(comment.text ?? comment.body, "Comment", 280),
    };
  }

  const parentType = report.targetType as ContentReportParentType;
  const snapshot = await db.collection(parentCollections[parentType]).doc(report.targetId).get();
  return resolvedParentTarget(parentType, ensurePublicTarget(snapshot.data()));
}

function noticeCategory(reason: ContentReportReason): DsaNoticeCategory {
  switch (reason) {
  case "hate": return "hate";
  case "violence": return "terrorism";
  case "sexual": return "childSafety";
  case "privacy": return "privacy";
  case "spam": return "fraud";
  case "harassment": return "defamation";
  case "misinformation":
  case "other": return "other";
  }
}

function exactContentLocation(report: ContentReportRequest): string {
  if (report.targetType === "comment") {
    return `ukrainiancommunity://${report.parentType}/${report.parentId}/comments/${report.targetId}`;
  }
  return `ukrainiancommunity://${report.targetType}/${report.targetId}`;
}

export const submitContentReport = onCall(
  callableOptions,
  async (request): Promise<ContentReportResponse> => {
    const actor = await requireVerifiedActiveUser(request);
    const report = parseContentReportRequest(request.data);
    const [target, userSnapshot] = await Promise.all([
      resolveReportTarget(report),
      db.collection("users").doc(actor.uid).get(),
    ]);
    if (target.authorId === actor.uid) {
      throw new HttpsError("failed-precondition", "You cannot report your own content.");
    }

    const user = userSnapshot.data() ?? {};
    const userDisplayName = normalizedText(
      user.displayName ?? user.name,
      "Community member",
      120
    );
    const receipt = await createDsaCase({
      exactLocation: exactContentLocation(report),
      contentDescription: target.title,
      illegalExplanation: report.illegalExplanation,
      legalBasis: report.legalBasis,
      evidence: report.evidence,
      category: noticeCategory(report.reason),
      reporterName: userDisplayName,
      reporterEmail: typeof actor.token.email === "string" ? actor.token.email : undefined,
      contactException: false,
      goodFaithConfirmed: true,
      preferredLanguage: user.language === "uk" ? "uk" : "de",
      reporterUserId: actor.uid,
      targetType: report.targetType,
      targetId: report.targetId,
      parentType: report.parentType,
      parentId: report.parentId,
      targetAuthorId: target.authorId,
      targetTitle: target.title,
      targetExcerpt: target.excerpt,
      reason: report.reason,
      isUrgent: urgentReasons.has(report.reason),
    });

    return {
      reportId: receipt.reportId,
      status: "open",
      submittedAt: receipt.submittedAt,
      wasDuplicate: false,
      caseNumber: receipt.caseNumber,
      accessToken: receipt.accessToken,
      acknowledgementAt: receipt.acknowledgementAt,
    };
  }
);
