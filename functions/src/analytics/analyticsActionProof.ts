import {createHash} from "node:crypto";

import {Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const analyticsActionProofCollection = "analyticsActionProofs";
export const analyticsActionProofRetentionHours = 48;

export type AnalyticsActionEventName =
  | "news_like"
  | "news_bookmark"
  | "event_register"
  | "event_bookmark"
  | "organization_follow"
  | "organization_bookmark";

export interface AnalyticsActionProofBinding {
  proofID: string;
  eventName: AnalyticsActionEventName;
  contentID: string;
  actorBinding: string;
  sessionBinding: string;
}

export interface ValidatedAnalyticsActionProof {
  createdAt: Date;
  expiresAt: Date;
}

const maximumIdentifierLength = 512;
const maximumFutureSkewMilliseconds = 5 * 60 * 1_000;
const minimumProofLifetimeMilliseconds = 47 * 60 * 60 * 1_000;
const maximumProofLifetimeMilliseconds =
  analyticsActionProofRetentionHours * 60 * 60 * 1_000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const sha256Pattern = /^[0-9a-f]{64}$/;
const actionNames = new Set<AnalyticsActionEventName>([
  "news_like",
  "news_bookmark",
  "event_register",
  "event_bookmark",
  "organization_follow",
  "organization_bookmark",
]);

export function optionalAnalyticsActionProofBinding(
  value: unknown
): AnalyticsActionProofBinding | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (!isRecord(value)) {
    throw invalidProofBinding();
  }

  const allowedFields = new Set([
    "proofID",
    "eventName",
    "contentID",
    "actorBinding",
    "sessionBinding",
  ]);
  if (Object.keys(value).length !== allowedFields.size
    || Object.keys(value).some((field) => !allowedFields.has(field))) {
    throw invalidProofBinding();
  }

  const proofID = requiredString(value.proofID);
  const eventName = requiredString(value.eventName);
  const contentID = requiredString(value.contentID);
  const actorBinding = requiredString(value.actorBinding);
  const sessionBinding = requiredString(value.sessionBinding);
  if (!uuidPattern.test(proofID)
    || !actionNames.has(eventName as AnalyticsActionEventName)
    || contentID.length > maximumIdentifierLength
    || contentID.includes("/")
    || !sha256Pattern.test(actorBinding)
    || !sha256Pattern.test(sessionBinding)) {
    throw invalidProofBinding();
  }

  return {
    proofID,
    eventName: eventName as AnalyticsActionEventName,
    contentID,
    actorBinding,
    sessionBinding,
  };
}

export function requireMatchingAnalyticsActionProofBinding(
  value: unknown,
  expectedEventName: AnalyticsActionEventName,
  expectedContentID: string
): AnalyticsActionProofBinding | undefined {
  const binding = optionalAnalyticsActionProofBinding(value);
  if (binding === undefined) {
    return undefined;
  }
  if (binding.eventName !== expectedEventName
    || binding.contentID !== expectedContentID) {
    throw invalidProofBinding();
  }
  return binding;
}

export function analyticsActorBinding(uid: string, proofID: string): string {
  return digest(["actor", uid, proofID]);
}

export function analyticsSessionBinding(consentID: string, proofID: string): string {
  return digest(["session", consentID, proofID]);
}

export function analyticsActionReceiptID(proofID: string): string {
  return digest(["action-proof-receipt", proofID]);
}

export function isMatchingAnalyticsActionReceipt(
  data: DocumentData | undefined,
  binding: AnalyticsActionProofBinding,
  uid: string,
  contentType: string
): boolean {
  return data !== undefined
    && data.receiptKind === "actionProof"
    && data.proofId === binding.proofID
    && data.actorBinding === analyticsActorBinding(uid, binding.proofID)
    && data.eventName === binding.eventName
    && data.contentType === contentType
    && data.contentID === binding.contentID
    && data.sessionBinding === binding.sessionBinding;
}

export function validateAnalyticsActionProof(
  data: DocumentData | undefined,
  binding: AnalyticsActionProofBinding,
  uid: string,
  consentID: string,
  receivedAt: Date
): ValidatedAnalyticsActionProof {
  if (data === undefined
    || data.proofId !== binding.proofID
    || data.eventName !== binding.eventName
    || data.contentId !== binding.contentID
    || data.actorBinding !== analyticsActorBinding(uid, binding.proofID)
    || data.actorBinding !== binding.actorBinding
    || data.sessionBinding !== binding.sessionBinding
    || data.sessionBinding !== analyticsSessionBinding(consentID, binding.proofID)) {
    throw invalidActionProof();
  }

  const createdAt = timestampDate(data.createdAt);
  const expiresAt = timestampDate(data.expiresAt);
  if (createdAt === undefined || expiresAt === undefined) {
    throw invalidActionProof();
  }

  const lifetimeMilliseconds = expiresAt.getTime() - createdAt.getTime();
  if (createdAt.getTime() > receivedAt.getTime() + maximumFutureSkewMilliseconds
    || receivedAt.getTime() >= expiresAt.getTime()
    || lifetimeMilliseconds <= minimumProofLifetimeMilliseconds
    || lifetimeMilliseconds > maximumProofLifetimeMilliseconds) {
    throw invalidActionProof();
  }

  return {createdAt, expiresAt};
}

export function analyticsActionProofDocumentData(
  binding: AnalyticsActionProofBinding,
  uid: string,
  createdAt: Date
): DocumentData {
  return {
    proofId: binding.proofID,
    eventName: binding.eventName,
    contentId: binding.contentID,
    actorBinding: analyticsActorBinding(uid, binding.proofID),
    sessionBinding: binding.sessionBinding,
    createdAt: Timestamp.fromDate(createdAt),
    expiresAt: Timestamp.fromMillis(
      createdAt.getTime() + maximumProofLifetimeMilliseconds
    ),
  };
}

function requiredString(value: unknown): string {
  if (typeof value !== "string") {
    throw invalidProofBinding();
  }
  const normalized = value.trim();
  if (normalized.length === 0) {
    throw invalidProofBinding();
  }
  return normalized;
}

function timestampDate(value: unknown): Date | undefined {
  if (!(value instanceof Timestamp)) {
    return undefined;
  }
  const date = value.toDate();
  return Number.isFinite(date.getTime()) ? date : undefined;
}

function invalidProofBinding(): HttpsError {
  return new HttpsError(
    "invalid-argument",
    "The analytics action proof binding is invalid."
  );
}

function invalidActionProof(): HttpsError {
  return new HttpsError(
    "failed-precondition",
    "The tracked action could not be verified."
  );
}

function digest(parts: string[]): string {
  return createHash("sha256").update(parts.join("\u0000")).digest("hex");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
