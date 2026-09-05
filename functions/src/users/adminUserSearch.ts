import {type Readable} from "node:stream";
import {FieldPath, type DocumentData, type Firestore, type QueryDocumentSnapshot} from "firebase-admin/firestore";

export const adminSearchIndexField = "adminSearchGramsV1";
export const adminSearchOverflow = "!overflow-v1";
export const adminSearchFields = [
  "displayName", "fullName", "email", "telegramUsername", "city", "selectedFederalState",
] as const;
const maximumGrams = 4_000;

export function normalizeAdminSearch(value: string): string {
  return value.toLocaleLowerCase("uk-UA").normalize("NFKD")
    .replace(/\p{M}/gu, "").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
}

/** Derived only from source fields. Never trust a client-supplied index. */
export function buildAdminSearchGrams(userId: string, data: DocumentData): string[] {
  const text = normalizeAdminSearch([userId, ...adminSearchFields.map(field => data[field])]
    .filter((value): value is string => typeof value === "string").join(" "));
  const grams = new Set<string>();
  for (const token of text.split(/\s+/)) {
    const points = Array.from(token);
    for (let index = 0; index < points.length; index++) {
      for (let size = 1; size <= 3 && index + size <= points.length; size++) {
        grams.add(points.slice(index, index + size).join(""));
        // An oversized profile stays in EVERY candidate set, never silently truncated.
        if (grams.size > maximumGrams) return [adminSearchOverflow];
      }
    }
  }
  return [...grams].sort();
}

export function adminSearchAnchor(normalizedQuery: string): string | null {
  const tokens = normalizedQuery.split(/\s+/).filter(Boolean).map(token => Array.from(token));
  tokens.sort((left, right) => right.length - left.length);
  return tokens[0]?.slice(0, 3).join("") || null;
}

/** No environment/client flag can activate this unfinished rollout.
 * Current call sites use the default incomplete gate and ALWAYS read all users.
 * Supplying ready belongs to a future coordinated atomic-writer/Rules package.
 */
export type AdminSearchReadiness = "incomplete" | "ready";

export async function* adminSearchDocuments(
  firestore: Firestore,
  normalizedQuery: string,
  fields: readonly string[],
  readiness: AdminSearchReadiness = "incomplete"
): AsyncGenerator<QueryDocumentSnapshot> {
  const anchor = adminSearchAnchor(normalizedQuery);
  const users = firestore.collection("users");
  const candidates = readiness === "ready" && anchor
    ? users.where(adminSearchIndexField, "array-contains-any", [anchor, adminSearchOverflow])
    : users;
  // One streaming query preserves full coverage; no first-page cut-off, offsets,
  // cached identities, or per-page snapshots. Only selected fields cross the wire.
  const stream = candidates.orderBy(FieldPath.documentId()).select(...fields).stream() as Readable;
  try {
    for await (const document of stream) yield document as QueryDocumentSnapshot;
  } finally {
    stream.destroy();
  }
}

/** Keep only the response-sized top set, but count and inspect the ENTIRE stream. */
export async function collectAdminSearch<T>(
  source: AsyncIterable<T>,
  matches: (value: T) => boolean,
  limit: number,
  compare?: (left: T, right: T) => number
): Promise<{items: T[]; totalMatches: number}> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new RangeError("Invalid search limit");
  const items: T[] = [];
  let totalMatches = 0;
  for await (const value of source) {
    if (!matches(value)) continue;
    totalMatches++;
    if (!compare) {
      if (items.length < limit) items.push(value);
      continue;
    }
    // Stable insertion preserves Firestore document-ID order for timestamp ties.
    const position = items.findIndex(item => compare(value, item) < 0);
    if (position >= 0) items.splice(position, 0, value);
    else if (items.length < limit) items.push(value);
    if (items.length > limit) items.pop();
  }
  // Stream errors propagate: a partial count must never be returned as complete.
  return {items, totalMatches};
}
