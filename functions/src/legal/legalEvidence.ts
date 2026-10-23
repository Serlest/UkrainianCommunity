import {FieldPath, Timestamp, type DocumentData, type DocumentSnapshot, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";
import {adminSearchDocuments} from "../users/adminUserSearch";

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
  source: "registration" | "profileSnapshot" | "legalDocument" | "analyticsConsent";
  contentHash: string | null;
  organizationId: string | null;
  organizationName: string | null;
  sourceRecordId: string | null;
  acceptedFromPlatform: string | null;
  consentId: string | null;
  purposeVersion: string | null;
  disclosureVersion: string | null;
  disclosureText: string | null;
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
  seconds?: number;
  nanoseconds?: number;
  searchQuery?: string;
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
  if (typeof value.cursor !== "object" || Array.isArray(value.cursor)) {
    throw new HttpsError("invalid-argument", "cursor is invalid.");
  }
  const cursorValue = value.cursor as Record<string, unknown>;
  const userId = requiredUserId(cursorValue.userId);
  const createdAt = typeof cursorValue.createdAt === "string" ? cursorValue.createdAt : "";
  if (!createdAt || Number.isNaN(Date.parse(createdAt))) {
    throw new HttpsError("invalid-argument", "cursor.createdAt is invalid.");
  }
  if (rawQuery) {
    if (cursorValue.searchQuery !== normalizedSearch(rawQuery)) {
      throw new HttpsError("invalid-argument", "The search cursor belongs to another query.");
    }
    return {query: rawQuery, limit, cursor: {userId, createdAt, searchQuery: cursorValue.searchQuery as string}};
  }
  if (cursorValue.searchQuery !== undefined) throw new HttpsError("invalid-argument", "Search cursor requires its query.");
  const {seconds, nanoseconds} = cursorValue;
  if (seconds !== undefined || nanoseconds !== undefined) {
    if (!Number.isSafeInteger(seconds) || !Number.isInteger(nanoseconds)
      || (nanoseconds as number) < 0 || (nanoseconds as number) >= 1_000_000_000) {
      throw new HttpsError("invalid-argument", "Invalid precise cursor.");
    }
    try { new Timestamp(seconds as number, nanoseconds as number); }
    catch { throw new HttpsError("invalid-argument", "Invalid precise cursor."); }
    return {query: null, limit, cursor: {userId, createdAt, seconds: seconds as number, nanoseconds: nanoseconds as number}};
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
      const matches: QueryDocumentSnapshot[] = [];
      for await (const document of adminSearchDocuments(db, normalizedQuery,
        ["displayName", "fullName", "email", "createdAt"], "automatic", undefined, input.cursor?.userId)) {
        if (!accountMatchesSearch(document.id, document.data(), normalizedQuery)) continue;
        matches.push(document);
        if (matches.length > input.limit) break;
      }
      const page = matches.slice(0, input.limit), last = page.at(-1);
      return {
        accounts: page.map(accountFromDocument),
        nextCursor: matches.length > input.limit && last ? {
          userId: last.id, createdAt: timestampISO(last.get("createdAt")) ?? new Date(0).toISOString(), searchQuery: normalizedQuery,
        } : null,
        totalMatches: null,
      };
    }

    let query = db.collection("users")
      .orderBy("createdAt", "desc")
      .orderBy(FieldPath.documentId(), "desc")
      .limit(input.limit + 1);
    if (input.cursor) {
      let timestamp: Timestamp;
      if (input.cursor.seconds !== undefined && input.cursor.nanoseconds !== undefined) {
        timestamp = new Timestamp(input.cursor.seconds, input.cursor.nanoseconds);
      } else {
        // Recover the exact timestamp for old clients, which only echo ISO ms.
        const anchor = await db.collection("users").doc(input.cursor.userId).get();
        const original = anchor.get("createdAt");
        if (!(original instanceof Timestamp)) {
          throw new HttpsError("failed-precondition", "The account list changed. Reload the first page.");
        }
        timestamp = original;
      }
      query = query.startAfter(timestamp, input.cursor.userId);
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
        seconds: (last.get("createdAt") as Timestamp).seconds,
        nanoseconds: (last.get("createdAt") as Timestamp).nanoseconds,
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
    const events = [
      ...(user.exists ? await profileFallbackEvents(user) : []),
      ...legalLogs.docs.flatMap(legalAcceptanceEvents),
      ...analyticsReceipts.docs.flatMap(analyticsConsentEvents),
    ]
      .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
    const identity = user.data() ?? {};
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

interface EvidencePageCursor { userId: string; source: number; after: string | null }

export const getLegalEvidencePage = onCall(callableOptions, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  assertOwner(auth.permissions);
  const userId = parseLegalEvidenceUserRequest(request.data);
  if (request.data?.format === 2) return evidencePageV2(userId, request.data);
  const value = request.data as Record<string, unknown>;
  const limit = value.limit === undefined ? 200 : value.limit;
  if (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 200) {
    throw new HttpsError("invalid-argument", "Invalid page limit.");
  }
  let cursor: EvidencePageCursor = {userId, source: 0, after: null};
  if (value.cursor !== undefined && value.cursor !== null) {
    try {
      if (typeof value.cursor !== "string" || value.cursor.length > 2048) throw new Error();
      const decoded = JSON.parse(Buffer.from(value.cursor, "base64url").toString("utf8"));
      if (decoded.userId !== userId || ![1, 2].includes(decoded.source)
        || !(decoded.after === null || (typeof decoded.after === "string" && decoded.after.length > 0
          && decoded.after.length <= 512 && !decoded.after.includes("/")))) throw new Error();
      cursor = decoded;
    } catch { throw new HttpsError("invalid-argument", "Invalid evidence cursor."); }
  }
  const user = await db.collection("users").doc(userId).get();
  let events: LegalEvidenceEvent[] = [];
  let next: EvidencePageCursor | null = null;
  if (cursor.source === 0) {
    events = user.exists ? await profileFallbackEvents(user) : [];
    next = {userId, source: 1, after: null};
  } else {
    const collection = cursor.source === 1 ? "legalAcceptanceLogs" : "analyticsConsentReceipts";
    let query = db.collection(collection).where("userId", "==", userId)
      .orderBy(FieldPath.documentId()).limit((limit as number) + 1);
    if (cursor.after) query = query.startAfter(cursor.after);
    const snapshot = await query.get();
    const page = snapshot.docs.slice(0, limit as number);
    events = page.flatMap(cursor.source === 1 ? legalAcceptanceEvents : analyticsConsentEvents);
    if (snapshot.size > (limit as number)) next = {userId, source: cursor.source, after: page.at(-1)!.id};
    else if (cursor.source === 1) next = {userId, source: 2, after: null};
  }
  const identity = user.data() ?? {};
  return {
    account: {userId, displayName: nullableString(identity.displayName) ?? nullableString(identity.fullName),
      email: nullableString(identity.email), createdAt: timestampISO(identity.createdAt)},
    events,
    nextCursor: next ? Buffer.from(JSON.stringify(next)).toString("base64url") : null,
    generatedAt: new Date().toISOString(),
  };
});

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
      ...(await Promise.all(users.docs.map(profileFallbackEvents))).flat(),
      ...legalLogs.docs.flatMap(legalAcceptanceEvents),
      ...analyticsReceipts.docs.flatMap(analyticsConsentEvents),
    ];
    return {
      events: events
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
    displayName: null,
    email: null,
    locale: null,
    appVersion: null,
    source: "registration" as const,
    contentHash: null,
    organizationId: null,
    organizationName: null,
    sourceRecordId: document.id,
    acceptedFromPlatform: null,
    consentId: null,
    purposeVersion: null,
    disclosureVersion: null,
    disclosureText: null,
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
      sourceRecordId: document.id,
      acceptedFromPlatform: nullableString(data.acceptedFromPlatform),
      consentId: null,
      purposeVersion: null,
      disclosureVersion: null,
      disclosureText: null,
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
    sourceRecordId: document.id,
    acceptedFromPlatform: null,
    consentId: nullableString(data.consentID),
    purposeVersion: nullableString(data.purposeVersion),
    disclosureVersion: nullableString(data.disclosureVersion),
    disclosureText: nullableString(data.disclosureText),
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
  return occurredAt ? {id, eventType, occurredAt, version, ...base,
    ...(base.source === "registration" && eventType !== "minimumAgeConfirmed" ? {source: "profileSnapshot" as const} : {}),
  } : null;
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

export function accountMatchesSearch(userId: string, data: DocumentData, query: string): boolean {
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



/** Profile fields are mutable summaries, never a second acceptance receipt. */
async function profileFallbackEvents(user: DocumentSnapshot): Promise<LegalEvidenceEvent[]> {
  const candidates = registrationEvents(user);
  const result = await Promise.all(candidates.map(async event => {
    if (event.eventType === "minimumAgeConfirmed") return event;
    const type = event.eventType === "termsAccepted" ? "terms" : "privacy";
    const match = await db.collection("legalAcceptanceLogs").where("userId", "==", user.id)
      .where("documentType", "==", type).where("version", "==", event.version)
      .where("acceptedAt", "==", user.get(type === "terms" ? "acceptedTermsAt" : "acceptedPrivacyAt")).limit(1).get();
    return match.empty ? event : null;
  }));
  return result.filter((event): event is LegalEvidenceEvent => event !== null);
}

type StreamName = "legal" | "grants" | "withdrawals";
interface EvidencePosition {seconds: number; nanoseconds: number; id: string; isNull?: boolean}
interface HistoryCursorV2 {
  v: 2; userId: string; filter: string; query: string;
  positions: Partial<Record<StreamName, EvidencePosition>>;
  finished: StreamName[]; profileConsumed: string[];
}
interface EvidenceCandidate {event: LegalEvidenceEvent; stream?: StreamName; position: EvidencePosition}
const evidenceStreams: StreamName[] = ["legal", "grants", "withdrawals"];
const evidenceFilters = ["all", "terms", "privacy", "age", "analytics", "organizations"];
const typeByFilter: Record<string, LegalEvidenceEventType[]> = {
  terms: ["termsAccepted"], privacy: ["privacyAcknowledged"], age: ["minimumAgeConfirmed"],
  analytics: ["analyticsGranted", "analyticsWithdrawn"], organizations: ["organizationRulesAccepted"],
};
const searchableTitles: Record<LegalEvidenceEventType, string> = {
  termsAccepted: "умови прийнято Nutzungsbedingungen akzeptiert",
  privacyAcknowledged: "конфіденційність підтверджено Datenschutz Kenntnisnahme",
  minimumAgeConfirmed: "вік 14 Mindestalter bestätigt",
  organizationRulesAccepted: "правила організації Organisationsregeln akzeptiert",
  analyticsGranted: "згоду на аналітику надано Analyse Einwilligung erteilt",
  analyticsWithdrawn: "згоду на аналітику відкликано Analyse Einwilligung widerrufen",
};

async function evidencePageV2(userId: string, data: Record<string, unknown>) {
  const limit = data.limit === undefined ? 50 : data.limit;
  if (!Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 100) throw new HttpsError("invalid-argument", "Invalid page limit.");
  const filter = data.filter === undefined ? "all" : data.filter;
  if (typeof filter !== "string" || !evidenceFilters.includes(filter)) throw new HttpsError("invalid-argument", "Invalid filter.");
  if (data.query !== undefined && (typeof data.query !== "string" || data.query.length > 120)) throw new HttpsError("invalid-argument", "Invalid query.");
  const query = normalizedSearch(typeof data.query === "string" ? data.query : "");
  let cursor: HistoryCursorV2 = {v: 2, userId, filter, query, positions: {}, finished: [], profileConsumed: []};
  if (data.cursor !== undefined && data.cursor !== null) {
    try {
      if (typeof data.cursor !== "string" || data.cursor.length > 4096) throw new Error();
      const decoded = JSON.parse(Buffer.from(data.cursor, "base64url").toString("utf8"));
      if (decoded.v !== 2 || decoded.userId !== userId || decoded.filter !== filter || decoded.query !== query
        || !decoded.positions || typeof decoded.positions !== "object" || Array.isArray(decoded.positions)
        || Object.keys(decoded.positions).some(key => !evidenceStreams.includes(key as StreamName))
        || !Array.isArray(decoded.finished) || decoded.finished.some((key: StreamName) => !evidenceStreams.includes(key))
        || !Array.isArray(decoded.profileConsumed) || decoded.profileConsumed.length > 3
        || decoded.profileConsumed.some((id: unknown) => typeof id !== "string" || !id.startsWith(`registration:${userId}:`))) throw new Error();
      for (const value of Object.values(decoded.positions) as EvidencePosition[]) {
        if (!Number.isSafeInteger(value.seconds) || !Number.isInteger(value.nanoseconds) || value.nanoseconds < 0 || value.nanoseconds >= 1e9
          || (value.isNull !== undefined && typeof value.isNull !== "boolean")
          || typeof value.id !== "string" || !value.id || value.id.includes("/") || value.id.length > 512) throw new Error();
        new Timestamp(value.seconds, value.nanoseconds);
      }
      cursor = decoded;
    } catch {throw new HttpsError("invalid-argument", "Invalid history cursor.");}
  }
  const user = await db.doc(`users/${userId}`).get();
  const candidates: EvidenceCandidate[] = [];
  const exhausted = new Set<StreamName>(cursor.finished);
  await Promise.all(evidenceStreams.map(async stream => {
    if (exhausted.has(stream)) return;
    if ((filter === "analytics" && stream === "legal")
      || (filter !== "all" && filter !== "analytics" && stream !== "legal") || filter === "age") {
      exhausted.add(stream); return;
    }
    const field = stream === "legal" ? "acceptedAt" : stream === "grants" ? "grantedAt" : "withdrawnAt";
    let source = db.collection(stream === "legal" ? "legalAcceptanceLogs" : "analyticsConsentReceipts")
      .where("userId", "==", userId).orderBy(field, "desc").orderBy(FieldPath.documentId(), "desc");
    if (stream === "legal" && ["terms", "privacy", "organizations"].includes(filter)) {
      source = source.where("documentType", "==", filter === "organizations" ? "organizationRules" : filter);
    }
    const pos = cursor.positions[stream];
    if (pos) source = source.startAfter(pos.isNull ? null : new Timestamp(pos.seconds, pos.nanoseconds), pos.id);
    const snapshot = await source.limit((limit as number) + 1).get();
    if (snapshot.size <= (limit as number)) exhausted.add(stream);
    snapshot.docs.forEach(doc => {
      const timestamp = doc.get(field);
      // A null grant/withdrawal has no event but must still advance its stream.
      const timestampValue = timestamp instanceof Timestamp ? timestamp : new Timestamp(0, 0);
      const events = stream === "legal" ? legalAcceptanceEvents(doc) : analyticsConsentEvents(doc)
        .filter(event => event.eventType === (stream === "grants" ? "analyticsGranted" : "analyticsWithdrawn"));
      candidates.push({stream, position: {seconds: timestampValue.seconds, nanoseconds: timestampValue.nanoseconds, id: doc.id, ...(timestamp === null ? {isNull: true} : {})},
        event: events[0] ?? {id: `empty:${stream}:${doc.id}`, occurredAt: new Date(0).toISOString()} as LegalEvidenceEvent});
    });
  }));
  // Profile fallbacks are tiny and sorted together with receipts, never relabeled as registration.
  if (user.exists) for (const event of await profileFallbackEvents(user)) {
    if (cursor.profileConsumed.includes(event.id)) continue;
    const timestamp = Timestamp.fromDate(new Date(event.occurredAt));
    candidates.push({event, position: {seconds: timestamp.seconds, nanoseconds: timestamp.nanoseconds, id: event.id}});
  }
  candidates.sort((a, b) => Number(a.position.isNull === true) - Number(b.position.isNull === true)
    || b.position.seconds - a.position.seconds || b.position.nanoseconds - a.position.nanoseconds
    || (a.stream ?? "profile").localeCompare(b.stream ?? "profile")
    || Buffer.compare(Buffer.from(b.position.id), Buffer.from(a.position.id)));
  const consumed = candidates.slice(0, limit as number);
  for (const candidate of consumed) {
    if (candidate.stream) cursor.positions[candidate.stream] = candidate.position;
    else cursor.profileConsumed.push(candidate.event.id);
  }
  cursor.finished = [...exhausted].filter(stream => !candidates.slice(limit as number).some(candidate => candidate.stream === stream));
  const nextCursor = cursor.finished.length === evidenceStreams.length && candidates.length <= (limit as number) ? null
    : Buffer.from(JSON.stringify(cursor)).toString("base64url");
  const identity = user.data() ?? {};
  const account = {userId, displayName: nullableString(identity.displayName) ?? nullableString(identity.fullName),
    email: nullableString(identity.email), createdAt: timestampISO(identity.createdAt)};
  const events = consumed.map(candidate => candidate.event).filter(event => {
    if (!event.eventType || (filter !== "all" && !typeByFilter[filter].includes(event.eventType))) return false;
    const haystack = normalizedSearch([...Object.values(event), account.displayName, account.email, searchableTitles[event.eventType]]
      .filter(value => typeof value === "string").join(" "));
    return !query || query.split(/\s+/).every(token => haystack.includes(token));
  });
  const summary = data.cursor ? undefined : await evidenceSummary(userId, identity);
  return {account, events, nextCursor, summary, generatedAt: new Date().toISOString()};
}

async function evidenceSummary(userId: string, identity: DocumentData) {
  const [terms, privacy, analytics] = await db.getAll(db.doc("legalDocuments/terms"), db.doc("legalDocuments/privacy"), db.doc(`analyticsConsentStates/${userId}`));
  const status = (kind: string, version: unknown, date: unknown, current: unknown) => ({kind,
    version: nullableString(version), confirmedAt: timestampISO(date), currentVersion: nullableString(current),
    state: !timestampISO(date) || !nullableString(current) ? "unknown" : version === current ? "current" : "outdated"});
  return [status("terms", identity.acceptedTermsVersion ?? identity.termsVersion, identity.acceptedTermsAt, terms.get("activeVersion")),
    status("privacy", identity.acceptedPrivacyVersion ?? identity.privacyVersion, identity.acceptedPrivacyAt, privacy.get("activeVersion")),
    {kind: "age", version: nullableString(identity.minimumAgeVersion), confirmedAt: timestampISO(identity.minimumAgeConfirmedAt), currentVersion: null,
      state: timestampISO(identity.minimumAgeConfirmedAt) ? "confirmed" : "unknown"},
    {kind: "analytics", version: nullableString(analytics.get("privacyVersion")), currentVersion: null,
      confirmedAt: timestampISO(analytics.get("withdrawnAt")) ?? timestampISO(analytics.get("grantedAt")),
      state: analytics.get("enabled") === true ? "granted" : analytics.get("enabled") === false ? "withdrawn" : "unknown"}];
}
