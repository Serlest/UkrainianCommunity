import {assertActiveUser} from "../auth/context";
import {Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireLegacyCallableUser as requireVerifiedActiveUser} from "../auth/legacyCallableContext";
import {storageObjectPathFromDownloadURL} from "../content/contentDeletionPolicy";
import {db} from "../firebase/admin";
import {isOwner, userPermissionSnapshotFromData, type UserPermissionSnapshot} from "../permissions/userPermissions";

import {photoRetirement, queuePhotoGarbage} from "./organizationPhotoGarbage";
import {accessFailure, withAccessDiagnostics} from "./organizationAccessDiagnostics";

export const maximumOrganizationPhotoCount = 30;
const maximumCaptionLength = 500;

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  enforceAppCheck: false,
};

interface CreateOrganizationPhotoRequest {
  organizationId: string;
  photoId: string;
  imageURL: string;
  caption?: string;
}

interface DeleteOrganizationPhotoRequest {
  organizationId: string;
  photoId: string;
}

export interface OrganizationPhotoMutationResponse {
  organizationId: string;
  photoId: string;
  photoCount: number;
  didChange: boolean;
  uploadedBy?: string;
  createdAt?: string;
}

export const createOrganizationPhotoMetadata = onCall(
  callableOptions,
  request => withAccessDiagnostics(request, "createOrganizationPhotoMetadata", async (): Promise<OrganizationPhotoMutationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    if (request.data?.principalId !== undefined && request.data.principalId !== auth.uid) {
      throw new HttpsError("permission-denied", "The account changed before the photo operation.");
    }
    const input = parseCreateOrganizationPhotoRequest(request.data);
    const organizationReference = db.collection("organizations").doc(input.organizationId);
    const photos = organizationReference.collection("photos");
    const photoReference = photos.doc(input.photoId);

    return db.runTransaction(async (transaction) => {
      const [organizationSnapshot, photoSnapshot, profileSnapshot, retirement] = await transaction.getAll(
        organizationReference,
        photoReference,
        db.doc(`users/${auth.uid}`),
        photoRetirement(`organizations/${input.organizationId}/photos/${input.photoId}.jpg`)
      );
      if (!organizationSnapshot.exists) {
        throw new HttpsError("not-found", "Organization does not exist.");
      }

      if (!profileSnapshot.exists) throw new HttpsError("permission-denied", "User profile no longer exists.");
      const permissions = userPermissionSnapshotFromData(auth.uid, profileSnapshot.data());
      assertActiveUser(permissions);
      assertCanManageOrganizationPhotos(
        permissions,
        organizationSnapshot.data(),
        auth.uid
      );

      const photoSnapshotList = await transaction.get(
        photos.limit(maximumOrganizationPhotoCount + 1)
      );
      const currentCount = photoSnapshotList.size;

      if (photoSnapshot.exists) {
        return existingPhotoResponse(
          input.organizationId,
          input.photoId,
          currentCount,
          photoSnapshot.data()
        );
      }

      if (retirement.exists) throw accessFailure("failed-precondition", "operation_expired", "This abandoned upload has expired. Select the photo again.");
      if (currentCount >= maximumOrganizationPhotoCount) {
        throw new HttpsError(
          "resource-exhausted",
          `An organization can contain at most ${maximumOrganizationPhotoCount} photos.`
        );
      }

      const now = Timestamp.now();
      transaction.create(photoReference, {
        id: input.photoId,
        organizationId: input.organizationId,
        imageURL: input.imageURL,
        caption: input.caption ?? null,
        uploadedBy: auth.uid,
        createdAt: now,
        updatedAt: null,
      });
      transaction.update(organizationReference, {
        photoCount: currentCount + 1,
      });

      return {
        organizationId: input.organizationId,
        photoId: input.photoId,
        photoCount: currentCount + 1,
        didChange: true,
        uploadedBy: auth.uid,
        createdAt: now.toDate().toISOString(),
      };
    });
  })
);

export const deleteOrganizationPhotoMetadata = onCall(
  callableOptions,
  request => withAccessDiagnostics(request, "deleteOrganizationPhotoMetadata", async (): Promise<OrganizationPhotoMutationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    if (request.data?.principalId !== undefined && request.data.principalId !== auth.uid) {
      throw new HttpsError("permission-denied", "The account changed before the photo operation.");
    }
    const input = parseDeleteOrganizationPhotoRequest(request.data);
    const organizationReference = db.collection("organizations").doc(input.organizationId);
    const photos = organizationReference.collection("photos");
    const photoReference = photos.doc(input.photoId);

    return db.runTransaction(async (transaction) => {
      const [organizationSnapshot, photoSnapshot, profileSnapshot] = await transaction.getAll(
        organizationReference,
        photoReference,
        db.doc(`users/${auth.uid}`)
      );
      if (!organizationSnapshot.exists) {
        throw new HttpsError("not-found", "Organization does not exist.");
      }

      if (!profileSnapshot.exists) throw new HttpsError("permission-denied", "User profile no longer exists.");
      const permissions = userPermissionSnapshotFromData(auth.uid, profileSnapshot.data());
      assertActiveUser(permissions);
      assertCanManageOrganizationPhotos(
        permissions,
        organizationSnapshot.data(),
        auth.uid
      );

      const photoSnapshotList = await transaction.get(
        photos.limit(maximumOrganizationPhotoCount + 1)
      );
      const currentCount = photoSnapshotList.size;
      if (!photoSnapshot.exists) {
        return {
          organizationId: input.organizationId,
          photoId: input.photoId,
          photoCount: currentCount,
          didChange: false,
        };
      }

      const nextCount = Math.max(0, currentCount - 1);
      const path = typeof photoSnapshot.get("imageURL") === "string" ? storageObjectPathFromDownloadURL(photoSnapshot.get("imageURL")) : undefined;
      if (path) queuePhotoGarbage(transaction, input.organizationId, input.photoId, path);
      transaction.delete(photoReference);
      transaction.update(organizationReference, {photoCount: nextCount});

      return {
        organizationId: input.organizationId,
        photoId: input.photoId,
        photoCount: nextCount,
        didChange: true,
      };
    });
  })
);

export function parseCreateOrganizationPhotoRequest(
  data: unknown
): CreateOrganizationPhotoRequest {
  const record = requestRecord(data);
  const organizationId = documentId(record.organizationId, "organizationId");
  const photoId = documentId(record.photoId, "photoId");
  const imageURL = requiredString(record.imageURL, "imageURL");
  const expectedPath = `organizations/${organizationId}/photos/${photoId}.jpg`;
  if (storageObjectPathFromDownloadURL(imageURL) !== expectedPath) {
    throw new HttpsError("invalid-argument", "imageURL must reference the expected photo object.");
  }

  return {
    organizationId,
    photoId,
    imageURL,
    caption: optionalCaption(record.caption),
  };
}

export function parseDeleteOrganizationPhotoRequest(
  data: unknown
): DeleteOrganizationPhotoRequest {
  const record = requestRecord(data);
  return {
    organizationId: documentId(record.organizationId, "organizationId"),
    photoId: documentId(record.photoId, "photoId"),
  };
}

export function canManageOrganizationPhotos(
  user: UserPermissionSnapshot,
  organization: DocumentData | undefined,
  uid: string
): boolean {
  if (isOwner(user)) {
    return true;
  }
  if (!organization) {
    return false;
  }
  return organization.ownerId === uid
    || stringArray(organization.adminIds).includes(uid)
    || stringArray(organization.moderatorIds).includes(uid);
}

function assertCanManageOrganizationPhotos(
  user: UserPermissionSnapshot,
  organization: DocumentData | undefined,
  uid: string
): void {
  if (!canManageOrganizationPhotos(user, organization, uid)) {
    throw new HttpsError(
      "permission-denied",
      "Organization photo management permissions are required."
    );
  }
}

function existingPhotoResponse(
  organizationId: string,
  photoId: string,
  photoCount: number,
  data: DocumentData | undefined
): OrganizationPhotoMutationResponse {
  const uploadedBy = typeof data?.uploadedBy === "string" ? data.uploadedBy : undefined;
  const createdAt = data?.createdAt instanceof Timestamp
    ? data.createdAt.toDate().toISOString()
    : undefined;
  if (!uploadedBy || !createdAt) {
    throw new HttpsError("failed-precondition", "Existing photo metadata is invalid.");
  }
  return {
    organizationId,
    photoId,
    photoCount,
    didChange: false,
    uploadedBy,
    createdAt,
  };
}

function requestRecord(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }
  return value as Record<string, unknown>;
}

function documentId(value: unknown, field: string): string {
  const normalized = requiredString(value, field);
  if (normalized.length > 512 || normalized.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} must be a valid document ID.`);
  }
  return normalized;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (!normalized) {
    throw new HttpsError("invalid-argument", `${field} must not be empty.`);
  }
  return normalized;
}

function optionalCaption(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "caption must be a string.");
  }
  const normalized = value.trim();
  if (normalized.length > maximumCaptionLength) {
    throw new HttpsError(
      "invalid-argument",
      `caption must contain at most ${maximumCaptionLength} characters.`
    );
  }
  return normalized || undefined;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}
