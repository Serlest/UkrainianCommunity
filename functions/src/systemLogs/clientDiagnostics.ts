import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: true,
};

const quotaWindowMilliseconds = 15 * 60 * 1_000;
const quotaMaximumWrites = 60;

const allowedFields = new Set([
  "eventType", "severity", "targetType", "targetId", "targetTitle",
  "organizationId", "organizationName", "summary", "technicalMessage",
  "errorCode", "moduleName", "screenName", "operationName", "appVersion",
  "osVersion", "deviceModel", "metadata", "correlationId",
]);

const allowedSeverities = new Set([
  "debug", "info", "notice", "warning", "error", "critical",
]);

export const writeClientDiagnostic = onCall(
  callableOptions,
  async (request): Promise<{id: string; createdAt: string}> => {
    const actor = await requireVerifiedActiveUser(request);
    const input = parseDiagnostic(request.data);
    const createdAt = Timestamp.now();
    const reference = db.collection("systemLogs").doc();
    const actorRole = normalizedActorRole(actor.permissions.globalRole);

    const quotaReference = db.collection("systemLogDiagnosticRateLimits").doc(actor.uid);
    await db.runTransaction(async (transaction) => {
      const quotaSnapshot = await transaction.get(quotaReference);
      const quota = quotaSnapshot.data();
      const previousStart = quota?.windowStartedAt instanceof Timestamp ?
        quota.windowStartedAt.toMillis() : 0;
      const isCurrentWindow = createdAt.toMillis() - previousStart < quotaWindowMilliseconds;
      const previousCount = isCurrentWindow && typeof quota?.count === "number" ? quota.count : 0;
      if (previousCount >= quotaMaximumWrites) {
        throw new HttpsError("resource-exhausted", "Diagnostic log rate limit exceeded.");
      }

      transaction.set(quotaReference, {
        windowStartedAt: isCurrentWindow ? quota?.windowStartedAt : createdAt,
        count: previousCount + 1,
        updatedAt: createdAt,
      });
      transaction.set(reference, {
        id: reference.id,
        createdAt,
        category: "diagnostics",
        severity: input.severity,
        severityRank: severityRank(input.severity),
        eventType: input.eventType,
        actorUserId: actor.uid,
        actorRole,
        targetType: input.targetType,
        summary: input.summary,
        outcome: "failed",
        isReviewed: false,
        metadata: input.metadata,
        retentionPolicy: "technicalError",
        isAppAdminReadable: actorRole !== "owner",
        ...optionalFields(input),
      });
    });

    return {id: reference.id, createdAt: createdAt.toDate().toISOString()};
  }
);

interface DiagnosticInput {
  eventType: string;
  severity: string;
  targetType: string;
  targetId?: string;
  targetTitle?: string;
  organizationId?: string;
  organizationName?: string;
  summary: string;
  technicalMessage?: string;
  errorCode?: string;
  moduleName?: string;
  screenName?: string;
  operationName?: string;
  appVersion?: string;
  osVersion?: string;
  deviceModel?: string;
  metadata: Record<string, string>;
  correlationId?: string;
}

export function parseDiagnostic(value: unknown): DiagnosticInput {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  if (Object.keys(value).some((key) => !allowedFields.has(key))) {
    throw new HttpsError("invalid-argument", "Request payload has unsupported fields.");
  }

  const severity = requiredString(value.severity, "severity", 16);
  if (!allowedSeverities.has(severity)) {
    throw new HttpsError("invalid-argument", "severity is not supported.");
  }

  return {
    eventType: requiredString(value.eventType, "eventType", 80),
    severity,
    targetType: requiredString(value.targetType, "targetType", 80),
    targetId: optionalString(value.targetId, "targetId", 200),
    targetTitle: optionalString(value.targetTitle, "targetTitle", 300),
    organizationId: optionalString(value.organizationId, "organizationId", 200),
    organizationName: optionalString(value.organizationName, "organizationName", 300),
    summary: requiredString(value.summary, "summary", 512),
    technicalMessage: optionalString(value.technicalMessage, "technicalMessage", 1_520),
    errorCode: optionalString(value.errorCode, "errorCode", 160),
    moduleName: optionalString(value.moduleName, "moduleName", 160),
    screenName: optionalString(value.screenName, "screenName", 160),
    operationName: optionalString(value.operationName, "operationName", 160),
    appVersion: optionalString(value.appVersion, "appVersion", 80),
    osVersion: optionalString(value.osVersion, "osVersion", 160),
    deviceModel: optionalString(value.deviceModel, "deviceModel", 160),
    metadata: stringMap(value.metadata),
    correlationId: optionalString(value.correlationId, "correlationId", 200),
  };
}

function optionalFields(input: DiagnosticInput): Record<string, string> {
  const result: Record<string, string> = {};
  for (const field of [
    "targetId", "targetTitle", "organizationId", "organizationName",
    "technicalMessage", "errorCode", "moduleName", "screenName",
    "operationName", "appVersion", "osVersion", "deviceModel", "correlationId",
  ] as const) {
    const value = input[field];
    if (value !== undefined) result[field] = value;
  }
  return result;
}

function stringMap(value: unknown): Record<string, string> {
  if (value === undefined) return {};
  if (!isRecord(value) || Object.keys(value).length > 40) {
    throw new HttpsError("invalid-argument", "metadata must be a small string map.");
  }
  const result: Record<string, string> = {};
  for (const [key, entry] of Object.entries(value)) {
    if (typeof entry !== "string" || key.length === 0 || key.length > 100 || entry.length > 320) {
      throw new HttpsError("invalid-argument", "metadata contains an invalid entry.");
    }
    result[key] = entry;
  }
  return result;
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  const normalized = optionalString(value, field, maxLength);
  if (normalized === undefined) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return normalized;
}

function optionalString(value: unknown, field: string, maxLength: number): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length === 0) return undefined;
  if (normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return normalized;
}

function severityRank(value: string): number {
  return ["debug", "info", "notice", "warning", "error", "critical"].indexOf(value);
}

function normalizedActorRole(value: unknown): "owner" | "admin" | "user" {
  if (value === "owner" || value === "admin") return value;
  return "user";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
