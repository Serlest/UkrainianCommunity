import { getMessaging } from "firebase-admin/messaging";
import type { BaseMessage, BatchResponse, SendResponse } from "firebase-admin/messaging";
import {messageForAndroid} from "./androidPush";

const fcmMulticastLimit = 500;
const firebaseInstallationIDLength = 22;
const firebaseInstallationIDPattern = /^[A-Za-z0-9_-]{22}$/;

export type PushRegistrationKind = "fid" | "token";

export interface StoredPushRegistration {
  documentId: string;
  identifier: string;
  kind: PushRegistrationKind;
  platform?: "android";
}

interface PushRegistrationDocumentReference {
  delete(): Promise<unknown>;
}

export interface PushRegistrationDocument {
  id: string;
  data(): FirebaseFirestore.DocumentData;
  ref: PushRegistrationDocumentReference;
}

export type PushMulticastMessage = BaseMessage & {
  tokens: string[];
  fids: string[];
};

export type PushMulticastSender = (
  message: PushMulticastMessage
) => Promise<BatchResponse>;

interface DeliveryTarget extends StoredPushRegistration {
  documentReferences: PushRegistrationDocumentReference[];
  supersededLegacyDocumentReferences: PushRegistrationDocumentReference[];
}

interface DeliveryBatch {
  tokens: DeliveryTarget[];
  fids: DeliveryTarget[];
}

interface ConsolidatedDeliveryPlan {
  targets: DeliveryTarget[];
  malformedFIDDocumentReferences: PushRegistrationDocumentReference[];
}

export interface PushDeliveryResult {
  targetCount: number;
  successCount: number;
  failureCount: number;
}

/**
 * Decodes both generations of the persisted schema. Documents created by app
 * versions before the FID migration do not contain `registrationType` and are
 * intentionally treated as legacy registration tokens.
 */
export function parseStoredPushRegistration(
  documentId: string,
  data: FirebaseFirestore.DocumentData
): StoredPushRegistration | undefined {
  const identifier = typeof data.token === "string" ? data.token.trim() : "";
  if (identifier.length === 0) {
    return undefined;
  }

  const rawKind = data.registrationType;
  if (rawKind !== undefined && rawKind !== "fid" && rawKind !== "token") {
    return undefined;
  }
  if (data.platform !== undefined && data.platform !== "ios" && data.platform !== "android") {
    return undefined;
  }

  const kind = rawKind === "fid" ? "fid" : "token";
  if (kind === "fid" && !isStrictFirebaseInstallationID(identifier)) {
    return undefined;
  }

  return {
    documentId,
    identifier,
    kind,
    ...(data.platform === "android" ? {platform: "android" as const} : {}),
  };
}

export function pushRegistrationBatches(
  registrations: StoredPushRegistration[],
  limit = fcmMulticastLimit
): Array<{ tokens: StoredPushRegistration[]; fids: StoredPushRegistration[] }> {
  if (!Number.isSafeInteger(limit) || limit <= 0 || limit > fcmMulticastLimit) {
    throw new Error(`Push registration batch limit must be between 1 and ${fcmMulticastLimit}.`);
  }

  const uniqueRegistrations = Array.from(
    registrations.reduce((result, registration) => {
      const key = `${registration.kind}:${registration.identifier}`;
      if (!result.has(key)) {
        result.set(key, registration);
      }
      return result;
    }, new Map<string, StoredPushRegistration>()).values()
  );

  const batches: Array<{ tokens: StoredPushRegistration[]; fids: StoredPushRegistration[] }> = [];
  for (let index = 0; index < uniqueRegistrations.length; index += limit) {
    const values = uniqueRegistrations.slice(index, index + limit);
    batches.push({
      tokens: values.filter((registration) => registration.kind === "token"),
      fids: values.filter((registration) => registration.kind === "fid"),
    });
  }
  return batches;
}

export function isPermanentPushRegistrationFailure(response: SendResponse): boolean {
  const code = response.error?.code;
  return code === "messaging/invalid-registration-token"
    || code === "messaging/registration-token-not-registered";
}

export type PushResultObserver = (documentIds: string[], response: SendResponse) => Promise<void>;

export function isRetryablePushFailure(response: SendResponse): boolean {
  return !response.success && [
    "messaging/server-unavailable", "messaging/internal-error", "messaging/unknown-error",
    "messaging/quota-exceeded", "messaging/message-rate-exceeded",
    "messaging/device-message-rate-exceeded", "app/network-error", "app/network-timeout",
  ].includes(response.error?.code ?? "messaging/unknown-error");
}

export async function sendPushToRegistrationDocuments(
  documents: readonly PushRegistrationDocument[],
  message: BaseMessage,
  sendEachForMulticast: PushMulticastSender = sendWithFirebaseAdmin,
  observeResult?: PushResultObserver
): Promise<PushDeliveryResult> {
  const plan = consolidatedDeliveryPlan(documents);
  await removeMalformedFIDRegistrations(plan.malformedFIDDocumentReferences);
  const targets = plan.targets;
  if (targets.length === 0) {
    return { targetCount: 0, successCount: 0, failureCount: 0 };
  }

  const batches = deliveryBatches(targets);
  const results = await Promise.all(batches.map(async (batch) => {
    const orderedTargets = [...batch.tokens, ...batch.fids];
    const response = await sendEachForMulticast({
      ...(orderedTargets[0].platform === "android" ? messageForAndroid(message) : message),
      tokens: batch.tokens.map((registration) => registration.identifier),
      fids: batch.fids.map((registration) => registration.identifier),
    });

    if (response.responses.length !== orderedTargets.length) {
      throw new Error("Push response count mismatch; delivery cannot be acknowledged.");
    }
    for (let index = 0; index < response.responses.length; index++) {
      const result = response.responses[index];
      if (!result.success) {
        // Never log tokens, FIDs, notification bodies or provider error messages.
        console.error("Push provider rejected notification", {
          code: result.error?.code ?? "messaging/unknown-error",
          registrationKind: orderedTargets[index].kind,
          retryable: isRetryablePushFailure(result),
        });
      }
      await observeResult?.(
        [...orderedTargets[index].documentReferences,
          ...(result.success ? orderedTargets[index].supersededLegacyDocumentReferences : [])].map((ref) => {
          const document = documents.find((value) => value.ref === ref);
          return document!.id;
        }), result
      );
    }
    await removeObsoleteRegistrations(orderedTargets, response.responses);
    return response;
  }));

  return results.reduce<PushDeliveryResult>((total, result) => ({
    targetCount: total.targetCount + result.responses.length,
    successCount: total.successCount + result.successCount,
    failureCount: total.failureCount + result.failureCount,
  }), { targetCount: 0, successCount: 0, failureCount: 0 });
}

function sendWithFirebaseAdmin(message: PushMulticastMessage): Promise<BatchResponse> {
  return getMessaging().sendEachForMulticast(message);
}

function consolidatedDeliveryPlan(
  documents: readonly PushRegistrationDocument[]
): ConsolidatedDeliveryPlan {
  const targets = new Map<string, DeliveryTarget>();
  const malformedFIDDocumentReferences: PushRegistrationDocumentReference[] = [];

  for (const document of documents) {
    const data = document.data();
    const registration = parseStoredPushRegistration(document.id, data);
    if (!registration) {
      if (isMalformedExplicitFID(data)) {
        malformedFIDDocumentReferences.push(document.ref);
      }
      continue;
    }

    const key = `${registration.kind}:${registration.identifier}`;
    const existing = targets.get(key);
    if (existing) {
      existing.documentReferences.push(document.ref);
    } else {
      targets.set(key, {
        ...registration,
        documentReferences: [document.ref],
        supersededLegacyDocumentReferences: [],
      });
    }
  }

  suppressSameInstallationLegacyTokens(targets);
  return {
    targets: Array.from(targets.values()),
    malformedFIDDocumentReferences,
  };
}

/**
 * Firebase Messaging 12.18 considers a legacy token current for an installation
 * when the token begins with that installation's 22-character FID. Correlating
 * on that strict SDK invariant lets us avoid a duplicate delivery without ever
 * guessing from device metadata or removing registrations for another device.
 */
function suppressSameInstallationLegacyTokens(
  targets: Map<string, DeliveryTarget>
): void {
  const fidTargets = new Map(
    Array.from(targets.values())
      .filter((target) => target.kind === "fid" && isStrictFirebaseInstallationID(target.identifier))
      .map((target) => [target.identifier, target])
  );

  for (const [key, target] of targets) {
    if (target.kind !== "token" || target.identifier.length <= firebaseInstallationIDLength) {
      continue;
    }

    const prefix = target.identifier.slice(0, firebaseInstallationIDLength);
    const fidTarget = fidTargets.get(prefix);
    if (!fidTarget || !target.identifier.startsWith(fidTarget.identifier)) {
      continue;
    }

    fidTarget.supersededLegacyDocumentReferences.push(...target.documentReferences);
    targets.delete(key);
  }
}

export function isStrictFirebaseInstallationID(identifier: string): boolean {
  return identifier.length === firebaseInstallationIDLength
    && firebaseInstallationIDPattern.test(identifier);
}

function isMalformedExplicitFID(data: FirebaseFirestore.DocumentData): boolean {
  if (data.registrationType !== "fid"
    || (data.platform !== undefined && data.platform !== "ios" && data.platform !== "android")) {
    return false;
  }
  const identifier = typeof data.token === "string" ? data.token.trim() : "";
  return !isStrictFirebaseInstallationID(identifier);
}

function deliveryBatches(targets: DeliveryTarget[]): DeliveryBatch[] {
  // Keep APNs/legacy envelopes byte-for-byte compatible and prevent a common
  // literal notification from overriding Android's native localization keys.
  const platformGroups = [targets.filter((target) => target.platform !== "android"),
    targets.filter((target) => target.platform === "android")];
  return platformGroups.flatMap((values) => pushRegistrationBatches(values)).map((batch) => ({
    tokens: batch.tokens as DeliveryTarget[],
    fids: batch.fids as DeliveryTarget[],
  }));
}

async function removeObsoleteRegistrations(
  targets: DeliveryTarget[],
  responses: SendResponse[]
): Promise<void> {
  if (responses.length !== targets.length) {
    console.error("Push registration response count did not match the requested targets.", {
      responseCount: responses.length,
      targetCount: targets.length,
    });
    return;
  }

  const references = responses.flatMap((response, index) => {
    const target = targets[index];
    if (!target) {
      return [];
    }

    if (response.success) {
      return target.supersededLegacyDocumentReferences;
    }

    return isPermanentPushRegistrationFailure(response)
      ? target.documentReferences
      : [];
  });

  await deleteRegistrationReferences(
    references,
    "Failed to remove obsolete push registrations."
  );
}

async function removeMalformedFIDRegistrations(
  references: PushRegistrationDocumentReference[]
): Promise<void> {
  if (references.length === 0) {
    return;
  }
  console.warn("Removing malformed Firebase Installation ID registrations.", {
    registrationCount: references.length,
  });
  await deleteRegistrationReferences(
    references,
    "Failed to remove malformed Firebase Installation ID registrations."
  );
}

async function deleteRegistrationReferences(
  references: PushRegistrationDocumentReference[],
  failureMessage: string
): Promise<void> {
  const cleanupResults = await Promise.allSettled(references.map((reference) => reference.delete()));
  const failedCleanupCount = cleanupResults.filter((result) => result.status === "rejected").length;
  if (failedCleanupCount > 0) {
    console.error(failureMessage, {
      failedCleanupCount,
    });
  }
}
