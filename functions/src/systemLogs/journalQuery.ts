import {createHash, randomUUID} from "node:crypto";
import {FieldPath, FieldValue, Timestamp, type DocumentData, type Firestore, type Query} from "firebase-admin/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {adminSearchAnchor, adminSearchOverflow, buildAdminSearchGrams, normalizeAdminSearch} from "../users/adminUserSearch";

export const journalIndexField = "journalSearchGramsV1";
export const journalIndexState = "internalSearchState/systemLogsV1";
export const journalCursorCollection = "systemLogQueryCursors";
const severities = ["debug", "info", "notice", "warning", "error", "critical"];
const sorts = ["newestFirst", "oldestFirst", "severityHighToLow", "severityLowToHigh", "category"];
const fields = ["summary", "technicalMessage", "errorCode", "moduleName", "screenName", "operationName", "actorDisplayName", "actorUserId", "actorRole", "targetTitle", "targetType", "targetId", "organizationName", "organizationId", "correlationId", "category", "severity", "eventType", "outcome"];
const hash = (s: string) => createHash("sha256").update(s).digest("hex");
export function journalText(id: string, d: DocumentData): string {
  return [id, ...fields.map(f => d[f]), ...Object.values(d.metadata ?? {})].filter(v => typeof v === "string" && v !== "[redacted]").join(" ");
}
// Ten composite indexes plus the automatic array index must stay well below
// Firestore's 40,000 index-entry/document limit. Oversized text remains in every
// candidate set, preserving matches without an unbounded index fan-out.
export function buildJournalGrams(id: string, data: DocumentData): string[] {
  const grams = buildAdminSearchGrams(id, {displayName: journalText(id, data)});
  return grams.length > 2000 ? [adminSearchOverflow] : grams;
}
export async function reconcileJournalIndex(database: Firestore, id: string) {
  const ref = database.collection("systemLogs").doc(id);
  return database.runTransaction(async tx => {
    const doc = await tx.get(ref); if (!doc.exists) return false;
    const d = doc.data()!, grams = buildJournalGrams(id, d);
    const rank = Math.max(0, severities.indexOf(d.severity));
    if (JSON.stringify(d[journalIndexField]) === JSON.stringify(grams) && d.severityRank === rank && typeof d.category === "string") return false;
    tx.update(ref, {[journalIndexField]: grams, severityRank: rank, category: typeof d.category === "string" ? d.category : "unknown"});
    return true;
  });
}
export const maintainSystemLogSearchIndex = onDocumentWritten({document: "systemLogs/{logId}", region: "europe-west3", maxInstances: 5, retry: true}, async event => {
  if (!event.data?.after.exists) return;
  const before = event.data.before.data(), after = event.data.after.data()!;
  if (before && journalText(event.params.logId, before) === journalText(event.params.logId, after)
      && JSON.stringify(after[journalIndexField]) === JSON.stringify(buildJournalGrams(event.params.logId, after))
      && after.severityRank === Math.max(0, severities.indexOf(after.severity))) return;
  try { await reconcileJournalIndex(db, event.params.logId); }
  catch (error) { await db.doc(journalIndexState).set({ready: false, reason: "maintenance-failed", updatedAt: FieldValue.serverTimestamp()}, {merge: true}); throw error; }
});

function invalid(): never { throw new HttpsError("invalid-argument", "Invalid journal query."); }
function strings(v: unknown, max = 30): string[] {
  if (v == null) return [];
  if (!Array.isArray(v) || v.length > max || v.some(s => typeof s !== "string" || s.length > 160)) return invalid();
  return [...new Set(v as string[])].sort();
}
function parse(input: unknown) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return invalid();
  const d = input as DocumentData, f = d.filter ?? {};
  if (Object.keys(d).some(k => !["filter", "sort", "limit", "cursor", "operationAliases"].includes(k)) || !f || typeof f !== "object" || Array.isArray(f)) return invalid();
  const allowed = ["categories", "severities", "eventTypes", "actorRoles", "targetTypes", "outcomes", "actorUserId", "targetId", "organizationId", "isReviewed", "searchText", "startDate", "endDate", "isAppAdminReadable", "section"];
  if (Object.keys(f).some(k => !allowed.includes(k))) return invalid();
  const filter: DocumentData = {};
  for (const k of ["categories", "severities", "eventTypes", "actorRoles", "targetTypes", "outcomes"]) filter[k] = strings(f[k]);
  for (const k of ["actorUserId", "targetId", "organizationId", "searchText", "section"]) {
    if (f[k] != null && (typeof f[k] !== "string" || f[k].length > (k === "searchText" ? 200 : 200))) return invalid();
    if (f[k] != null) filter[k] = f[k];
  }
  for (const k of ["isReviewed", "isAppAdminReadable"]) { if (f[k] != null && typeof f[k] !== "boolean") return invalid(); if (f[k] != null) filter[k] = f[k]; }
  for (const k of ["startDate", "endDate"]) { if (f[k] != null && (!Number.isSafeInteger(f[k]) || f[k] < 0)) return invalid(); if (f[k] != null) filter[k] = f[k]; }
  if (filter.section && !["all", "actions", "errors", "security", "moderation", "organizations", "users"].includes(filter.section)) return invalid();
  const sort = d.sort ?? "newestFirst", limit = d.limit ?? 100;
  if (!sorts.includes(sort) || !Number.isInteger(limit) || limit < 1 || limit > 100 || (d.cursor != null && (typeof d.cursor !== "string" || !/^[a-f0-9-]{36}$/.test(d.cursor)))) return invalid();
  return {filter, sort: sort as string, limit: limit as number, cursor: d.cursor as string | undefined, operationAliases: strings(d.operationAliases, 128)};
}
export function journalMatches(id: string, d: DocumentData, f: DocumentData, aliases: string[]): boolean {
  for (const [key, field] of [["categories", "category"], ["severities", "severity"], ["eventTypes", "eventType"], ["actorRoles", "actorRole"], ["targetTypes", "targetType"], ["outcomes", "outcome"]]) if (f[key]?.length && !f[key].includes(d[field])) return false;
  for (const key of ["actorUserId", "targetId", "organizationId", "isAppAdminReadable"]) if (f[key] != null && f[key] !== d[key]) return false;
  if (f.isReviewed != null && f.isReviewed !== (d.isReviewed === true)) return false;
  const time = d.createdAt instanceof Timestamp ? d.createdAt.toMillis() : 0;
  if ((f.startDate != null && time < f.startDate) || (f.endDate != null && time > f.endDate)) return false;
  const section = f.section ?? "all";
  if (section === "actions" && !["audit", "content", "organization", "userAccount"].includes(d.category)) return false;
  if (section === "errors" && d.category !== "diagnostics" && severities.indexOf(d.severity) < 4) return false;
  if (section === "security" && d.retentionPolicy !== "security" && d.category !== "authorization") return false;
  if (section === "moderation" && d.category !== "moderation" && d.retentionPolicy !== "moderationDispute") return false;
  if (section === "organizations" && d.category !== "organization" && d.targetType !== "organization") return false;
  if (section === "users" && d.category !== "userAccount" && d.targetType !== "userProfile") return false;
  const tokens = normalizeAdminSearch(f.searchText ?? "").split(/\s+/).filter(Boolean), text = normalizeAdminSearch(journalText(id, d));
  return tokens.every(t => text.includes(t)) || aliases.includes(d.operationName);
}
export async function queryJournal(actorID: string, role: string, input: unknown, database = db, now = new Date()) {
  if (!["owner", "admin"].includes(role)) throw new HttpsError("permission-denied", "Journal access denied.");
  const p = parse(input), normalized = normalizeAdminSearch(p.filter.searchText ?? ""), anchor = adminSearchAnchor(normalized);
  const indexed = !!anchor && p.operationAliases.length === 0 && (await database.doc(journalIndexState).get()).get("ready") === true;
  const fingerprint = hash(JSON.stringify([actorID, role, p.filter, p.sort, p.limit, p.operationAliases, indexed]));
  let query: Query = database.collection("systemLogs");
  if (role === "admin") query = query.where("isAppAdminReadable", "==", true);
  if (indexed) query = query.where(journalIndexField, "array-contains-any", [anchor, adminSearchOverflow]);
  const descending = p.sort !== "oldestFirst";
  if (p.sort.startsWith("severity")) query = query.orderBy("severityRank", p.sort === "severityHighToLow" ? "desc" : "asc");
  if (p.sort === "category") query = query.orderBy("category", "asc");
  query = query.orderBy("createdAt", descending ? "desc" : "asc").orderBy(FieldPath.documentId(), descending ? "desc" : "asc");
  if (p.cursor) {
    const cursor = (await database.collection(journalCursorCollection).doc(p.cursor).get()).data();
    if (!cursor || cursor.fingerprint !== fingerprint || !(cursor.expiresAt instanceof Timestamp) || cursor.expiresAt.toMillis() <= now.getTime() || !Array.isArray(cursor.position)) throw new HttpsError("aborted", "Journal query expired. Refresh the list.");
    query = query.startAfter(...cursor.position);
  }
  const page = await query.limit(250).get(), items: DocumentData[] = [];
  let last: typeof page.docs[number] | undefined;
  for (const doc of page.docs) {
    last = doc;
    const data = doc.data();
    if (journalMatches(doc.id, data, p.filter, p.operationAliases)) {
      const item: DocumentData = {...data, id: doc.id}; delete item[journalIndexField];
      for (const key of ["createdAt", "reviewedAt"]) if (item[key] instanceof Timestamp) item[key] = item[key].toMillis();
      items.push(item);
      if (items.length === p.limit) break;
    }
  }
  const hasMore = !!last && (page.size === 250 || last.id !== page.docs.at(-1)?.id);
  let cursor: string | null = null;
  if (hasMore && last) {
    cursor = randomUUID();
    const position: unknown[] = [];
    if (p.sort.startsWith("severity")) position.push(last.get("severityRank"));
    if (p.sort === "category") position.push(last.get("category"));
    position.push(last.get("createdAt"), last.id);
    await database.collection(journalCursorCollection).doc(cursor).set({fingerprint, position, expiresAt: Timestamp.fromMillis(now.getTime() + 3600000)});
  }
  return {items, cursor, scanned: last ? page.docs.findIndex(d => d.id === last!.id) + 1 : 0};
}
export const listSystemLogs = onCall({region: "europe-west3", maxInstances: 10, enforceAppCheck: true}, async request => {
  const actor = await requireVerifiedActiveUser(request);
  return queryJournal(actor.uid, actor.permissions.globalRole ?? "user", request.data);
});
