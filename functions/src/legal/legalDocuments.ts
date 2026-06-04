import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";

type LegalDocumentType = "terms" | "privacy";

interface AcceptLegalDocumentRequest {
  documentType: LegalDocumentType;
  version: string;
  appVersion?: string;
  locale?: string;
  acceptedFromPlatform?: string;
}

interface AcceptLegalDocumentResponse {
  documentType: LegalDocumentType;
  version: string;
  acceptedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

function parseAcceptLegalDocumentRequest(data: unknown): AcceptLegalDocumentRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const documentType = normalizedDocumentType(data.documentType);

  return {
    documentType,
    version: normalizedRequiredString(data.version, "version"),
    appVersion: optionalTrimmedString(data.appVersion, "appVersion"),
    locale: optionalTrimmedString(data.locale, "locale"),
    acceptedFromPlatform: optionalTrimmedString(
      data.acceptedFromPlatform,
      "acceptedFromPlatform"
    ) ?? "ios",
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedDocumentType(value: unknown): LegalDocumentType {
  if (value === "terms" || value === "privacy") {
    return value;
  }

  throw new HttpsError("invalid-argument", "documentType must be terms or privacy.");
}

function normalizedRequiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }

  return trimmedValue;
}

function optionalTrimmedString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  return trimmedValue.length > 0 ? trimmedValue : undefined;
}

function userAcceptanceUpdate(
  request: AcceptLegalDocumentRequest
): Record<string, unknown> {
  const acceptedAt = FieldValue.serverTimestamp();
  const baseUpdate = {
    updatedAt: FieldValue.serverTimestamp(),
  };

  switch (request.documentType) {
    case "terms":
      return {
        ...baseUpdate,
        acceptedTermsVersion: request.version,
        acceptedTermsAt: acceptedAt,
        termsVersion: request.version,
      };
    case "privacy":
      return {
        ...baseUpdate,
        acceptedPrivacyVersion: request.version,
        acceptedPrivacyAt: acceptedAt,
        privacyVersion: request.version,
      };
  }
}

export const acceptLegalDocument = onCall(
  callableOptions,
  async (request): Promise<AcceptLegalDocumentResponse> => {
    const auth = requireAuth(request);
    const legalRequest = parseAcceptLegalDocumentRequest(request.data);
    const userReference = db.collection("users").doc(auth.uid);
    const documentReference = db.collection("legalDocuments").doc(
      legalRequest.documentType
    );
    const versionReference = documentReference
      .collection("versions")
      .doc(legalRequest.version);
    const logReference = db.collection("legalAcceptanceLogs").doc();
    const committedAt = new Date().toISOString();

    await db.runTransaction(async (transaction) => {
      const [userSnapshot, documentSnapshot, versionSnapshot] = await Promise.all([
        transaction.get(userReference),
        transaction.get(documentReference),
        transaction.get(versionReference),
      ]);

      if (!userSnapshot.exists) {
        throw new HttpsError("permission-denied", "User profile does not exist.");
      }

      if (!documentSnapshot.exists) {
        throw new HttpsError("failed-precondition", "Legal document is not published.");
      }

      const documentData = documentSnapshot.data() ?? {};
      const activeVersion = documentData.activeVersion;
      if (activeVersion !== legalRequest.version) {
        throw new HttpsError("failed-precondition", "Requested version is not active.");
      }

      if (!versionSnapshot.exists) {
        throw new HttpsError("failed-precondition", "Legal version does not exist.");
      }

      const versionData = versionSnapshot.data() ?? {};
      if (versionData.status !== "published") {
        throw new HttpsError("failed-precondition", "Legal version is not published.");
      }

      transaction.update(userReference, userAcceptanceUpdate(legalRequest));
      transaction.set(logReference, {
        userId: auth.uid,
        documentType: legalRequest.documentType,
        version: legalRequest.version,
        acceptedAt: FieldValue.serverTimestamp(),
        appVersion: legalRequest.appVersion ?? null,
        locale: legalRequest.locale ?? null,
        contentHash: typeof versionData.contentHash === "string" ?
          versionData.contentHash :
          null,
        acceptedFromPlatform: legalRequest.acceptedFromPlatform ?? "ios",
      });
    });

    return {
      documentType: legalRequest.documentType,
      version: legalRequest.version,
      acceptedAt: committedAt,
    };
  }
);
