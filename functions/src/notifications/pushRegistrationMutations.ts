import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";
import { isStrictFirebaseInstallationID } from "./pushRegistrations";
import type { PushRegistrationKind } from "./pushRegistrations";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: true,
};
export const registrationDeletionPageSize = 250;

export interface PushRegistrationDeletionRequest {
  userId: string;
  identifier: string;
  registrationType: PushRegistrationKind;
}

export interface PushRegistrationDeletionCandidate {
  documentId: string;
  data: FirebaseFirestore.DocumentData;
}

interface PushRegistrationDeletionResponse {
  deletedRegistrationCount: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parsePushRegistrationDeletionRequest(
  value: unknown
): PushRegistrationDeletionRequest {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "The push registration request must be an object.");
  }
  const allowedFields = new Set(["userId", "identifier", "registrationType"]);
  if (Object.keys(value).some((key) => !allowedFields.has(key))) {
    throw new HttpsError("invalid-argument", "The push registration request has unsupported fields.");
  }

  const userId = typeof value.userId === "string" ? value.userId.trim() : "";
  if (userId.length === 0 || userId.length > 256 || userId.includes("/")) {
    throw new HttpsError("invalid-argument", "userId must be a valid user ID.");
  }

  const identifier = typeof value.identifier === "string" ? value.identifier.trim() : "";
  if (identifier.length === 0 || identifier.length > 4_096) {
    throw new HttpsError("invalid-argument", "identifier must be a valid push registration.");
  }
  if (value.registrationType !== "fid" && value.registrationType !== "token") {
    throw new HttpsError("invalid-argument", "registrationType must be fid or token.");
  }
  if (value.registrationType === "fid" && !isStrictFirebaseInstallationID(identifier)) {
    throw new HttpsError("invalid-argument", "identifier must be a valid Firebase Installation ID.");
  }

  return {
    userId,
    identifier,
    registrationType: value.registrationType,
  };
}

export function assertPushRegistrationOwner(
  authenticatedUserId: string,
  input: PushRegistrationDeletionRequest
): void {
  if (input.userId !== authenticatedUserId) {
    throw new HttpsError(
      "permission-denied",
      "The registration owner does not match authentication."
    );
  }
}

/**
 * Selects only the current registration and legacy tokens proven by Firebase
 * Messaging 12.18's strict FID-prefix invariant to belong to the same install.
 */
export function registrationDocumentIDsForDeletion(
  candidates: PushRegistrationDeletionCandidate[],
  request: PushRegistrationDeletionRequest
): string[] {
  return candidates.flatMap((candidate) => {
    const identifier = typeof candidate.data.token === "string"
      ? candidate.data.token
      : "";
    if (identifier.length === 0) {
      return [];
    }

    const isExactRegistration = identifier === request.identifier;
    const isSameInstallationLegacyToken = request.registrationType === "fid"
      && identifier.length > request.identifier.length
      && identifier.startsWith(request.identifier);
    return isExactRegistration || isSameInstallationLegacyToken
      ? [candidate.documentId]
      : [];
  });
}

export async function deletePushRegistrationsForUser(
  userId: string,
  input: PushRegistrationDeletionRequest
): Promise<number> {
  const collection = db.collection("users")
    .doc(userId)
    .collection("notificationPushTokens");
  let deletedRegistrationCount = 0;

  while (true) {
    const baseQuery = input.registrationType === "fid"
      ? collection
        .where("token", ">=", input.identifier)
        .where("token", "<", `${input.identifier}\uf8ff`)
      : collection.where("token", "==", input.identifier);
    const registrations = await baseQuery.limit(registrationDeletionPageSize).get();
    if (registrations.empty) {
      break;
    }

    const batch = db.batch();
    for (const document of registrations.docs) {
      batch.delete(document.ref);
    }
    await batch.commit();
    deletedRegistrationCount += registrations.size;
  }

  return deletedRegistrationCount;
}

export const deleteNotificationPushRegistration = onCall(
  callableOptions,
  async (request): Promise<PushRegistrationDeletionResponse> => {
    // Any authenticated account may clean its own route. Requiring verified or
    // active status here would prevent safe sign-out for suspended/unverified users.
    const auth = requireAuth(request);
    const input = parsePushRegistrationDeletionRequest(request.data);
    assertPushRegistrationOwner(auth.uid, input);

    const deletedRegistrationCount = await deletePushRegistrationsForUser(auth.uid, input);

    return { deletedRegistrationCount };
  }
);
