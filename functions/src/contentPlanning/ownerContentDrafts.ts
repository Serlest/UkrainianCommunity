import {createHash} from "node:crypto";

import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";
import {writeUserNotification} from "../notifications/notificationPayloads";

type DraftKind = "news" | "event";
type DraftState = "readyForReview" | "needsAttention";

interface SourceInput {
  url: string;
  title?: string;
  isPrimary: boolean;
  checkedAt?: string;
}

interface ParsedDraftInput {
  idempotencyKey: string;
  kind: DraftKind;
  state: DraftState;
  title: string;
  payload: Record<string, unknown>;
  sources: Array<Record<string, unknown>>;
  verificationNotes: string[];
  missingFields: string[];
}

const newsFields = new Set([
  "title", "summary", "body", "sourceInput", "tags", "federalState",
  "germanTitle", "germanSummary", "germanBody", "imageCaption",
  "imageAlternativeText", "imageCredit", "externalActionTitle", "externalActionURL",
]);

const eventFields = new Set([
  "title", "summary", "details", "city", "venue", "address", "locationNote",
  "latitude", "longitude", "eventOrganizerName", "organizerURL", "contactPhone",
  "contactEmail", "contactURL", "federalState", "startDate", "endDate", "isAllDay",
  "category", "audience", "minimumAge", "maximumAge", "tags", "capacity",
  "germanTitle", "germanSummary", "germanDetails", "additionalOccurrences",
  "participationMode", "externalActionTitle", "externalActionURL", "priceKind",
  "price", "maximumPrice", "priceNote",
]);

export function parseOwnerContentDraftInput(value: unknown): ParsedDraftInput {
  const input = record(value, "request");
  const idempotencyKey = requiredString(input.idempotencyKey, "idempotencyKey", 120);
  const kind = enumValue(input.kind, "kind", new Set<DraftKind>(["news", "event"]));
  const rawPayload = record(input.payload, "payload");
  const allowedFields = kind === "news" ? newsFields : eventFields;
  const payload: Record<string, unknown> = {};
  for (const [key, fieldValue] of Object.entries(rawPayload)) {
    if (!allowedFields.has(key)) {
      throw new HttpsError("invalid-argument", `Unsupported payload field: ${key}.`);
    }
    payload[key] = normalizedPayloadValue(key, fieldValue);
  }

  validatePayload(kind, payload);
  const missingFields = stringArray(input.missingFields, "missingFields", 30, 100);
  const verificationNotes = stringArray(input.verificationNotes, "verificationNotes", 30, 500);
  const requestedState = input.state === undefined
    ? undefined
    : enumValue(input.state, "state", new Set<DraftState>(["readyForReview", "needsAttention"]));
  const sources = sourceArray(input.sources);

  return {
    idempotencyKey,
    kind,
    state: requestedState ?? (missingFields.length > 0 ? "needsAttention" : "readyForReview"),
    title: requiredString(payload.title, "payload.title", 120),
    payload,
    sources,
    verificationNotes,
    missingFields,
  };
}

export async function saveOwnerContentDraftForUser(
  ownerUserId: string,
  parsed: ParsedDraftInput
): Promise<{draftId: string; created: boolean}> {
  const draftId = createHash("sha256")
    .update(`${ownerUserId}:${parsed.idempotencyKey}`)
    .digest("hex")
    .slice(0, 40);
  const reference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(draftId);
  let created = false;

  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) return;
    created = true;
    transaction.create(reference, {
      id: draftId,
      schemaVersion: 1,
      ownerUserId,
      kind: parsed.kind,
      state: parsed.state,
      title: parsed.title,
      payload: parsed.payload,
      sources: parsed.sources,
      verificationNotes: parsed.verificationNotes,
      missingFields: parsed.missingFields,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      scheduledAt: null,
      completedAt: null,
      failureMessage: null,
    });
  });

  if (created) {
    await writeUserNotification({
      notificationId: `contentDraftReady_${draftId}`,
      targetUserId: ownerUserId,
      type: "contentDraftReady",
      title: parsed.kind === "news" ? "Нова чернетка новини" : "Нова чернетка події",
      message: parsed.title,
      severity: parsed.state === "needsAttention" ? "warning" : "info",
      actionType: "openContentPlanning",
      actionTargetId: draftId,
      sourceType: "contentDraft",
      sourceId: draftId,
      dedupeKey: `contentDraftReady:${draftId}`,
      metadata: {kind: parsed.kind, state: parsed.state},
    });
  }

  return {draftId, created};
}

export const saveOwnerContentDraft = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    const parsed = parseOwnerContentDraftInput(request.data);
    return saveOwnerContentDraftForUser(actor.uid, parsed);
  }
);

function validatePayload(kind: DraftKind, payload: Record<string, unknown>): void {
  requiredString(payload.summary, "payload.summary", 200);
  stringArray(payload.tags, "payload.tags", 8, 30);
  optionalWebURL(payload.externalActionURL, "payload.externalActionURL");

  if (kind === "news") {
    requiredString(payload.body, "payload.body", 10_000);
    requiredString(payload.sourceInput, "payload.sourceInput", 2_048);
    return;
  }

  requiredString(payload.details, "payload.details", 2_000);
  requiredString(payload.city, "payload.city", 120);
  requiredString(payload.federalState, "payload.federalState", 80);
  if (!optionalString(payload.venue, 200) && !optionalString(payload.address, 300)) {
    throw new HttpsError("invalid-argument", "Event payload requires venue or address.");
  }
  const startDate = requiredDate(payload.startDate, "payload.startDate");
  const endDate = requiredDate(payload.endDate, "payload.endDate");
  if (endDate.getTime() <= startDate.getTime()) {
    throw new HttpsError("invalid-argument", "Event endDate must be later than startDate.");
  }
  payload.startDate = Timestamp.fromDate(startDate);
  payload.endDate = Timestamp.fromDate(endDate);
  optionalWebURL(payload.organizerURL, "payload.organizerURL");
  optionalWebURL(payload.contactURL, "payload.contactURL");
}

function normalizedPayloadValue(key: string, value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (key === "additionalOccurrences") {
    if (!Array.isArray(value) || value.length > 29) {
      throw new HttpsError("invalid-argument", "additionalOccurrences must contain at most 29 items.");
    }
    return value.map((item, index) => {
      const occurrence = record(item, `additionalOccurrences[${index}]`);
      const start = requiredDate(occurrence.startDate, `additionalOccurrences[${index}].startDate`);
      const end = requiredDate(occurrence.endDate, `additionalOccurrences[${index}].endDate`);
      if (end.getTime() <= start.getTime()) {
        throw new HttpsError("invalid-argument", "Occurrence endDate must be later than startDate.");
      }
      return {
        startDate: Timestamp.fromDate(start),
        endDate: Timestamp.fromDate(end),
        isAllDay: occurrence.isAllDay === true,
      };
    });
  }
  if (Array.isArray(value)) return value.map((item) => primitive(item));
  return primitive(value);
}

function sourceArray(value: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 10) {
    throw new HttpsError("invalid-argument", "sources must contain between 1 and 10 items.");
  }
  const sources = value.map((item, index) => {
    const source = record(item, `sources[${index}]`) as unknown as SourceInput;
    const url = requiredWebURL(source.url, `sources[${index}].url`);
    return {
      url,
      title: optionalString(source.title, 300) ?? null,
      isPrimary: source.isPrimary === true,
      checkedAt: source.checkedAt ? Timestamp.fromDate(requiredDate(source.checkedAt, `sources[${index}].checkedAt`)) : null,
    };
  });
  if (sources.filter((source) => source.isPrimary).length !== 1) {
    throw new HttpsError("invalid-argument", "Exactly one source must be primary.");
  }
  return sources;
}

function record(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${field} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  const resolved = optionalString(value, maxLength);
  if (!resolved) throw new HttpsError("invalid-argument", `${field} is required.`);
  return resolved;
}

function optionalString(value: unknown, maxLength: number): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value !== "string") throw new HttpsError("invalid-argument", "Expected a string.");
  const resolved = value.trim();
  if (resolved.length > maxLength) throw new HttpsError("invalid-argument", "String is too long.");
  return resolved.length > 0 ? resolved : undefined;
}

function stringArray(value: unknown, field: string, maxCount: number, maxLength: number): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > maxCount) {
    throw new HttpsError("invalid-argument", `${field} contains too many items.`);
  }
  return value.map((item) => requiredString(item, field, maxLength));
}

function enumValue<T extends string>(value: unknown, field: string, values: Set<T>): T {
  if (typeof value !== "string" || !values.has(value as T)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value as T;
}

function requiredDate(value: unknown, field: string): Date {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be ISO 8601.`);
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || !/[zZ]|[+-]\d{2}:\d{2}$/.test(value)) {
    throw new HttpsError("invalid-argument", `${field} must include an explicit time zone.`);
  }
  return date;
}

function requiredWebURL(value: unknown, field: string): string {
  const resolved = requiredString(value, field, 2_048);
  let url: URL;
  try { url = new URL(resolved); } catch { throw new HttpsError("invalid-argument", `${field} is not a valid URL.`); }
  if ((url.protocol !== "https:" && url.protocol !== "http:") || !url.hostname) {
    throw new HttpsError("invalid-argument", `${field} must be an HTTP(S) URL.`);
  }
  return url.toString();
}

function optionalWebURL(value: unknown, field: string): void {
  if (value === undefined || value === null || value === "") return;
  requiredWebURL(value, field);
}

function primitive(value: unknown): unknown {
  if (["string", "number", "boolean"].includes(typeof value)) return value;
  throw new HttpsError("invalid-argument", "Payload values must be primitive or supported arrays.");
}
