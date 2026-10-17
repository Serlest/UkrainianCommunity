import {FieldPath, FieldValue, Timestamp, type Transaction} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {directoryMaterials, planDirectoryAdditions, type RecentMaterial} from "./directoryRecentModel";

export const directoryRecentCollection = "directoryRecentAdditions";
interface Cursor {seconds: number; nanoseconds: number; id: string;}

/** Invoked inside the same authorized, revision-checked category publication transaction. */
export async function recordDirectoryAdditions(transaction: Transaction, categoryID: string,
  previousPayload: string | undefined, nextPayload: string, revision: number): Promise<void> {
  const stateRef = db.collection("directoryCategories").doc(categoryID).collection("recentState").doc("v1");
  const state = await transaction.get(stateRef);
  const plan = planDirectoryAdditions(categoryID, previousPayload, nextPayload, state.data()?.knownIDs);
  transaction.set(stateRef, {schemaVersion: 1, knownIDs: plan.knownIDs});
  for (const material of plan.additions) {
    const {visible: _visible, ...event} = material;
    transaction.create(db.collection(directoryRecentCollection).doc(material.id), {
      ...event, schemaVersion: 1, revision, publishedAt: FieldValue.serverTimestamp(),
    });
  }
}

export function recentRequest(value: unknown): {limit: number; cursor: Cursor | null} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", "Expected a recent additions request.");
  }
  const input = value as Record<string, unknown>;
  const limit = input.limit ?? 20;
  if (Object.keys(input).some((k) => !["limit", "cursor"].includes(k)) ||
      !Number.isInteger(limit) || (limit as number) < 1 || (limit as number) > 50) {
    throw new HttpsError("invalid-argument", "Invalid recent additions limit.");
  }
  if (input.cursor == null) return {limit: limit as number, cursor: null};
  const cursor = input.cursor as Cursor;
  if (typeof cursor !== "object" || Array.isArray(cursor) ||
      Object.keys(cursor).sort().join(",") !== "id,nanoseconds,seconds" ||
      !Number.isInteger(cursor.seconds) || cursor.seconds < 0 || cursor.seconds > 253402300799 ||
      !Number.isInteger(cursor.nanoseconds) || cursor.nanoseconds < 0 || cursor.nanoseconds >= 1e9 ||
      typeof cursor.id !== "string" || !/^[a-f0-9]{64}$/.test(cursor.id)) {
    throw new HttpsError("invalid-argument", "Invalid recent additions cursor.");
  }
  return {limit: limit as number, cursor};
}

/** Public projection uses current content, never a stale/hidden title from the private journal. */
export const getDirectoryRecentAdditions = onCall({region: "europe-west3", maxInstances: 10,
  invoker: "public", enforceAppCheck: false, timeoutSeconds: 30}, async (request) => {
  const {limit, cursor} = recentRequest(request.data);
  const base = db.collection(directoryRecentCollection)
    .orderBy("publishedAt", "desc").orderBy(FieldPath.documentId(), "desc");
  let next = cursor;
  let scanned = 0;
  const items: Array<Omit<RecentMaterial, "visible"> & {revision: number; publishedAt: string}> = [];
  const categories = new Map<string, Map<string, RecentMaterial>>();
  while (scanned < 200 && items.length < limit) {
    const query = next ? base.startAfter(new Timestamp(next.seconds, next.nanoseconds), next.id) : base;
    const take = Math.min(50, 200 - scanned);
    const batch = await query.limit(take).get();
    if (batch.empty) break;
    for (const doc of batch.docs) {
      const event = doc.data();
      const time = event.publishedAt as Timestamp;
      if (!(time instanceof Timestamp)) throw new HttpsError("data-loss", "Invalid publication timestamp.");
      next = {seconds: time.seconds, nanoseconds: time.nanoseconds, id: doc.id};
      scanned++;
      const categoryID = event.categoryID;
      if (typeof categoryID !== "string" || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(categoryID)) continue;
      if (!categories.has(categoryID)) {
        const snapshot = await db.collection("directoryCategories").doc(categoryID).get();
        const current = snapshot.data();
        let materials: RecentMaterial[] = [];
        if (current && current.isDeleted !== true && typeof current.payload === "string") {
          try { materials = directoryMaterials(current.payload); } catch { /* Fail closed on malformed snapshots. */ }
        }
        categories.set(categoryID, new Map(materials.filter((m) => m.visible).map((m) => [m.id, m])));
      }
      const current = categories.get(categoryID)?.get(doc.id);
      if (current) {
        const {visible: _visible, ...material} = current;
        items.push({...material, revision: event.revision, publishedAt: time.toDate().toISOString()});
      }
      if (items.length === limit) break;
    }
    if (batch.size < take && items.length < limit) break;
  }
  const hasMore = next !== null && !(await base
    .startAfter(new Timestamp(next.seconds, next.nanoseconds), next.id).limit(1).get()).empty;
  return {items, nextCursor: hasMore ? next : null, hasMore};
});
