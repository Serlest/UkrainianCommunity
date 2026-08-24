import type {DocumentData, Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

export const analyticsSchemaVersion = 2;
export const analyticsSchemaStateCollection = "analyticsSchemaState";
export const analyticsSchemaStateDocumentID = "current";

export type AnalyticsSchemaCutoverStatus =
  | "prepared"
  | "finalizing"
  | "complete";

export interface AnalyticsSchemaGateState {
  schemaVersion: number;
  status: AnalyticsSchemaCutoverStatus;
  generation: string;
  cutoverDay: string;
}

export function analyticsSchemaGateState(
  data: DocumentData | undefined
): AnalyticsSchemaGateState | undefined {
  const schemaVersion = data?.schemaVersion;
  const status = data?.status;
  const generation = data?.generation;
  const cutoverDay = data?.cutoverDay;
  if (schemaVersion !== analyticsSchemaVersion ||
    (status !== "prepared" && status !== "finalizing" && status !== "complete") ||
    typeof generation !== "string" ||
    generation.trim().length === 0 ||
    typeof cutoverDay !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(cutoverDay)) {
    return undefined;
  }

  return {
    schemaVersion,
    status,
    generation: generation.trim(),
    cutoverDay,
  };
}

export function isAnalyticsSchemaReady(
  data: DocumentData | undefined
): boolean {
  return analyticsSchemaGateState(data)?.status === "complete";
}

export async function loadAnalyticsSchemaGateState(
  database: Firestore
): Promise<AnalyticsSchemaGateState | undefined> {
  const snapshot = await database
    .collection(analyticsSchemaStateCollection)
    .doc(analyticsSchemaStateDocumentID)
    .get();
  return analyticsSchemaGateState(snapshot.data());
}

export async function requireAnalyticsSchemaReady(
  database: Firestore
): Promise<void> {
  const state = await loadAnalyticsSchemaGateState(database);
  if (state?.status !== "complete") {
    // `unavailable` is intentionally retryable. Clients retain their bounded
    // analytics outbox while the operator freezes v1 and finalizes the dated
    // v2 schema, so the cutover does not create an event-loss window.
    throw new HttpsError(
      "unavailable",
      "Analytics is temporarily paused for a schema transition."
    );
  }
}
