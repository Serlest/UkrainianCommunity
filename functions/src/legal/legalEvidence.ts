import {Timestamp, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";

type LegalEvidenceEventType =
  | "termsAccepted"
  | "privacyAcknowledged"
  | "minimumAgeConfirmed"
  | "organizationRulesAccepted"
  | "analyticsGranted"
  | "analyticsWithdrawn";

interface LegalEvidenceEvent {
  id: string;
  userId: string;
  displayName: string | null;
  email: string | null;
  eventType: LegalEvidenceEventType;
  occurredAt: string;
  version: string | null;
  locale: string | null;
  appVersion: string | null;
  source: "registration" | "legalDocument" | "analyticsConsent";
  contentHash: string | null;
  organizationId: string | null;
  organizationName: string | null;
}

interface ListLegalEvidenceResponse {
  events: LegalEvidenceEvent[];
  generatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};
const defaultLimit = 100;
const maximumLimit = 200;

export function parseLegalEvidenceLimit(data: unknown): number {
  if (data === undefined || data === null) return defaultLimit;
  if (typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  const value = (data as Record<string, unknown>).limit;
  if (value === undefined) return defaultLimit;
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > maximumLimit) {
    throw new HttpsError("invalid-argument", "limit must be an integer from 1 to 200.");
  }
  return value as number;
}

export const listLegalEvidence = onCall(
  callableOptions,
  async (request): Promise<ListLegalEvidenceResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertOwner(auth.permissions);
    const limit = parseLegalEvidenceLimit(request.data);

    const [users, legalLogs, analyticsReceipts] = await Promise.all([
      db.collection("users").orderBy("createdAt", "desc").limit(limit).get(),
      db.collection("legalAcceptanceLogs").orderBy("acceptedAt", "desc").limit(limit).get(),
      db.collection("analyticsConsentReceipts").orderBy("grantedAt", "desc").limit(limit).get(),
    ]);

    const events = [
      ...users.docs.flatMap(registrationEvents),
      ...legalLogs.docs.flatMap(legalAcceptanceEvents),
      ...analyticsReceipts.docs.flatMap(analyticsConsentEvents),
    ];
    const userIds = [...new Set(events.map((event) => event.userId))];
    const userSnapshots = userIds.length === 0 ?
      [] :
      await db.getAll(...userIds.map((userId) => db.collection("users").doc(userId)));
    const identities = new Map(
      userSnapshots.map((snapshot) => {
        const data = snapshot.data() ?? {};
        return [snapshot.id, {
          displayName: nullableString(data.displayName) ?? nullableString(data.fullName),
          email: nullableString(data.email),
        }] as const;
      })
    );

    return {
      events: events
        .map((event) => ({...event, ...(identities.get(event.userId) ?? {})}))
        .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt))
        .slice(0, limit),
      generatedAt: new Date().toISOString(),
    };
  }
);

function registrationEvents(document: QueryDocumentSnapshot): LegalEvidenceEvent[] {
  const data = document.data();
  const base = {
    userId: document.id,
    displayName: nullableString(data.displayName) ?? nullableString(data.fullName),
    email: nullableString(data.email),
    locale: null,
    appVersion: null,
    source: "registration" as const,
    contentHash: null,
    organizationId: null,
    organizationName: null,
  };
  return [
    eventFromTimestamp(
      `registration:${document.id}:terms`,
      "termsAccepted",
      data.acceptedTermsAt,
      nullableString(data.acceptedTermsVersion) ?? nullableString(data.termsVersion),
      base
    ),
    eventFromTimestamp(
      `registration:${document.id}:privacy`,
      "privacyAcknowledged",
      data.acceptedPrivacyAt,
      nullableString(data.acceptedPrivacyVersion) ?? nullableString(data.privacyVersion),
      base
    ),
    eventFromTimestamp(
      `registration:${document.id}:minimum-age`,
      "minimumAgeConfirmed",
      data.minimumAgeConfirmedAt,
      nullableString(data.minimumAgeVersion),
      base
    ),
  ].filter((event): event is LegalEvidenceEvent => event !== null);
}

function legalAcceptanceEvents(document: QueryDocumentSnapshot): LegalEvidenceEvent[] {
  const data = document.data();
  const documentType = nullableString(data.documentType);
  if (
    documentType !== "terms" &&
    documentType !== "privacy" &&
    documentType !== "organizationRules"
  ) return [];
  const event = eventFromTimestamp(
    `legal:${document.id}`,
    documentType === "terms" ?
      "termsAccepted" :
      documentType === "privacy" ? "privacyAcknowledged" : "organizationRulesAccepted",
    data.acceptedAt,
    nullableString(data.version),
    {
      userId: nullableString(data.userId) ?? "",
      displayName: null,
      email: null,
      locale: nullableString(data.locale),
      appVersion: nullableString(data.appVersion),
      source: "legalDocument",
      contentHash: nullableString(data.contentHash),
      organizationId: nullableString(data.organizationId),
      organizationName: nullableString(data.organizationName),
    }
  );
  return event?.userId ? [event] : [];
}

function analyticsConsentEvents(document: QueryDocumentSnapshot): LegalEvidenceEvent[] {
  const data = document.data();
  const userId = nullableString(data.userId);
  if (!userId) return [];
  const base = {
    userId,
    displayName: null,
    email: null,
    locale: nullableString(data.disclosureLocale),
    appVersion: nullableString(data.appVersion),
    source: "analyticsConsent" as const,
    contentHash: null,
    organizationId: null,
    organizationName: null,
  };
  return [
    eventFromTimestamp(
      `analytics:${document.id}:grant`,
      "analyticsGranted",
      data.grantedAt,
      nullableString(data.privacyVersion),
      base
    ),
    eventFromTimestamp(
      `analytics:${document.id}:withdrawal`,
      "analyticsWithdrawn",
      data.withdrawnAt,
      nullableString(data.privacyVersion),
      base
    ),
  ].filter((event): event is LegalEvidenceEvent => event !== null);
}

function eventFromTimestamp(
  id: string,
  eventType: LegalEvidenceEventType,
  timestamp: unknown,
  version: string | null,
  base: Omit<LegalEvidenceEvent, "id" | "eventType" | "occurredAt" | "version">
): LegalEvidenceEvent | null {
  const occurredAt = timestampISO(timestamp);
  return occurredAt ? {id, eventType, occurredAt, version, ...base} : null;
}

function timestampISO(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function nullableString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}
