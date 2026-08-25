import {onDocumentDeleted} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {adminStorage, db} from "../firebase/admin";

const region = "europe-west3";
const orphanGracePeriodMilliseconds = 24 * 60 * 60 * 1000;

export const cleanupNewsImagesOnDelete = onDocumentDeleted(
  {document: "news/{newsId}", region},
  async (event) => deletePrefix(`news/${event.params.newsId}/`)
);

export const cleanupEventImagesOnDelete = onDocumentDeleted(
  {document: "events/{eventId}", region},
  async (event) => deletePrefix(`events/${event.params.eventId}/`)
);

export const cleanupOrganizationImagesOnDelete = onDocumentDeleted(
  {document: "organizations/{organizationId}", region},
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

export function featuredBannerIdFromObjectName(objectName: string): string | undefined {
  const match = /^featuredBanners\/([^/]+)\/hero(?:-[A-Za-z0-9-]+)?\.jpg$/.exec(objectName);
  return match?.[1];
}

export function isStaleOrphan(createdAtMilliseconds: number, nowMilliseconds: number): boolean {
  return Number.isFinite(createdAtMilliseconds)
    && createdAtMilliseconds <= nowMilliseconds - orphanGracePeriodMilliseconds;
}

async function deletePrefix(prefix: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({prefix, force: true});
}
