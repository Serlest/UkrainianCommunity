import {type Readable} from "node:stream";
import {FieldPath, FieldValue, Timestamp, type DocumentData, type Firestore, type Query} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {canManageFeedback} from "../permissions/userPermissions";
import {adminSearchAnchor, normalizeAdminSearch} from "../users/adminUserSearch";

export const feedbackIndexState = "internalSearchState/feedbackV1";
export const feedbackSourceFields = ["status", "createdAt", "updatedAt", "lastMessageAt", "userId", "userDisplayName", "subject", "message", "lastMessageText", "type"];
export function feedbackBucket(status: unknown): string {
  return status === "answered" || status === "done" ? "answered" : status === "closed" || status === "archived" ? "closed" : "open";
}
export function feedbackSearchText(id: string, data: DocumentData): string {
  return normalizeAdminSearch([id, data.userId, data.userDisplayName, data.subject, data.message, data.lastMessageText, data.type]
    .filter(value => typeof value === "string").join(" "));
}
export function feedbackIndex(id: string, data: DocumentData): DocumentData {
  const grams = new Set<string>();
  for (const token of feedbackSearchText(id, data).split(/\s+/)) {
    const points = Array.from(token);
    for (let i = 0; i < points.length; i++) for (let n = 1; n <= 3 && i + n <= points.length; n++) {
      grams.add(points.slice(i, i + n).join(""));
      if (grams.size > 6000) break;
    }
    if (grams.size > 6000) break;
  }
  return {inboxBucketV1: feedbackBucket(data.status), inboxActivityV1: data.lastMessageAt instanceof Timestamp ? data.lastMessageAt :
    data.updatedAt instanceof Timestamp ? data.updatedAt : data.createdAt instanceof Timestamp ? data.createdAt : Timestamp.fromMillis(0),
  inboxGramsV1: grams.size > 6000 ? ["!overflow"] : [...grams].sort()};
}
export async function reconcileFeedbackIndex(firestore: Firestore, id: string): Promise<boolean> {
  return firestore.runTransaction(async transaction => {
    const ref = firestore.doc(`feedback/${id}`); const current = await transaction.get(ref);
    if (!current.exists) return false;
    const derived = feedbackIndex(id, current.data()!);
    if (Object.entries(derived).every(([key, value]) => JSON.stringify(current.get(key)) === JSON.stringify(value))) return false;
    transaction.update(ref, derived); return true;
  });
}
export const maintainFeedbackInboxIndex = onDocumentWritten({document: "feedback/{feedbackId}", region: "europe-west3", retry: true, maxInstances: 4}, async event => {
  if (!event.data?.after.exists) return;
  const before = event.data.before.data(), after = event.data.after.data()!;
  if (before && feedbackSourceFields.every(key => JSON.stringify(before[key]) === JSON.stringify(after[key])) &&
      Object.entries(feedbackIndex(event.params.feedbackId, after)).every(([key, value]) => JSON.stringify(after[key]) === JSON.stringify(value))) return;
  try { await reconcileFeedbackIndex(db, event.params.feedbackId); }
  catch (error) {
    await db.doc(feedbackIndexState).set({ready: false, failedAt: FieldValue.serverTimestamp()}, {merge: true});
    throw error;
  }
});

type Cursor = {seconds: number; nanoseconds: number; id: string};
function cursorFor(id: string, data: DocumentData): Cursor {
  const date = feedbackIndex(id, data).inboxActivityV1 as Timestamp;
  return {seconds: date.seconds, nanoseconds: date.nanoseconds, id};
}
function compare(a: Cursor, b: Cursor): number {
  return a.seconds - b.seconds || a.nanoseconds - b.nanoseconds || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}
export async function readFeedbackInbox(firestore: Firestore, input: Record<string, unknown>) {
  const filter = input.filter ?? "open";
  if (!["open", "answered", "closed"].includes(String(filter))) throw new HttpsError("invalid-argument", "Invalid filter.");
  if (input.search !== undefined && (typeof input.search !== "string" || input.search.length > 160)) throw new HttpsError("invalid-argument", "Search is too long.");
  const search = normalizeAdminSearch(String(input.search ?? ""));
  const oldest = input.oldest === true; const limit = Math.max(1, Math.min(30, Number(input.limit) || 30));
  let cursor: Cursor | undefined;
  if (input.cursor !== undefined && input.cursor !== null) {
    const value = input.cursor as Cursor;
    if (!Number.isSafeInteger(value.seconds) || !Number.isInteger(value.nanoseconds) || value.nanoseconds < 0 || value.nanoseconds >= 1e9 ||
        typeof value.id !== "string" || !value.id || value.id.includes("/")) throw new HttpsError("invalid-argument", "Invalid cursor.");
    cursor = value;
  }
  const ready = (await firestore.doc(feedbackIndexState).get()).get("ready") === true;
  const collection = firestore.collection("feedback");
  const counts: Record<string, number> = {open: 0, answered: 0, closed: 0};
  let rows: Array<{id: string; cursor: Cursor}> = [];
  if (ready && !search) {
    await Promise.all(Object.keys(counts).map(async key => { counts[key] = (await collection.where("inboxBucketV1", "==", key).count().get()).data().count; }));
    const direction = oldest ? "asc" : "desc";
    let query: Query = collection.where("inboxBucketV1", "==", filter).orderBy("inboxActivityV1", direction).orderBy(FieldPath.documentId(), direction);
    if (cursor) query = query.startAfter(new Timestamp(cursor.seconds, cursor.nanoseconds), cursor.id);
    const page = await query.limit(limit + 1).get();
    rows = page.docs.map(doc => ({id: doc.id, cursor: cursorFor(doc.id, doc.data())}));
  } else {
    const anchor = adminSearchAnchor(search);
    // A private readiness switch prevents incomplete results before backfill. Oversized
    // records participate in every indexed search. Keep only response-sized top results.
    const candidates = ready && anchor ? collection.where("inboxGramsV1", "array-contains-any", [anchor, "!overflow"]) : collection;
    const stream = candidates.orderBy(FieldPath.documentId()).stream() as Readable;
    try {
      for await (const doc of stream) {
        const data = doc.data();
        if (!search.split(/\s+/).every(word => feedbackSearchText(doc.id, data).includes(word))) continue;
        const bucket = feedbackBucket(data.status); counts[bucket]++;
        if (bucket !== filter) continue;
        const key = cursorFor(doc.id, data);
        if (cursor && (oldest ? compare(key, cursor) <= 0 : compare(key, cursor) >= 0)) continue;
        rows.push({id: doc.id, cursor: key});
        rows.sort((a, b) => (oldest ? 1 : -1) * compare(a.cursor, b.cursor));
        if (rows.length > limit + 1) rows.pop();
      }
    } finally { stream.destroy(); }
  }
  const hasMore = rows.length > limit; rows = rows.slice(0, limit);
  return {ids: rows.map(row => row.id), counts, cursor: hasMore ? rows.at(-1)?.cursor : null};
}
export const listFeedbackInbox = onCall({region: "europe-west3", maxInstances: 4, timeoutSeconds: 60, invoker: "public", enforceAppCheck: false}, async request => {
  const actor = await requireVerifiedActiveUser(request);
  if (!canManageFeedback(actor.permissions)) throw new HttpsError("permission-denied", "Feedback management access required.");
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data)) throw new HttpsError("invalid-argument", "Invalid query.");
  if (request.data.principalId !== actor.uid) throw new HttpsError("permission-denied", "Account changed.");
  return readFeedbackInbox(db, request.data);
});
