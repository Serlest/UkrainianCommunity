import {createHash, randomUUID} from "node:crypto";
import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {onCall} from "firebase-functions/v2/https";
import {adminStorage, db} from "../firebase/admin";
import {assertActiveUser, assertPrivilegedMFA, requireVerifiedActiveUser} from "../auth/context";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {canManageOrganizationPhotos, maximumOrganizationPhotoCount} from "./organizationPhotoMutations";
import {accessPolicyConfiguration} from "./organizationAccess";
import {commandEnabled} from "./organizationAccessPolicy";
import {accessFailure, withAccessDiagnostics} from "./organizationAccessDiagnostics";
import {firebaseStorageDownloadURL, storageObjectPathFromDownloadURL} from "../content/contentDeletionPolicy";
import {photoGraceMs, queuePhotoGarbage} from "./organizationPhotoGarbage";

export function parsePhotoSave(data: any) {
  const validID = (x: unknown): x is string => typeof x === "string" && /^[A-Za-z0-9_-]{1,200}$/.test(x);
  if (!data || !validID(data.organizationId) || !validID(data.photoId) || !validID(data.operationId)
    || (data.expectedImageURL !== null && (typeof data.expectedImageURL !== "string" || data.expectedImageURL.length > 4096))
    || typeof data.imageBase64 !== "string" || data.imageBase64.length > 4_000_000
    || !/^[A-Za-z0-9+/]+={0,2}$/.test(data.imageBase64)
    || (data.caption != null && (typeof data.caption !== "string" || data.caption.length > 500))) {
    throw accessFailure("invalid-argument", "invalid_request", "Invalid photo request.");
  }
  const bytes = Buffer.from(data.imageBase64, "base64");
  if (bytes.length > 3_000_000 || bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8
    || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9 || bytes.toString("base64") !== data.imageBase64) {
    throw accessFailure("invalid-argument", "invalid_request", "A JPEG image up to 3 MB is required.");
  }
  return {organizationId: data.organizationId as string, photoId: data.photoId as string, operationId: data.operationId as string,
    expectedImageURL: data.expectedImageURL as string | null, caption: (data.caption?.trim() || null) as string | null,
    bytes, digest: createHash("sha256").update(bytes).digest("hex")};
}

export const saveOrganizationPhoto = onCall({region: "europe-west3", enforceAppCheck: true, memory: "512MiB", timeoutSeconds: 120, maxInstances: 10, concurrency: 10}, request =>
  withAccessDiagnostics(request, "saveOrganizationPhoto", async () => {
    // This command replaces both Storage upload and metadata commit. Preserve
    // the existing Storage App Check and MFA gates without changing v1 APIs.
    const auth = await requireVerifiedActiveUser(request);
    if (request.data?.principalId !== auth.uid) throw accessFailure("permission-denied", "account_changed", "The account changed before saving.");
    const input = parsePhotoSave(request.data);
    const operationID = createHash("sha256").update(`${auth.uid}\0${input.operationId}`).digest("hex");
    const operation = db.doc(`organizationPhotoOperations/${operationID}`);
    const organization = db.doc(`organizations/${input.organizationId}`);
    const photo = organization.collection("photos").doc(input.photoId);
    const path = `organizations/${input.organizationId}/photoVersions/${operationID}.jpg`;
    const fingerprint = createHash("sha256").update(JSON.stringify([input.organizationId, input.photoId, input.expectedImageURL, input.caption, input.digest])).digest("hex");

    async function validateActor(transaction: FirebaseFirestore.Transaction) {
      const [profile, org, config] = await transaction.getAll(db.doc(`users/${auth.uid}`), organization, db.doc(accessPolicyConfiguration));
      if (!profile.exists) throw accessFailure("permission-denied", "account_inactive", "User profile no longer exists.");
      const actor = userPermissionSnapshotFromData(auth.uid, profile.data());
      assertActiveUser(actor);
      assertPrivilegedMFA(auth.token, actor);
      if (!org.exists) throw accessFailure("not-found", "object_missing", "Organization does not exist.");
      if (!canManageOrganizationPhotos(actor, org.data(), auth.uid)) throw accessFailure("permission-denied", "role_missing", "Organization photo management is not allowed.");
      return config.data();
    }

    const prepared = await db.runTransaction(async transaction => {
      const config = await validateActor(transaction);
      const [existing, currentPhoto] = await transaction.getAll(operation, photo);
      if (existing.exists) {
        if (existing.get("fingerprint") !== fingerprint) throw accessFailure("already-exists", "invalid_request", "Operation ID was reused.");
        if (existing.get("state") === "committed") return {committed: true, token: existing.get("token") as string};
        if (existing.get("state") !== "pending" || existing.get("expiresAt").toMillis() <= Date.now()) throw accessFailure("failed-precondition", "operation_expired", "This upload has expired. Select the photo again.");
      }
      if (!commandEnabled(config, auth.uid, "saveOrganizationPhoto", "managePhotos")) throw accessFailure("failed-precondition", "route_disabled", "The photo command is not enabled.");
      assertPhotoVersion(currentPhoto.data(), input.expectedImageURL);
      const count = await transaction.get(organization.collection("photos").limit(maximumOrganizationPhotoCount + 1));
      if (!currentPhoto.exists && count.size >= maximumOrganizationPhotoCount) throw accessFailure("resource-exhausted", "limit_reached", "The photo limit has been reached.");
      if (existing.exists) return {committed: false, token: existing.get("token") as string};
      const token = randomUUID();
      const now = Timestamp.now();
      transaction.create(operation, {organizationId: organization.id, photoId: photo.id, actorUserId: auth.uid, path, fingerprint,
        token, state: "pending", createdAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + photoGraceMs)});
      return {committed: false, token};
    });
    if (prepared.committed) return {photoId: photo.id, organizationId: organization.id, didChange: false};

    const file = adminStorage.bucket().file(path);
    try {
      await file.save(input.bytes, {resumable: false, preconditionOpts: {ifGenerationMatch: 0}, metadata: {
        contentType: "image/jpeg", cacheControl: "public,max-age=86400", metadata: {firebaseStorageDownloadTokens: prepared.token, contentDigest: input.digest},
      }});
    } catch (error) {
      if (Number((error as {code?: unknown}).code) !== 412) throw error;
      const [metadata] = await file.getMetadata();
      if (metadata.metadata?.contentDigest !== input.digest) throw accessFailure("already-exists", "invalid_request", "The upload object belongs to another operation.");
    }
    const imageURL = firebaseStorageDownloadURL(adminStorage.bucket().name, path, prepared.token);
    return db.runTransaction(async transaction => {
      const config = await validateActor(transaction);
      const [pending, currentPhoto] = await transaction.getAll(operation, photo);
      if (pending.get("state") === "committed") return {photoId: photo.id, organizationId: organization.id, didChange: false};
      if (pending.get("state") !== "pending" || pending.get("expiresAt").toMillis() <= Date.now()) throw accessFailure("failed-precondition", "operation_expired", "This upload has expired.");
      if (!commandEnabled(config, auth.uid, "saveOrganizationPhoto", "managePhotos")) throw accessFailure("failed-precondition", "route_disabled", "The photo command is not enabled.");
      assertPhotoVersion(currentPhoto.data(), input.expectedImageURL);
      const allPhotos = await transaction.get(organization.collection("photos").limit(maximumOrganizationPhotoCount + 1));
      if (!currentPhoto.exists && allPhotos.size >= maximumOrganizationPhotoCount) throw accessFailure("resource-exhausted", "limit_reached", "The photo limit has been reached.");
      const now = Timestamp.now();
      const previousPath = typeof currentPhoto.get("imageURL") === "string" ? storageObjectPathFromDownloadURL(currentPhoto.get("imageURL")) : undefined;
      transaction.set(photo, {id: photo.id, organizationId: organization.id, imageURL, caption: input.caption, uploadedBy: auth.uid,
        createdAt: currentPhoto.get("createdAt") ?? now, updatedAt: currentPhoto.exists ? now : null});
      transaction.update(organization, {photoCount: allPhotos.size + (currentPhoto.exists ? 0 : 1)});
      transaction.update(operation, {state: "committed", expiresAt: FieldValue.delete(), receiptExpiresAt: Timestamp.fromMillis(now.toMillis() + 30 * photoGraceMs)});
      if (previousPath && previousPath !== path) queuePhotoGarbage(transaction, organization.id, photo.id, previousPath, now);
      return {photoId: photo.id, organizationId: organization.id, didChange: true};
    });
  }));

function assertPhotoVersion(current: DocumentData | undefined, expectedImageURL: string | null): void {
  if (expectedImageURL === null ? !!current : current?.imageURL !== expectedImageURL) {
    throw accessFailure("aborted", "object_changed", "The photo changed. Reload before replacing it.");
  }
}
