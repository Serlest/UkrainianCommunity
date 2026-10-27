import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { assertActiveUser, assertPrivilegedMFA, requireVerifiedActiveUserWithoutLegal } from "../auth/context";
import { db } from "../firebase/admin";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {hasValidPublishedLegalContent, legalSHA256} from "./legalDocumentIntegrity";

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
  enforceAppCheck: false,
};

function parseAcceptLegalDocumentRequest(data: unknown): AcceptLegalDocumentRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const documentType = normalizedDocumentType(data.documentType);
  if (typeof data.version !== "string" || !/^[0-9]{4}\.[1-9][0-9]?$/.test(data.version.trim())) {
    throw new HttpsError("invalid-argument", "Invalid legal version.");
  }

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
  request: AcceptLegalDocumentRequest, acceptedAt: Timestamp
): Record<string, unknown> {
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
    const auth = await requireVerifiedActiveUserWithoutLegal(request);
    const legalRequest = parseAcceptLegalDocumentRequest(request.data);
    const userReference = db.collection("users").doc(auth.uid);
    const documentReference = db.collection("legalDocuments").doc(
      legalRequest.documentType
    );
    const versionReference = documentReference
      .collection("versions")
      .doc(legalRequest.version);
    const acceptedAt = await db.runTransaction(async (transaction) => {
      const [userSnapshot, documentSnapshot, versionSnapshot] = await Promise.all([
        transaction.get(userReference), transaction.get(documentReference), transaction.get(versionReference),
      ]);
      if (!userSnapshot.exists) throw new HttpsError("permission-denied", "User profile does not exist.");
      const userData = userSnapshot.data() ?? {};
      const permissions = userPermissionSnapshotFromData(auth.uid, userData);
      assertActiveUser(permissions);
      assertPrivilegedMFA(auth.token, permissions);
      const pointer = documentSnapshot.data(), version = versionSnapshot.data();
      if (!pointer || !version || !hasValidPublishedLegalContent(legalRequest.documentType, legalRequest.version, pointer, version)) {
        throw new HttpsError("failed-precondition", "The requested legal version is not active or its integrity could not be verified.");
      }
      const contentHash = version.contentHash as string;
      const logReference = db.collection("legalAcceptanceLogs").doc("ack_" + legalSHA256(
        JSON.stringify([auth.uid, legalRequest.documentType, legalRequest.version, contentHash])
      ));
      // Preserve initial registration and historical random-ID receipts. Never rewrite them.
      // Equality-only queries use Firestore index merging; no unordered receipt scan is needed.
      const legacyQuery = db.collection("legalAcceptanceLogs").where("userId", "==", auth.uid)
        .where("documentType", "==", legalRequest.documentType).where("version", "==", legalRequest.version)
        .where("contentHash", "==", contentHash).limit(1);
      const [canonical, legacy] = await Promise.all([transaction.get(logReference), transaction.get(legacyQuery)]);
      const existing = canonical.exists ? canonical.data() : legacy.docs[0]?.data();
      let timestamp: Timestamp;
      if (existing) {
        if (existing.userId !== auth.uid || existing.documentType !== legalRequest.documentType
          || existing.version !== legalRequest.version || existing.contentHash !== contentHash
          || !(existing.acceptedAt instanceof Timestamp)) {
          throw new HttpsError("failed-precondition", "Stored legal acknowledgement cannot be verified.");
        }
        timestamp = existing.acceptedAt;
      } else {
        timestamp = Timestamp.now();
        transaction.create(logReference, {
          userId: auth.uid, documentType: legalRequest.documentType, version: legalRequest.version,
          acceptedAt: timestamp, appVersion: legalRequest.appVersion ?? null, locale: legalRequest.locale ?? null,
          contentHash, acceptedFromPlatform: legalRequest.acceptedFromPlatform ?? "ios",
        });
      }
      const field = legalRequest.documentType === "terms" ? "acceptedTermsVersion" : "acceptedPrivacyVersion";
      const dateField = legalRequest.documentType === "terms" ? "acceptedTermsAt" : "acceptedPrivacyAt";
      if (userData[field] !== legalRequest.version || !(userData[dateField] instanceof Timestamp)
        || !userData[dateField].isEqual(timestamp)) {
        transaction.update(userReference, userAcceptanceUpdate(legalRequest, timestamp));
      }
      return timestamp.toDate().toISOString();
    });
    return {documentType: legalRequest.documentType, version: legalRequest.version, acceptedAt};
  }
);
