import {randomUUID} from "node:crypto";

import {FieldValue, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {adminStorage, db} from "../firebase/admin";
import {isOwner, type UserPermissionSnapshot} from "../permissions/userPermissions";

const maximumCoverBytes = 3_000_000;
const maximumBase64Length = Math.ceil(maximumCoverBytes / 3) * 4;
const supportedKinds = new Set(["news", "event"] as const);

type ContentCoverKind = "news" | "event";

interface ContentCoverUploadRequest {
  kind: ContentCoverKind;
  contentId: string;
  imageBase64: string;
}

export interface ContentCoverUploadResponse {
  kind: ContentCoverKind;
  contentId: string;
  imageURL: string;
  byteCount: number;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
  memory: "512MiB" as const,
  timeoutSeconds: 120,
  enforceAppCheck: false,
};

export const uploadOrganizationContentCover = onCall(
  callableOptions,
  async (request): Promise<ContentCoverUploadResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const input = parseContentCoverUploadRequest(request.data);
    const collection = input.kind === "news" ? "news" : "events";
    const contentReference = db.collection(collection).doc(input.contentId);
    const contentSnapshot = await contentReference.get();
    if (!contentSnapshot.exists) {
      throw new HttpsError("not-found", "Content does not exist.");
    }

    const content = contentSnapshot.data();
    const organizationId = organizationIdFromContent(content);
    if (!organizationId) {
      if (!isOwner(auth.permissions) || content?.sourceType !== "app") {
        throw new HttpsError(
          "permission-denied",
          "Organization content publishing permissions are required."
        );
      }
    } else {
      const organizationSnapshot = await db.collection("organizations").doc(organizationId).get();
      if (!organizationSnapshot.exists) {
        throw new HttpsError("failed-precondition", "Content organization does not exist.");
      }
      assertCanManageOrganizationContent(
        auth.permissions,
        organizationSnapshot.data(),
        auth.uid
      );
    }

    const objectPath = `${collection}/${input.contentId}/cover.jpg`;
    const downloadToken = randomUUID();
    const bucket = adminStorage.bucket();
    const object = bucket.file(objectPath);

    await object.save(input.image, {
      resumable: false,
      contentType: "image/jpeg",
      metadata: {
        cacheControl: "public,max-age=3600",
        metadata: {firebaseStorageDownloadTokens: downloadToken},
      },
    });

    const imageURL = firebaseDownloadURL(bucket.name, objectPath, downloadToken);
    try {
      await contentReference.update({
        imageURL,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      await object.delete({ignoreNotFound: true}).catch(() => undefined);
      throw error;
    }

    return {
      kind: input.kind,
      contentId: input.contentId,
      imageURL,
      byteCount: input.image.length,
    };
  }
);

export function parseContentCoverUploadRequest(
  value: unknown
): ContentCoverUploadRequest & {image: Buffer} {
  const record = requestRecord(value);
  const keys = Object.keys(record).sort();
  if (keys.join(",") !== "contentId,imageBase64,kind") {
    throw new HttpsError("invalid-argument", "Request payload has unsupported fields.");
  }

  const kind = requiredString(record.kind, "kind");
  if (!supportedKinds.has(kind as ContentCoverKind)) {
    throw new HttpsError("invalid-argument", "kind must be news or event.");
  }
  const contentId = documentId(record.contentId, "contentId");
  const imageBase64 = requiredString(record.imageBase64, "imageBase64");
  if (imageBase64.length > maximumBase64Length
    || imageBase64.length % 4 !== 0
    || !/^[A-Za-z0-9+/]+={0,2}$/.test(imageBase64)) {
    throw new HttpsError("invalid-argument", "imageBase64 is not a supported JPEG payload.");
  }

  const image = Buffer.from(imageBase64, "base64");
  if (image.length === 0 || image.length >= maximumCoverBytes || !isJPEG(image)) {
    throw new HttpsError("invalid-argument", "The cover must be a JPEG smaller than 3 MB.");
  }

  return {kind: kind as ContentCoverKind, contentId, imageBase64, image};
}

export function canManageOrganizationContent(
  user: UserPermissionSnapshot,
  organization: DocumentData | undefined,
  uid: string
): boolean {
  if (isOwner(user)) return true;
  if (!organization) return false;
  return organization.ownerId === uid
    || stringArray(organization.adminIds).includes(uid)
    || stringArray(organization.moderatorIds).includes(uid);
}

export function firebaseDownloadURL(bucket: string, path: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(path)}`
    + `?alt=media&token=${encodeURIComponent(token)}`;
}

function organizationIdFromContent(content: DocumentData | undefined): string | undefined {
  if (content?.sourceType !== "organization") return undefined;
  const organizationId = content.organizationId;
  return typeof organizationId === "string" && organizationId.trim()
    ? organizationId.trim()
    : undefined;
}

function assertCanManageOrganizationContent(
  user: UserPermissionSnapshot,
  organization: DocumentData | undefined,
  uid: string
): void {
  if (!canManageOrganizationContent(user, organization, uid)) {
    throw new HttpsError(
      "permission-denied",
      "Organization content publishing permissions are required."
    );
  }
}

function isJPEG(data: Buffer): boolean {
  return data.length >= 4
    && data[0] === 0xff
    && data[1] === 0xd8
    && data[data.length - 2] === 0xff
    && data[data.length - 1] === 0xd9;
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

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}
