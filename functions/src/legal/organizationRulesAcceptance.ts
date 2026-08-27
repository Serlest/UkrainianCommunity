import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {isOwner} from "../permissions/userPermissions";

interface AcceptOrganizationRulesRequest {
  organizationId: string;
  organizationName: string;
  version: string;
  appVersion?: string;
  locale?: string;
  acceptedFromPlatform?: string;
}

interface AcceptOrganizationRulesResponse {
  organizationId: string;
  version: string;
  acceptedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};
const proofValidityDays = 30;
export const maximumUnpublishedOrganizationRequests = 3;
const unpublishedOrganizationStatuses = ["pendingReview", "needsRevision", "rejected"];

export const acceptOrganizationRules = onCall(
  callableOptions,
  async (request): Promise<AcceptOrganizationRulesResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const input = parseRequest(request.data);
    const documentReference = db.collection("legalDocuments").doc("organizationRules");
    const versionReference = documentReference.collection("versions").doc(input.version);
    const proofReference = db.collection("organizationCreationProofs").doc(input.organizationId);
    const logReference = db.collection("legalAcceptanceLogs").doc();
    const requestQuery = db.collection("organizations")
      .where("submittedByUserId", "==", auth.uid)
      .where("moderationStatus", "in", unpublishedOrganizationStatuses)
      .limit(maximumUnpublishedOrganizationRequests + 1);
    let committedAt = new Date();

    await db.runTransaction(async (transaction) => {
      const [documentSnapshot, versionSnapshot, proofSnapshot, requestSnapshot] = await Promise.all([
        transaction.get(documentReference),
        transaction.get(versionReference),
        transaction.get(proofReference),
        transaction.get(requestQuery),
      ]);

      if (!isOwner(auth.permissions)) {
        const otherRequestCount = requestSnapshot.docs.filter(
          (document) => document.id !== input.organizationId
        ).length;
        if (hasReachedOrganizationRequestLimit(otherRequestCount)) {
          throw new HttpsError(
            "resource-exhausted",
            "Resolve or delete an existing organization request before creating another.",
            {reason: "organization-request-limit", maximum: maximumUnpublishedOrganizationRequests}
          );
        }
      }

      if (!documentSnapshot.exists || documentSnapshot.data()?.activeVersion !== input.version) {
        throw new HttpsError("failed-precondition", "Requested organization rules are not active.");
      }
      const versionData = versionSnapshot.data();
      if (!versionSnapshot.exists || versionData?.status !== "published") {
        throw new HttpsError("failed-precondition", "Organization rules are not published.");
      }

      const existing = proofSnapshot.data();
      if (
        existing?.userId === auth.uid &&
        existing?.version === input.version &&
        existing?.organizationName === input.organizationName &&
        existing?.expiresAt instanceof Timestamp &&
        existing.expiresAt.toMillis() > Date.now()
      ) {
        committedAt = existing.acceptedAt instanceof Timestamp ?
          existing.acceptedAt.toDate() :
          committedAt;
        return;
      }

      committedAt = new Date();
      const expiresAt = Timestamp.fromMillis(
        committedAt.getTime() + proofValidityDays * 24 * 60 * 60 * 1_000
      );
      const evidence = {
        userId: auth.uid,
        documentType: "organizationRules",
        version: input.version,
        acceptedAt: FieldValue.serverTimestamp(),
        appVersion: input.appVersion ?? null,
        locale: input.locale ?? null,
        contentHash: typeof versionData?.contentHash === "string" ? versionData.contentHash : null,
        acceptedFromPlatform: input.acceptedFromPlatform ?? "ios",
        organizationId: input.organizationId,
        organizationName: input.organizationName,
      };

      transaction.set(proofReference, {
        ...evidence,
        expiresAt,
      });
      transaction.set(logReference, evidence);
    });

    return {
      organizationId: input.organizationId,
      version: input.version,
      acceptedAt: committedAt.toISOString(),
    };
  }
);

export function parseOrganizationRulesAcceptanceRequest(
  data: unknown
): AcceptOrganizationRulesRequest {
  return parseRequest(data);
}

export function hasReachedOrganizationRequestLimit(otherRequestCount: number): boolean {
  return Number.isInteger(otherRequestCount)
    && otherRequestCount >= maximumUnpublishedOrganizationRequests;
}

function parseRequest(data: unknown): AcceptOrganizationRulesRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  const organizationId = requiredString(data.organizationId, "organizationId", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(organizationId)) {
    throw new HttpsError("invalid-argument", "organizationId has an invalid format.");
  }

  return {
    organizationId,
    organizationName: requiredString(data.organizationName, "organizationName", 180),
    version: requiredString(data.version, "version", 80),
    appVersion: optionalString(data.appVersion, "appVersion", 80),
    locale: optionalString(data.locale, "locale", 20),
    acceptedFromPlatform: optionalString(
      data.acceptedFromPlatform,
      "acceptedFromPlatform",
      40
    ) ?? "ios",
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(value: unknown, field: string, maximumLength: number): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximumLength) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must contain 1 to ${maximumLength} characters.`
    );
  }
  return normalized;
}

function optionalString(
  value: unknown,
  field: string,
  maximumLength: number
): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length > maximumLength) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must contain at most ${maximumLength} characters.`
    );
  }
  return normalized.length > 0 ? normalized : undefined;
}
