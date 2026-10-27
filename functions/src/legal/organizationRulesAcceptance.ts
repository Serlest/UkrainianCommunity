import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {assertActiveUser, assertPrivilegedMFA, hasCurrentLegalAcknowledgements, requireVerifiedAuth} from "../auth/context";
import {db} from "../firebase/admin";
import {isOwner, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {hasValidPublishedLegalContent} from "./legalDocumentIntegrity";

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
  enforceAppCheck: false,
};
const proofValidityDays = 30;
export const maximumUnpublishedOrganizationRequests = 3;
const unpublishedOrganizationStatuses = ["pendingReview", "needsRevision", "rejected"];

export const acceptOrganizationRules = onCall(
  callableOptions,
  async (request): Promise<AcceptOrganizationRulesResponse> => {
    const auth = requireVerifiedAuth(request);
    const input = parseRequest(request.data);
    const documentReference = db.collection("legalDocuments").doc("organizationRules");
    const versionReference = documentReference.collection("versions").doc(input.version);
    const proofReference = db.collection("organizationCreationProofs").doc(input.organizationId);
    const logReference = db.collection("legalAcceptanceLogs").doc();
    const requestQuery = db.collection("organizations")
      .where("submittedByUserId", "==", auth.uid)
      .where("moderationStatus", "in", unpublishedOrganizationStatuses)
      .limit(maximumUnpublishedOrganizationRequests + 1);
    const acceptedAt = await db.runTransaction(async (transaction) => {
      const [userSnapshot, termsSnapshot, privacySnapshot, documentSnapshot, versionSnapshot, proofSnapshot, requestSnapshot] = await Promise.all([
        transaction.get(db.doc(`users/${auth.uid}`)),
        transaction.get(db.doc("legalDocuments/terms")),
        transaction.get(db.doc("legalDocuments/privacy")),
        transaction.get(documentReference),
        transaction.get(versionReference),
        transaction.get(proofReference),
        transaction.get(requestQuery),
      ]);

      if (!userSnapshot.exists) throw new HttpsError("permission-denied", "User profile does not exist.");
      const permissions = userPermissionSnapshotFromData(auth.uid, userSnapshot.data());
      assertActiveUser(permissions);
      assertPrivilegedMFA(auth.token, permissions);
      if (!hasCurrentLegalAcknowledgements(permissions, {terms: termsSnapshot.get("activeVersion"), privacy: privacySnapshot.get("activeVersion")})) {
        throw new HttpsError("failed-precondition", "Current legal documents must be acknowledged.");
      }

      if (!isOwner(permissions)) {
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

      const pointer = documentSnapshot.data(), versionData = versionSnapshot.data();
      if (!pointer || !versionData || !hasValidPublishedLegalContent("organizationRules", input.version, pointer, versionData)) {
        throw new HttpsError("failed-precondition", "Organization rules are not active or their integrity could not be verified.");
      }
      const contentHash = versionData.contentHash as string;
      const existing = proofSnapshot.data();
      // This endpoint reserves a new creation ID; editing/transferred organizations
      // does not use it. A different account must never take over that reservation.
      if (proofSnapshot.exists && existing?.userId !== auth.uid) {
        throw new HttpsError("permission-denied", "Organization proof belongs to another account.");
      }
      if (
        existing?.userId === auth.uid &&
        existing?.version === input.version &&
        existing?.organizationName === input.organizationName &&
        existing?.contentHash === contentHash &&
        existing?.acceptedAt instanceof Timestamp &&
        existing?.expiresAt instanceof Timestamp &&
        existing.expiresAt.toMillis() > Date.now()
      ) {
        return existing.acceptedAt.toDate().toISOString();
      }

      const committedAt = Timestamp.now();
      const expiresAt = Timestamp.fromMillis(
        committedAt.toMillis() + proofValidityDays * 24 * 60 * 60 * 1_000
      );
      const evidence = {
        userId: auth.uid,
        documentType: "organizationRules",
        version: input.version,
        acceptedAt: committedAt,
        appVersion: input.appVersion ?? null,
        locale: input.locale ?? null,
        contentHash,
        acceptedFromPlatform: input.acceptedFromPlatform ?? "ios",
        organizationId: input.organizationId,
        organizationName: input.organizationName,
      };

      transaction.set(proofReference, {
        ...evidence,
        expiresAt,
      });
      transaction.set(logReference, evidence);
      return committedAt.toDate().toISOString();
    });

    return {
      organizationId: input.organizationId,
      version: input.version,
      acceptedAt,
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
