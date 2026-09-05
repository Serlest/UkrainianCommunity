import {randomUUID} from "node:crypto";
import {logger} from "firebase-functions";
import {HttpsError, type CallableRequest} from "firebase-functions/v2/https";

export type AccessReason = "sign_in_required" | "email_unverified" | "account_inactive" | "session_refresh_required" | "account_changed" | "role_missing" | "object_missing" | "object_changed" | "invalid_request" | "route_disabled" | "operation_expired" | "limit_reached" | "network_unavailable" | "outcome_unknown";
const reasons = new Set<AccessReason>(["sign_in_required", "email_unverified", "account_inactive", "session_refresh_required", "account_changed", "role_missing", "object_missing", "object_changed", "invalid_request", "route_disabled", "operation_expired", "limit_reached", "network_unavailable", "outcome_unknown"]);

export function accessFailure(code: ConstructorParameters<typeof HttpsError>[0], reasonCode: AccessReason, message: string): HttpsError {
  return new HttpsError(code, message, {reasonCode});
}

export function accessReason(error: unknown): AccessReason {
  if (!(error instanceof HttpsError)) return "outcome_unknown";
  const explicit = (error.details as {reasonCode?: AccessReason} | undefined)?.reasonCode;
  if (explicit && reasons.has(explicit)) return explicit;
  if (error.message.includes("verified email")) return "email_unverified";
  if (error.message.includes("active account") || error.message.includes("profile no longer exists") || error.message.includes("profile does not exist")) return "account_inactive";
  if (error.message.includes("TOTP-authenticated")) return "session_refresh_required";
  if (error.message.includes("account changed")) return "account_changed";
  if (error.message.includes("not enabled")) return "route_disabled";
  return ({unauthenticated: "sign_in_required", "permission-denied": "role_missing", "not-found": "object_missing",
    aborted: "object_changed", "invalid-argument": "invalid_request", "already-exists": "invalid_request",
    "resource-exhausted": "limit_reached", unavailable: "network_unavailable", "deadline-exceeded": "outcome_unknown"} as Partial<Record<string, AccessReason>>)[error.code] ?? "outcome_unknown";
}

/** Structured logs contain no UID, object ID, user text, URL, token or photo bytes. */
export async function withAccessDiagnostics<T>(request: CallableRequest, action: string, operation: (correlationId: string) => Promise<T>): Promise<T> {
  const correlationId = randomUUID();
  const start = performance.now();
  const version = request.data?.clientVersion;
  const clientVersion = typeof version === "string" && /^[0-9.]{1,24}$/.test(version) ? version : "unknown";
  try {
    const result = await operation(correlationId);
    logger.info("organization_access_operation", {action, clientVersion, correlationId, outcome: "success", durationMs: Math.round(performance.now() - start)});
    return result;
  } catch (error) {
    const reasonCode = accessReason(error);
    const code = error instanceof HttpsError ? error.code : "internal";
    logger.warn("organization_access_operation", {action, clientVersion, correlationId, outcome: "failure", code, reasonCode, durationMs: Math.round(performance.now() - start)});
    throw new HttpsError(code, error instanceof HttpsError ? error.message : "The operation could not be confirmed.", {reasonCode, correlationId});
  }
}

export function recordAccessComparison(action: string, client: boolean, server: boolean, correlationId: string): void {
  logger.info("organization_access_comparison", {action, client, server, correlationId, source: "client_reported"});
}
