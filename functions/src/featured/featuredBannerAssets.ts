import {FieldPath, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {adminStorage, db} from "../firebase/admin";

export function featuredBannerAssetPath(value: unknown, bucket: string): string | undefined {
  if (typeof value !== "string") return undefined;
  try {
    const url = new URL(value);
    let path: string | undefined;
    if (url.hostname === "firebasestorage.googleapis.com") {
      const match = /^\/v0\/b\/([^/]+)\/o\/(.+)$/.exec(url.pathname);
      if (match && decodeURIComponent(match[1]) === bucket) path = decodeURIComponent(match[2]);
    } else if (url.hostname === "storage.googleapis.com" && url.pathname.startsWith(`/${bucket}/`)) {
      path = decodeURIComponent(url.pathname.slice(bucket.length + 2));
    }
    return path && /^featuredBanners\/[^/]+\/[^/]+$/.test(path) && !path.split("/").includes("..") ? path : undefined;
  } catch { return undefined; }
}

/** Bounded pages, only image URLs. A copy may refer to another banner's folder. */
export async function referencedFeaturedBannerAssets(): Promise<Set<string>> {
  const result = new Set<string>(), bucket = adminStorage.bucket().name;
  let cursor: QueryDocumentSnapshot | undefined;
  for (;;) {
    let query = db.collection("featuredBanners").select("imageURL").orderBy(FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    for (const doc of page.docs) {
      const path = featuredBannerAssetPath(doc.get("imageURL"), bucket);
      if (path) result.add(path);
    }
    if (page.size < 200) return result;
    cursor = page.docs.at(-1);
  }
}

export async function deleteUnreferencedBannerAsset(path: string): Promise<void> {
  if ((await referencedFeaturedBannerAssets()).has(path)) return;
  const file = adminStorage.bucket().file(path);
  const [exists] = await file.exists();
  if (!exists) return;
  try {
    const [metadata] = await file.getMetadata();
    await file.delete({ignoreNotFound: true, ifGenerationMatch: Number(metadata.generation)});
  } catch (error) {
    if ((error as {code?: number}).code !== 404) throw error;
  }
}
