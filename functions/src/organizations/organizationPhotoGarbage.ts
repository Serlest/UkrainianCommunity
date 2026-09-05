import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type Transaction} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {adminStorage, db} from "../firebase/admin";
import {storageObjectPathFromDownloadURL} from "../content/contentDeletionPolicy";

export const photoGraceMs = 24 * 60 * 60 * 1000;
export const photoPathKey = (path: string) => createHash("sha256").update(path).digest("hex");
export const photoRetirement = (path: string) => db.doc(`organizationPhotoRetirements/${photoPathKey(path)}`);
export function queuePhotoGarbage(transaction: Transaction, organizationId: string, photoId: string, path: string, now = Timestamp.now()): void {
  if (!managedPhotoPath(path, organizationId)) return;
  transaction.set(db.doc(`organizationPhotoGarbage/${photoPathKey(path)}`), {
    organizationId, photoId, path, notBefore: Timestamp.fromMillis(now.toMillis() + photoGraceMs),
  });
}

export function managedPhotoPath(path: string, organizationId: string): boolean {
  return path.startsWith(`organizations/${organizationId}/`) &&
    (/^organizations\/[^/]+\/photos\/[^/]+\.jpg$/.test(path) || /^organizations\/[^/]+\/photoVersions\/[a-f0-9]{64}\.jpg$/.test(path));
}

function referencesPath(data: Record<string, any> | undefined, path: string): boolean {
  return !!data && [data.imageURL, data.logoURL, data.coverURL].some(value => typeof value === "string" && storageObjectPathFromDownloadURL(value) === path);
}

/** A tombstone serializes cleanup with the legacy metadata creation transaction. */
export async function claimPhotoGarbage(organizationId: string, photoId: string, path: string): Promise<boolean> {
  if (!managedPhotoPath(path, organizationId)) return false;
  return db.runTransaction(async transaction => {
    const [org, photo] = await transaction.getAll(db.doc(`organizations/${organizationId}`), db.doc(`organizations/${organizationId}/photos/${photoId}`));
    if (referencesPath(org.data(), path) || referencesPath(photo.data(), path)) return false;
    transaction.set(photoRetirement(path), {organizationId, photoId});
    return true;
  });
}

export async function cleanupPhotoGarbage(now = Timestamp.now()): Promise<number> {
  const due = await db.collection("organizationPhotoGarbage").where("notBefore", "<=", now).limit(100).get();
  let deleted = 0;
  for (const task of due.docs) {
    const {organizationId, photoId, path} = task.data();
    if (typeof organizationId !== "string" || typeof photoId !== "string" || typeof path !== "string") continue;
    if (!await claimPhotoGarbage(organizationId, photoId, path)) {
      await task.ref.update({notBefore: Timestamp.fromMillis(now.toMillis() + photoGraceMs)});
      continue;
    }
    try {
      const file = adminStorage.bucket().file(path);
      const [metadata] = await file.getMetadata();
      // Delete only the observed generation; a concurrent upload is never erased.
      await file.delete({ifGenerationMatch: metadata.generation});
      await task.ref.delete();
      deleted += 1;
    } catch (error) {
      if (Number((error as {code?: unknown}).code) === 404) { await task.ref.delete(); continue; }
      await task.ref.update({notBefore: Timestamp.fromMillis(now.toMillis() + photoGraceMs)});
      logger.warn("organization_photo_cleanup_retry", {code: Number((error as {code?: unknown}).code) || "unknown"});
    }
  }
  return deleted;
}

export async function expirePhotoOperations(now = Timestamp.now()): Promise<number> {
  const expired = await db.collection("organizationPhotoOperations").where("expiresAt", "<=", now).limit(100).get();
  let count = 0;
  for (const item of expired.docs) {
    const changed = await db.runTransaction(async transaction => {
      const op = await transaction.get(item.ref);
      if (op.get("state") !== "pending" || !(op.get("expiresAt") instanceof Timestamp) || op.get("expiresAt").toMillis() > now.toMillis()) return false;
      queuePhotoGarbage(transaction, op.get("organizationId"), op.get("photoId"), op.get("path"), now);
      transaction.update(item.ref, {state: "expired", expiresAt: FieldValue.delete(), receiptExpiresAt: Timestamp.fromMillis(now.toMillis() + 30 * photoGraceMs)});
      return true;
    });
    if (changed) count += 1;
  }
  const receipts = await db.collection("organizationPhotoOperations").where("receiptExpiresAt", "<=", now).limit(100).get();
  for (const receipt of receipts.docs) await receipt.ref.delete();
  return count;
}

/** Bounded, resumable scan also covers abandoned uploads made by released clients. */
export async function scanLegacyPhotoOrphans(now = Timestamp.now()): Promise<number> {
  const cursor = db.doc("serverJobs/organizationPhotoOrphans");
  const cursorSnapshot = await cursor.get();
  const [files, next] = await adminStorage.bucket().getFiles({prefix: "organizations/", maxResults: 250, autoPaginate: false,
    pageToken: cursorSnapshot.get("pageToken") || undefined});
  let queued = 0;
  for (const file of files) {
    const match = /^organizations\/([^/]+)\/photos\/([^/]+)\.jpg$/.exec(file.name);
    const created = Date.parse(file.metadata.timeCreated ?? "");
    if (!match || !Number.isFinite(created) || created > now.toMillis() - 7 * photoGraceMs) continue;
    if (!await claimPhotoGarbage(match[1], match[2], file.name)) continue;
    await db.runTransaction(async transaction => { queuePhotoGarbage(transaction, match[1], match[2], file.name, now); });
    queued += 1;
  }
  await cursor.set({pageToken: next?.pageToken ?? null, updatedAt: now});
  return queued;
}

export const cleanupOrganizationPhotoLifecycle = onSchedule({schedule: "every 60 minutes", region: "europe-west3", timeoutSeconds: 540, memory: "512MiB"}, async () => {
  const configuration = await db.doc("serverConfiguration/organizationAccess").get();
  // Publishing a compatible server package must not start deleting historical
  // uploads. The two cleanup scopes have independent, explicit rollout gates.
  if (configuration.get("photoCleanupEnabled") !== true) return;
  const expired = await expirePhotoOperations();
  const deleted = await cleanupPhotoGarbage();
  const queued = configuration.get("legacyPhotoSweepEnabled") === true ? await scanLegacyPhotoOrphans() : 0;
  logger.info("organization_photo_cleanup", {expired, deleted, queued});
});
