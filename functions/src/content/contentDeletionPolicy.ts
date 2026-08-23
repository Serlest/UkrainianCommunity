export type ContentKind = "news" | "events";

export interface ContentReferencePolicy {
  source: "collection" | "collectionGroup";
  collectionId: string;
  field: string;
}

const contentReferencePolicies: Record<ContentKind, readonly ContentReferencePolicy[]> = {
  news: [
    {source: "collection", collectionId: "likes", field: "newsId"},
    {source: "collectionGroup", collectionId: "newsBookmarks", field: "newsId"},
    {source: "collectionGroup", collectionId: "newsViews", field: "newsId"},
  ],
  events: [
    {source: "collection", collectionId: "likes", field: "eventId"},
    {source: "collection", collectionId: "registrations", field: "eventId"},
    {source: "collectionGroup", collectionId: "eventBookmarks", field: "eventId"},
    {source: "collectionGroup", collectionId: "eventViews", field: "eventId"},
  ],
};

export function normalizedResourceId(value: string, field: string): string {
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.includes("/")) {
    throw new Error(`${field} must be a non-empty Firestore document ID.`);
  }
  return normalized;
}

export function contentReferencePoliciesFor(
  kind: ContentKind
): readonly ContentReferencePolicy[] {
  return contentReferencePolicies[kind];
}

export function canonicalContentStoragePath(kind: ContentKind, contentId: string): string {
  const normalizedId = normalizedResourceId(contentId, "contentId");
  return `${kind}/${normalizedId}/cover.jpg`;
}

export function canonicalContentStoragePrefix(kind: ContentKind, contentId: string): string {
  const normalizedId = normalizedResourceId(contentId, "contentId");
  return `${kind}/${normalizedId}/`;
}

export function legacyDraftStoragePath(
  kind: ContentKind,
  organizationId: string,
  contentId: string
): string {
  const normalizedOrganizationId = normalizedResourceId(organizationId, "organizationId");
  const normalizedContentId = normalizedResourceId(contentId, "contentId");
  const folder = kind === "news" ? "news" : "events";
  return `organizations/${normalizedOrganizationId}/draftUploads/${folder}/${normalizedContentId}_cover.jpg`;
}

export function contentStoragePrefixes(
  kind: ContentKind,
  contentId: string,
  organizationId?: string
): string[] {
  const prefixes = [canonicalContentStoragePrefix(kind, contentId)];
  if (organizationId?.trim()) {
    prefixes.push(legacyDraftStoragePath(kind, organizationId, contentId));
  }
  return prefixes;
}

export function organizationStoragePrefix(organizationId: string): string {
  return `organizations/${normalizedResourceId(organizationId, "organizationId")}/`;
}

export function storageObjectPathFromDownloadURL(value: string): string | undefined {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return undefined;
  }

  const host = url.hostname.toLowerCase();
  if (host === "firebasestorage.googleapis.com") {
    const marker = "/o/";
    const markerIndex = url.pathname.indexOf(marker);
    if (markerIndex < 0) {
      return undefined;
    }
    return decodedPath(url.pathname.slice(markerIndex + marker.length));
  }

  if (host === "storage.googleapis.com") {
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts.length < 2) {
      return undefined;
    }
    return decodedPath(parts.slice(1).join("/"));
  }

  return undefined;
}

export function firebaseStorageDownloadURL(
  bucketName: string,
  objectPath: string,
  downloadToken: string
): string {
  const bucket = bucketName.trim();
  const path = objectPath.trim();
  const token = downloadToken.trim();
  if (!bucket || !path || !token) {
    throw new Error("Storage download URL components must not be empty.");
  }

  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket)}`
    + `/o/${encodeURIComponent(path)}?alt=media&token=${encodeURIComponent(token)}`;
}

export function eventBlocksOrganizationDeletion(data: Record<string, unknown>): boolean {
  return data.cancellationState !== "cancelled" && data.moderationStatus !== "archived";
}

function decodedPath(value: string): string | undefined {
  try {
    const decoded = decodeURIComponent(value).replace(/^\/+/, "");
    return decoded.length > 0 ? decoded : undefined;
  } catch {
    return undefined;
  }
}
