import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {adminStorage, db} from "../firebase/admin";
import {cleanupDeletedContentReferences} from "./contentDeletion";
import {
  type ContentKind,
  contentStoragePrefixes,
  firebaseStorageDownloadURL,
} from "./contentDeletionPolicy";

const region = "europe-west3";
const orphanGracePeriodMilliseconds = 24 * 60 * 60 * 1000;

export const cleanupNewsImagesOnDelete = onDocumentDeleted(
  {document: "news/{newsId}", region, retry: true},
  async (event) => cleanupDeletedContentLifecycle(
    "news",
    event.params.newsId,
    event.data?.data()
  )
);

export const cleanupEventImagesOnDelete = onDocumentDeleted(
  {document: "events/{eventId}", region, retry: true},
  async (event) => cleanupDeletedContentLifecycle(
    "events",
    event.params.eventId,
    event.data?.data()
  )
);

export const cleanupOrganizationImagesOnDelete = onDocumentDeleted(
  {document: "organizations/{organizationId}", region, retry: true},
  async (event) => deletePrefix(`organizations/${event.params.organizationId}/`)
);

export const cleanupStaleFeaturedBannerOrphans = onSchedule(
  {
    schedule: "every day 04:17",
    timeZone: "Europe/Vienna",
    region,
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const bucket = adminStorage.bucket();
    let pageToken: string | undefined;
    let scanned = 0;
    let deleted = 0;

    do {
      const [files, nextQuery] = await bucket.getFiles({
        prefix: "featuredBanners/",
        maxResults: 500,
        autoPaginate: false,
        pageToken,
      });
      pageToken = nextQuery?.pageToken;
      scanned += files.length;

      const bannerIds = Array.from(new Set(files
        .map((file) => featuredBannerIdFromObjectName(file.name))
        .filter((value): value is string => Boolean(value))));
      const existingIds = new Set<string>();
      for (let index = 0; index < bannerIds.length; index += 30) {
        const references = bannerIds.slice(index, index + 30)
          .map((bannerId) => db.collection("featuredBanners").doc(bannerId));
        if (references.length === 0) continue;
        const snapshots = await db.getAll(...references);
        snapshots.filter((snapshot) => snapshot.exists)
          .forEach((snapshot) => existingIds.add(snapshot.id));
      }

      const now = Date.now();
      for (const file of files) {
        const bannerId = featuredBannerIdFromObjectName(file.name);
        const createdAt = Date.parse(file.metadata.timeCreated ?? "");
        if (!bannerId || existingIds.has(bannerId) || !isStaleOrphan(createdAt, now)) {
          continue;
        }
        await file.delete({ignoreNotFound: true});
        deleted += 1;
      }
    } while (pageToken);

    console.info("Featured banner orphan cleanup completed.", {scanned, deleted});
  }
);

export const cleanupStaleContentMediaOrphans = onSchedule(
  {
    schedule: "every day 04:27",
    timeZone: "Europe/Vienna",
    region,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    let scanned = 0;
    let candidates = 0;
    let deleted = 0;
    for (const prefix of ["news/", "events/", "organizations/"]) {
      const result = await cleanupOrphanContentPrefix(prefix);
      scanned += result.scanned;
      candidates += result.candidates;
      deleted += result.deleted;
    }
    console.info("Content media orphan cleanup completed.", {
      scanned,
      candidates,
      deleted,
      gracePeriodHours: orphanGracePeriodMilliseconds / (60 * 60 * 1000),
    });
  }
);

export function featuredBannerIdFromObjectName(objectName: string): string | undefined {
  const match = /^featuredBanners\/([^/]+)\/hero(?:-[A-Za-z0-9-]+)?\.jpg$/.exec(objectName);
  return match?.[1];
}

export function isStaleOrphan(createdAtMilliseconds: number, nowMilliseconds: number): boolean {
  return Number.isFinite(createdAtMilliseconds)
    && createdAtMilliseconds <= nowMilliseconds - orphanGracePeriodMilliseconds;
}

export interface OrphanContentObjectIdentity {
  kind: ContentKind;
  contentId: string;
}

export interface OrphanOrganizationLogoIdentity {
  organizationId: string;
}

export function orphanContentObjectIdentity(
  objectName: string
): OrphanContentObjectIdentity | undefined {
  const canonical = /^(news|events)\/([^/]+)\/.+$/.exec(objectName);
  if (canonical) {
    return {
      kind: canonical[1] as ContentKind,
      contentId: canonical[2],
    };
  }

  const legacy = /^organizations\/[^/]+\/draftUploads\/(news|events)\/(.+)_cover\.jpg$/
    .exec(objectName);
  if (legacy) {
    return {
      kind: legacy[1] as ContentKind,
      contentId: legacy[2],
    };
  }

  const originalEditor = /^organizations\/[^/]+\/(news|events)\/([^/]+)\/[^/]+\.png$/
    .exec(objectName);
  if (originalEditor) {
    return {
      kind: originalEditor[1] as ContentKind,
      contentId: originalEditor[2],
    };
  }
  return undefined;
}

export function orphanOrganizationLogoIdentity(
  objectName: string
): OrphanOrganizationLogoIdentity | undefined {
  const match = /^organizations\/([^/]+)\/logo\.jpg$/.exec(objectName);
  return match ? {organizationId: match[1]} : undefined;
}

export function firebaseDownloadURLsForStorageObject(
  bucketName: string,
  objectPath: string,
  customMetadata: unknown
): string[] {
  const metadata = customMetadata && typeof customMetadata === "object" &&
      !Array.isArray(customMetadata)
    ? customMetadata as Record<string, unknown>
    : undefined;
  const value = metadata?.firebaseStorageDownloadTokens;
  if (typeof value !== "string") return [];
  return Array.from(new Set(value.split(",")
    .map((token) => token.trim())
    .filter((token) => token.length > 0)))
    .map((token) => firebaseStorageDownloadURL(bucketName, objectPath, token));
}

async function cleanupDeletedContentLifecycle(
  kind: ContentKind,
  contentId: string,
  data: Record<string, unknown> | undefined
): Promise<void> {
  await cleanupDeletedContentReferences(kind, contentId);
  const organizationId = typeof data?.organizationId === "string"
    ? data.organizationId
    : undefined;
  for (const prefix of contentStoragePrefixes(kind, contentId, organizationId)) {
    await deletePrefix(prefix);
  }
}

async function cleanupOrphanContentPrefix(prefix: string): Promise<{
  scanned: number;
  candidates: number;
  deleted: number;
}> {
  const bucket = adminStorage.bucket();
  let pageToken: string | undefined;
  let scanned = 0;
  let candidates = 0;
  let deleted = 0;
  do {
    const [files, nextQuery] = await bucket.getFiles({
      prefix,
      maxResults: 500,
      autoPaginate: false,
      pageToken,
    });
    pageToken = nextQuery?.pageToken;
    scanned += files.length;
    const now = Date.now();
    const staleFiles = files.flatMap((file) => {
      const identity = orphanContentObjectIdentity(file.name);
      const createdAt = Date.parse(file.metadata.timeCreated ?? "");
      return identity && isStaleOrphan(createdAt, now)
        ? [{file, identity}]
        : [];
    });
    const staleOrganizationLogos = files.flatMap((file) => {
      const identity = orphanOrganizationLogoIdentity(file.name);
      const createdAt = Date.parse(file.metadata.timeCreated ?? "");
      return identity && isStaleOrphan(createdAt, now)
        ? [{file, identity}]
        : [];
    });
    candidates += staleFiles.length + staleOrganizationLogos.length;

    const grouped = new Map<string, typeof staleFiles>();
    for (const candidate of staleFiles) {
      const key = `${candidate.identity.kind}/${candidate.identity.contentId}`;
      grouped.set(key, [...(grouped.get(key) ?? []), candidate]);
    }
    for (const group of grouped.values()) {
      const identity = group[0].identity;
      // Re-read immediately before the destructive action. An upload may have
      // happened long before a delayed Firestore commit, so age alone is not proof.
      const content = await db.collection(identity.kind).doc(identity.contentId).get();
      if (content.exists) {
        continue;
      }
      for (const candidate of group) {
        if (await deleteListedGeneration(candidate.file.name, candidate.file.metadata.generation)) {
          deleted += 1;
        }
      }
    }

    for (const candidate of staleOrganizationLogos) {
      const organizationReference = db.collection("organizations")
        .doc(candidate.identity.organizationId);
      if ((await organizationReference.get()).exists ||
          await organizationLogoHasLiveReference(
            candidate.file.name,
            candidate.identity.organizationId,
            candidate.file.metadata.generation
          )) {
        continue;
      }

      // Re-read directly before touching Storage. This intentionally retains
      // the object if a new organization or content reference appeared while
      // the scheduled scan was running.
      if ((await organizationReference.get()).exists ||
          await organizationLogoHasLiveReference(
            candidate.file.name,
            candidate.identity.organizationId,
            candidate.file.metadata.generation
          )) {
        continue;
      }
      if (await deleteListedGeneration(
        candidate.file.name,
        candidate.file.metadata.generation
      )) {
        deleted += 1;
      }
    }
  } while (pageToken);

  return {scanned, candidates, deleted};
}

async function organizationLogoHasLiveReference(
  objectPath: string,
  organizationId: string,
  generationValue: string | number | undefined
): Promise<boolean> {
  const [newsByOrganization, eventsByOrganization] = await Promise.all([
    db.collection("news").where("organizationId", "==", organizationId).limit(1).get(),
    db.collection("events").where("organizationId", "==", organizationId).limit(1).get(),
  ]);
  if (!newsByOrganization.empty || !eventsByOrganization.empty) return true;

  const generation = storageGeneration(generationValue);
  if (generation === undefined) {
    console.error("Preserved orphan Storage candidate with an invalid generation.", {
      objectPath,
    });
    return true;
  }

  let metadata;
  try {
    [metadata] = await adminStorage.bucket().file(objectPath, {generation})
      .getMetadata();
  } catch (error) {
    // The listed generation may have been deleted or replaced while the scan
    // was running. There is then nothing from this scan that may be deleted.
    if (isNotFound(error)) return true;
    throw error;
  }
  const downloadURLs = firebaseDownloadURLsForStorageObject(
    adminStorage.bucket().name,
    objectPath,
    metadata.metadata
  );
  // A Firebase object without a verifiable token may still be referenced by a
  // URL shape that cannot be queried exactly. Preserve it for manual review.
  if (downloadURLs.length === 0) return true;

  for (const downloadURL of downloadURLs) {
    const snapshots = await Promise.all([
      db.collection("news").where("imageURL", "==", downloadURL).limit(1).get(),
      db.collection("news").where("organizationImageURL", "==", downloadURL).limit(1).get(),
      db.collection("events").where("imageURL", "==", downloadURL).limit(1).get(),
      db.collection("events").where("organizationImageURL", "==", downloadURL).limit(1).get(),
      db.collection("organizations").where("imageURL", "==", downloadURL).limit(1).get(),
      db.collection("organizations").where("logoURL", "==", downloadURL).limit(1).get(),
      db.collection("organizations").where("coverURL", "==", downloadURL).limit(1).get(),
      db.collection("featuredBanners").where("imageURL", "==", downloadURL).limit(1).get(),
      db.collection("users").where("avatarURL", "==", downloadURL).limit(1).get(),
    ]);
    if (snapshots.some((snapshot) => !snapshot.empty)) return true;
  }
  return false;
}

async function deleteListedGeneration(
  objectPath: string,
  generationValue: string | number | undefined
): Promise<boolean> {
  const generation = storageGeneration(generationValue);
  if (generation === undefined) {
    console.error("Skipped orphan Storage deletion with an invalid generation.", {
      objectPath,
    });
    return false;
  }
  await adminStorage.bucket().file(objectPath, {generation})
    .delete({ignoreNotFound: true});
  return true;
}

function storageGeneration(value: string | number | undefined): number | undefined {
  const generation = Number(value);
  return Number.isSafeInteger(generation) && generation > 0
    ? generation
    : undefined;
}

function isNotFound(error: unknown): boolean {
  return Boolean(error && typeof error === "object" && "code" in error &&
    (error as {code?: number}).code === 404);
}

async function deletePrefix(prefix: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({prefix, force: true});
}
