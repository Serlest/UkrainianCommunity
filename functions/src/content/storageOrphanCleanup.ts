import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {adminStorage, db} from "../firebase/admin";
import {cleanupDeletedContentReferences} from "./contentDeletion";
import {
  type ContentKind,
  contentStoragePrefixes,
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
  return undefined;
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
    candidates += staleFiles.length;

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
        await candidate.file.delete({ignoreNotFound: true});
        deleted += 1;
      }
    }
  } while (pageToken);

  return {scanned, candidates, deleted};
}

async function deletePrefix(prefix: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({prefix, force: true});
}
