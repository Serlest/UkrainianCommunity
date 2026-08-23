import { Timestamp, type DocumentData } from "firebase-admin/firestore";
import { HttpsError, onCall, type CallableRequest } from "firebase-functions/v2/https";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import { assertOwner, getUserPermissions } from "../permissions/userPermissions";

type FeaturedBannerSaveMode = "create" | "update";
type FeaturedBannerActionType = "none" | "news" | "event" | "organization" | "externalURL";
type FeaturedBannerRegionScope = "allAustria" | "federalState";
type FeaturedBannerVisibleSection = "home" | "events" | "organizations";

interface FeaturedBannerDraft {
  id: string;
  internalName?: string;
  title?: string;
  subtitle?: string;
  imageURL: string;
  actionType: FeaturedBannerActionType;
  actionTargetID?: string;
  externalURL?: string;
  regionScope: FeaturedBannerRegionScope;
  federalState?: string;
  visibleSections: FeaturedBannerVisibleSection[];
  displayDurationSeconds: number;
  priority: number;
  isActive: boolean;
  startsAt?: Timestamp;
  endsAt?: Timestamp;
}

interface FeaturedBannerSaveRequest {
  mode: FeaturedBannerSaveMode;
  banner: FeaturedBannerDraft;
}

interface FeaturedBannerIDRequest {
  id: string;
}

interface FeaturedBannerActiveRequest extends FeaturedBannerIDRequest {
  isActive: boolean;
}

interface FeaturedBannerMutationResponse {
  id: string;
  updatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const actionTypes = new Set<FeaturedBannerActionType>([
  "none",
  "news",
  "event",
  "organization",
  "externalURL",
]);
const targetActionTypes = new Set<FeaturedBannerActionType>([
  "news",
  "event",
  "organization",
]);
const regionScopes = new Set<FeaturedBannerRegionScope>([
  "allAustria",
  "federalState",
]);
const federalStates = new Set([
  "burgenland",
  "kaernten",
  "niederoesterreich",
  "oberoesterreich",
  "salzburg",
  "steiermark",
  "tirol",
  "vorarlberg",
  "wien",
]);
const visibleSections = new Set<FeaturedBannerVisibleSection>([
  "home",
  "events",
  "organizations",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const normalized = value.trim();
  if (normalized.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }
  if (normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return normalized;
}

function optionalString(value: unknown, field: string, maxLength: number): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new HttpsError("invalid-argument", `${field} is too long.`);
  }
  return normalized.length > 0 ? normalized : undefined;
}

function safeDocumentID(value: unknown): string {
  const id = requiredString(value, "id", 128);
  if (id.includes("/")) {
    throw new HttpsError("invalid-argument", "id contains unsupported characters.");
  }
  return id;
}

function webURL(value: unknown, field: string): string {
  const normalized = requiredString(value, field, 2_048);
  try {
    const url = new URL(normalized);
    if (url.protocol !== "https:" && url.protocol !== "http:") {
      throw new Error("unsupported protocol");
    }
    return url.toString();
  } catch {
    throw new HttpsError("invalid-argument", `${field} must be a valid HTTP URL.`);
  }
}

function integerInRange(value: unknown, field: string, minimum: number, maximum: number): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < minimum || value > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be an integer from ${minimum} through ${maximum}.`
    );
  }
  return value;
}

function optionalTimestamp(value: unknown, field: string): Timestamp | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be an ISO-8601 string.`);
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new HttpsError("invalid-argument", `${field} must be a valid date.`);
  }
  return Timestamp.fromDate(date);
}

function enumValue<T extends string>(value: unknown, field: string, allowed: Set<T>): T {
  if (typeof value !== "string" || !allowed.has(value as T)) {
    throw new HttpsError("invalid-argument", `${field} is not supported.`);
  }
  return value as T;
}

function parseVisibleSections(value: unknown): FeaturedBannerVisibleSection[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError("invalid-argument", "visibleSections must not be empty.");
  }

  const parsed = value.map((section) =>
    enumValue(section, "visibleSections", visibleSections)
  );
  return Array.from(new Set(parsed)).sort();
}

export function parseFeaturedBannerDraft(value: unknown): FeaturedBannerDraft {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "banner must be an object.");
  }

  const actionType = enumValue(value.actionType, "actionType", actionTypes);
  const regionScope = enumValue(value.regionScope, "regionScope", regionScopes);
  const actionTargetID = optionalString(value.actionTargetID, "actionTargetID", 256);
  const externalURL = value.externalURL === undefined || value.externalURL === null
    ? undefined
    : webURL(value.externalURL, "externalURL");
  const federalState = optionalString(value.federalState, "federalState", 64);
  const startsAt = optionalTimestamp(value.startsAt, "startsAt");
  const endsAt = optionalTimestamp(value.endsAt, "endsAt");

  if (targetActionTypes.has(actionType) && !actionTargetID) {
    throw new HttpsError("invalid-argument", "actionTargetID is required for this actionType.");
  }
  if (actionType === "externalURL" && !externalURL) {
    throw new HttpsError("invalid-argument", "externalURL is required for externalURL actions.");
  }
  if (regionScope === "federalState" && (!federalState || !federalStates.has(federalState))) {
    throw new HttpsError("invalid-argument", "federalState is required for regional banners.");
  }
  if (startsAt && endsAt && startsAt.toMillis() >= endsAt.toMillis()) {
    throw new HttpsError("invalid-argument", "startsAt must be earlier than endsAt.");
  }
  if (typeof value.isActive !== "boolean") {
    throw new HttpsError("invalid-argument", "isActive must be a boolean.");
  }

  return {
    id: safeDocumentID(value.id),
    internalName: optionalString(value.internalName, "internalName", 120),
    title: optionalString(value.title, "title", 120),
    subtitle: optionalString(value.subtitle, "subtitle", 240),
    imageURL: webURL(value.imageURL, "imageURL"),
    actionType,
    actionTargetID: targetActionTypes.has(actionType) ? actionTargetID : undefined,
    externalURL: actionType === "externalURL" ? externalURL : undefined,
    regionScope,
    federalState: regionScope === "federalState" ? federalState : undefined,
    visibleSections: parseVisibleSections(value.visibleSections),
    displayDurationSeconds: integerInRange(value.displayDurationSeconds, "displayDurationSeconds", 3, 12),
    priority: integerInRange(value.priority, "priority", 0, 1_000),
    isActive: value.isActive,
    startsAt,
    endsAt,
  };
}

export function parseFeaturedBannerSaveRequest(value: unknown): FeaturedBannerSaveRequest {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  if (value.mode !== "create" && value.mode !== "update") {
    throw new HttpsError("invalid-argument", "mode must be create or update.");
  }
  return {
    mode: value.mode,
    banner: parseFeaturedBannerDraft(value.banner),
  };
}

function parseIDRequest(value: unknown): FeaturedBannerIDRequest {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  return { id: safeDocumentID(value.id) };
}

function parseActiveRequest(value: unknown): FeaturedBannerActiveRequest {
  const parsed = parseIDRequest(value);
  if (!isRecord(value) || typeof value.isActive !== "boolean") {
    throw new HttpsError("invalid-argument", "isActive must be a boolean.");
  }
  return { ...parsed, isActive: value.isActive };
}

export function canonicalFeaturedBannerData(
  banner: FeaturedBannerDraft,
  actorID: string,
  committedAt: Timestamp,
  existingData?: DocumentData
): DocumentData {
  const preservedCreatedAt = existingData?.createdAt instanceof Timestamp
    ? existingData.createdAt
    : committedAt;
  const preservedCreatedBy = typeof existingData?.createdBy === "string"
    && existingData.createdBy.trim().length > 0
    ? existingData.createdBy
    : actorID;

  return {
    id: banner.id,
    ...(banner.internalName ? { internalName: banner.internalName } : {}),
    ...(banner.title ? { title: banner.title } : {}),
    ...(banner.subtitle ? { subtitle: banner.subtitle } : {}),
    imageURL: banner.imageURL,
    actionType: banner.actionType,
    ...(banner.actionTargetID ? { actionTargetID: banner.actionTargetID } : {}),
    ...(banner.externalURL ? { externalURL: banner.externalURL } : {}),
    regionScope: banner.regionScope,
    ...(banner.federalState ? { federalState: banner.federalState } : {}),
    visibleSections: banner.visibleSections,
    displayDurationSeconds: banner.displayDurationSeconds,
    priority: banner.priority,
    isActive: banner.isActive,
    ...(banner.startsAt ? { startsAt: banner.startsAt } : {}),
    ...(banner.endsAt ? { endsAt: banner.endsAt } : {}),
    createdAt: preservedCreatedAt,
    updatedAt: committedAt,
    createdBy: preservedCreatedBy,
    updatedBy: actorID,
  };
}

function storedDraft(id: string, data: DocumentData): Record<string, unknown> {
  const isoString = (value: unknown): string | undefined =>
    value instanceof Timestamp ? value.toDate().toISOString() : undefined;

  return {
    id,
    internalName: data.internalName,
    title: data.title,
    subtitle: data.subtitle,
    imageURL: data.imageURL,
    actionType: data.actionType,
    actionTargetID: data.actionTargetID,
    externalURL: data.externalURL,
    regionScope: data.regionScope,
    federalState: data.federalState,
    visibleSections: data.visibleSections,
    displayDurationSeconds: data.displayDurationSeconds,
    priority: data.priority,
    isActive: data.isActive,
    startsAt: isoString(data.startsAt),
    endsAt: isoString(data.endsAt),
  };
}

async function requireVerifiedOwner(request: CallableRequest): Promise<string> {
  const auth = requireAuth(request);
  if (auth.token.email_verified !== true) {
    throw new HttpsError("permission-denied", "A verified owner account is required.");
  }
  assertOwner(await getUserPermissions(auth.uid));
  return auth.uid;
}

export const saveFeaturedBanner = onCall(
  callableOptions,
  async (request): Promise<FeaturedBannerMutationResponse> => {
    const actorID = await requireVerifiedOwner(request);
    const input = parseFeaturedBannerSaveRequest(request.data);
    const reference = db.collection("featuredBanners").doc(input.banner.id);
    const committedAt = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (input.mode === "create" && snapshot.exists) {
        throw new HttpsError("already-exists", "Featured banner already exists.");
      }
      if (input.mode === "update" && !snapshot.exists) {
        throw new HttpsError("not-found", "Featured banner does not exist.");
      }

      transaction.set(
        reference,
        canonicalFeaturedBannerData(input.banner, actorID, committedAt, snapshot.data())
      );
    });

    return {
      id: input.banner.id,
      updatedAt: committedAt.toDate().toISOString(),
    };
  }
);

export const setFeaturedBannerActive = onCall(
  callableOptions,
  async (request): Promise<FeaturedBannerMutationResponse> => {
    const actorID = await requireVerifiedOwner(request);
    const input = parseActiveRequest(request.data);
    const reference = db.collection("featuredBanners").doc(input.id);
    const committedAt = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "Featured banner does not exist.");
      }

      if (input.isActive) {
        try {
          parseFeaturedBannerDraft(storedDraft(input.id, snapshot.data() ?? {}));
        } catch (error) {
          if (error instanceof HttpsError && error.code === "invalid-argument") {
            throw new HttpsError(
              "failed-precondition",
              "Repair the featured banner before activating it."
            );
          }
          throw error;
        }
      }

      transaction.update(reference, {
        isActive: input.isActive,
        updatedAt: committedAt,
        updatedBy: actorID,
      });
    });

    return { id: input.id, updatedAt: committedAt.toDate().toISOString() };
  }
);

export const deleteFeaturedBanner = onCall(
  callableOptions,
  async (request): Promise<FeaturedBannerMutationResponse> => {
    await requireVerifiedOwner(request);
    const input = parseIDRequest(request.data);
    const reference = db.collection("featuredBanners").doc(input.id);
    const committedAt = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "Featured banner does not exist.");
      }
      transaction.delete(reference);
    });

    return { id: input.id, updatedAt: committedAt.toDate().toISOString() };
  }
);
