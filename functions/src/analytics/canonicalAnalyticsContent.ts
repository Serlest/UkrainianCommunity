import {type DocumentData} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {db} from "../firebase/admin";

export type AnalyticsContentType = "news" | "event" | "organization";

export interface CanonicalAnalyticsContent {
  contentID: string;
  contentType: AnalyticsContentType;
  title: string;
  category?: string;
  organizationID?: string;
  organizationName?: string;
  federalState?: string;
  regionScope?: string;
}

const collectionByContentType: Record<AnalyticsContentType, string> = {
  news: "news",
  event: "events",
  organization: "organizations",
};

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

const regionScopes = new Set(["austria", "federalState", "city"]);

export async function resolveCanonicalAnalyticsContent(
  contentType: AnalyticsContentType,
  contentID: string
): Promise<CanonicalAnalyticsContent> {
  const snapshot = await db
    .collection(collectionByContentType[contentType])
    .doc(contentID)
    .get();

  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Analytics content is unavailable.");
  }

  return canonicalAnalyticsContentFromData(contentType, contentID, snapshot.data());
}

export function canonicalAnalyticsContentFromData(
  contentType: AnalyticsContentType,
  contentID: string,
  data: DocumentData | undefined
): CanonicalAnalyticsContent {
  if (
    data?.moderationStatus !== "approved"
    || (data.archivedAt !== undefined && data.archivedAt !== null)
  ) {
    throw new HttpsError("not-found", "Analytics content is unavailable.");
  }

  const titleField = contentType === "organization" ? "name" : "title";
  const title = requiredDisplayText(data[titleField], titleField);
  const organizationID = contentType === "organization"
    ? contentID
    : optionalSafeID(data.organizationId);
  const organizationName = contentType === "organization"
    ? title
    : optionalDisplayText(data.organizationName);

  const category = optionalSlug(data.category);
  const federalState = optionalEnumValue(data.federalState, federalStates);
  const regionScope = optionalEnumValue(data.regionScope, regionScopes);

  return {
    contentID,
    contentType,
    title,
    ...(category === undefined ? {} : {category}),
    ...(organizationID === undefined ? {} : {organizationID}),
    ...(organizationName === undefined ? {} : {organizationName}),
    ...(federalState === undefined ? {} : {federalState}),
    ...(regionScope === undefined ? {} : {regionScope}),
  };
}

function requiredDisplayText(value: unknown, field: string): string {
  const text = optionalDisplayText(value);
  if (text === undefined) {
    throw new HttpsError("failed-precondition", `${field} is missing from analytics content.`);
  }
  return text;
}

function optionalDisplayText(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 0 && normalized.length <= 120 ? normalized : undefined;
}

function optionalSafeID(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  return /^[A-Za-z0-9._:-]{1,128}$/.test(normalized) ? normalized : undefined;
}

function optionalSlug(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.trim();
  return /^[A-Za-z0-9_-]{1,64}$/.test(normalized) ? normalized : undefined;
}

function optionalEnumValue(value: unknown, allowed: Set<string>): string | undefined {
  const normalized = optionalSlug(value);
  return normalized !== undefined && allowed.has(normalized) ? normalized : undefined;
}
