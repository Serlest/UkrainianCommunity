import {FieldPath, Timestamp, type DocumentData, type DocumentSnapshot, type QueryDocumentSnapshot} from "firebase-admin/firestore";
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

interface LegalEvidenceAccount {
  userId: string;
  displayName: string | null;
  email: string | null;
  createdAt: string | null;
}

interface LegalEvidenceAccountCursor {
  userId: string;
  createdAt: string;
}

interface ListLegalEvidenceAccountsResponse {
  accounts: LegalEvidenceAccount[];
  nextCursor: LegalEvidenceAccountCursor | null;
  totalMatches: number | null;
}

interface GetLegalEvidenceForUserResponse {
  account: LegalEvidenceAccount;
  events: LegalEvidenceEvent[];
  generatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  enforceAppCheck: false,
};
const defaultLimit = 100;
const maximumLimit = 200;
const defaultAccountLimit = 50;
const maximumAccountLimit = 100;
const maximumUserEvidenceEvents = 500;

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

export function parseLegalEvidenceAccountRequest(data: unknown): {
  query: string | null;
  limit: number;
  cursor: LegalEvidenceAccountCursor | null;
} {
  if (data !== undefined && data !== null && (typeof data !== "object" || Array.isArray(data))) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  const value = (data ?? {}) as Record<string, unknown>;
  const rawQuery = typeof value.query === "string" ? value.query.trim() : "";
  if (rawQuery.length === 1 || rawQuery.length > 120) {
    throw new HttpsError("invalid-argument", "query must be empty or contain 2 to 120 characters.");
  }
  const limit = value.limit === undefined ? defaultAccountLimit : Number(value.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > maximumAccountLimit) {
    throw new HttpsError("invalid-argument", "limit must be an integer from 1 to 100.");
  }
  if (value.cursor === undefined || value.cursor === null) {
    return {query: rawQuery || null, limit, cursor: null};
  }
  if (rawQuery) {
    throw new HttpsError("invalid-argument", "cursor is not supported during search.");
  }
  if (typeof value.cursor !== "object" || Array.isArray(value.cursor)) {
    throw new HttpsError("invalid-argument", "cursor is invalid.");
  }
  const cursorValue = value.cursor as Record<string, unknown>;
  const userId = requiredUserId(cursorValue.userId);
  const createdAt = typeof cursorValue.createdAt === "string" ? cursorValue.createdAt : "";
  if (!createdAt || Number.isNaN(Date.parse(createdAt))) {
    throw new HttpsError("invalid-argument", "cursor.createdAt is invalid.");
  }
  return {query: null, limit, cursor: {userId, createdAt}};
}

export function parseLegalEvidenceUserRequest(data: unknown): string {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  return requiredUserId((data as Record<string, unknown>).userId);
}

export const listLegalEvidenceAccounts = onCall(
  callableOptions,
  async (request): Promise<ListLegalEvidenceAccountsResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertOwner(auth.permissions);
    const input = parseLegalEvidenceAccountRequest(request.data);

    if (input.query) {
      const normalizedQuery = normalizedSearch(input.query);
      const snapshot = await db.collection("users")
        .select("displayName", "fullName", "email", "createdAt")
        .get();
      const matches = snapshot.docs
        .filter((document) => accountMatchesSearch(document.id, document.data(), normalizedQuery))
        .sort((left, right) => timestampMillis(right.data().createdAt) - timestampMillis(left.data().createdAt));
      return {
        accounts: matches.slice(0, input.limit).map(accountFromDocument),
        nextCursor: null,
        totalMatches: matches.length,
      };
    }

    let query = db.collection("users")
      .orderBy("createdAt", "desc")
      .orderBy(FieldPath.documentId(), "desc")
      .limit(input.limit + 1);
    if (input.cursor) {
      query = query.startAfter(Timestamp.fromDate(new Date(input.cursor.createdAt)), input.cursor.userId);
    }
    const snapshot = await query.get();
    const page = snapshot.docs.slice(0, input.limit);
    const last = page.at(-1);
    const lastCreatedAt = last ? timestampISO(last.data().createdAt) : null;
    return {
      accounts: page.map(accountFromDocument),
      nextCursor: snapshot.size > input.limit && last && lastCreatedAt ? {
        userId: last.id,
        createdAt: lastCreatedAt,
      } : null,
      totalMatches: null,
    };
  }
);

export const getLegalEvidenceForUser = onCall(
  callableOptions,
  async (request): Promise<GetLegalEvidenceForUserResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertOwner(auth.permissions);
    const userId = parseLegalEvidenceUserRequest(request.data);
    const [user, legalLogs, analyticsReceipts] = await Promise.all([
      db.collection("users").doc(userId).get(),
      db.collection("legalAcceptanceLogs").where("userId", "==", userId).limit(maximumUserEvidenceEvents).get(),
      db.collection("analyticsConsentReceipts").where("userId", "==", userId).limit(maximumUserEvidenceEvents).get(),
    ]);
    if (!user.exists && legalLogs.empty && analyticsReceipts.empty) {
      throw new HttpsError("not-found", "The account and its legal evidence were not found.");
    }
    const identity = user.data() ?? {};
    const events = [
      ...(user.exists ? registrationEvents(user) : []),
      ...legalLogs.docs.flatMap(legalAcceptanceEvents),
      ...analyticsReceipts.docs.flatMap(analyticsConsentEvents),
    ]
      .map((event) => ({
        ...event,
        displayName: nullableString(identity.displayName) ?? nullableString(identity.fullName),
        email: nullableString(identity.email),
      }))
      .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
    return {
      account: {
        userId,
        displayName: nullableString(identity.displayName) ?? nullableString(identity.fullName),
        email: nullableString(identity.email),
        createdAt: timestampISO(identity.createdAt),
      },
      events,
      generatedAt: new Date().toISOString(),
    };
  }
);

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

function registrationEvents(document: DocumentSnapshot): LegalEvidenceEvent[] {
  const data = document.data() ?? {};
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

function requiredUserId(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "userId is required.");
  }
  const normalized = value.trim();
  if (!normalized || normalized.length > 200 || normalized.includes("/")) {
    throw new HttpsError("invalid-argument", "userId is invalid.");
  }
  return normalized;
}

function normalizedSearch(value: string): string {
  return value
    .toLocaleLowerCase("uk-UA")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function accountMatchesSearch(userId: string, data: DocumentData, query: string): boolean {
  const haystack = [userId, data.displayName, data.fullName, data.email]
    .filter((value): value is string => typeof value === "string")
    .join(" ");
  const normalizedHaystack = normalizedSearch(haystack);
  return query.split(/\s+/).every((token) => normalizedHaystack.includes(token));
}

function accountFromDocument(document: QueryDocumentSnapshot): LegalEvidenceAccount {
  const data = document.data();
  return {
    userId: document.id,
    displayName: nullableString(data.displayName) ?? nullableString(data.fullName),
    email: nullableString(data.email),
    createdAt: timestampISO(data.createdAt),
  };
}

function timestampMillis(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : 0;
}
