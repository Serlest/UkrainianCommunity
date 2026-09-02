import {type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {adminAuth, db} from "../firebase/admin";
import {assertCanManageUsers} from "../permissions/userPermissions";

interface UserSearchRequest {
  query: string;
  limit: number;
}

interface UserSearchResponse {
  userIds: string[];
  totalMatches: number;
}

interface UserSecurityMetadataRequest {
  targetUserId: string;
}

interface UserSecurityMetadataResponse {
  targetUserId: string;
  emailVerified: boolean;
  authDisabled: boolean;
  creationTime: string | null;
  lastSignInTime: string | null;
  providerIds: string[];
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  enforceAppCheck: false,
};

const searchableFields = [
  "displayName",
  "fullName",
  "email",
  "telegramUsername",
  "city",
  "selectedFederalState",
] as const;

export function normalizeUserSearchQuery(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "query must be a string.");
  }

  const normalized = value
    .trim()
    .toLocaleLowerCase("uk-UA")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
  if (normalized.length < 2) {
    throw new HttpsError("invalid-argument", "query must contain at least 2 characters.");
  }
  if (normalized.length > 120) {
    throw new HttpsError("invalid-argument", "query is too long.");
  }
  return normalized;
}

function normalizedLimit(value: unknown): number {
  if (value === undefined || value === null) {
    return 100;
  }
  if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > 100) {
    throw new HttpsError("invalid-argument", "limit must be an integer between 1 and 100.");
  }
  return Number(value);
}

function requiredTargetUserId(value: unknown): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", "targetUserId is required.");
  }
  return value.trim();
}

export function userDocumentMatchesSearch(
  documentId: string,
  data: DocumentData,
  normalizedQuery: string
): boolean {
  const values = [documentId, ...searchableFields.map((field) => data[field])];
  const searchableText = values
    .filter((value): value is string => typeof value === "string")
    .join(" ")
    .toLocaleLowerCase("uk-UA")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ");
  const tokens = normalizedQuery.split(/\s+/).filter(Boolean);
  return tokens.every((token) => searchableText.includes(token));
}

export const searchManagedUsers = onCall(
  callableOptions,
  async (request): Promise<UserSearchResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertCanManageUsers(auth.permissions);

    const data = request.data as Partial<UserSearchRequest> | undefined;
    const query = normalizeUserSearchQuery(data?.query);
    const limit = normalizedLimit(data?.limit);
    const snapshot = await db.collection("users")
      .select(...searchableFields)
      .get();

    const matchingIds = snapshot.docs
      .filter((document) => userDocumentMatchesSearch(document.id, document.data(), query))
      .map((document) => document.id);

    return {
      userIds: matchingIds.slice(0, limit),
      totalMatches: matchingIds.length,
    };
  }
);

export const getManagedUserSecurityMetadata = onCall(
  callableOptions,
  async (request): Promise<UserSecurityMetadataResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    assertCanManageUsers(auth.permissions);

    const data = request.data as Partial<UserSecurityMetadataRequest> | undefined;
    const targetUserId = requiredTargetUserId(data?.targetUserId);

    try {
      const user = await adminAuth.getUser(targetUserId);
      return {
        targetUserId,
        emailVerified: user.emailVerified,
        authDisabled: user.disabled,
        creationTime: user.metadata.creationTime ?? null,
        lastSignInTime: user.metadata.lastSignInTime ?? null,
        providerIds: [...new Set(user.providerData.map((provider) => provider.providerId))].sort(),
      };
    } catch (error) {
      const code = typeof error === "object" && error !== null && "code" in error
        ? String(error.code)
        : "";
      if (code === "auth/user-not-found") {
        throw new HttpsError("not-found", "Target authentication account does not exist.");
      }
      throw error;
    }
  }
);
