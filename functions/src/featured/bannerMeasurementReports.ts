import {onSchedule} from "firebase-functions/v2/scheduler";
import {createHash} from "node:crypto";
import {FieldPath, FieldValue, Timestamp, type DocumentData, type DocumentReference, type Transaction} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {requireVerifiedActiveUser} from "../auth/context";
import {assertOwner} from "../permissions/userPermissions";

export const bannerReportCollection = "bannerMeasurementReportShards";
export const bannerProjectionCollection = "bannerMeasurementReportProjections";
export const bannerReportState = "bannerMeasurementReportState/v1";
export const bannerReportShardCount = 16;
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
export const bannerReportID = (day: string, bannerID: string | undefined, shard: number) =>
  `${day}_${bannerID == null ? "overview" : hash(bannerID)}_${shard}`;
function count(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) throw new Error("Invalid banner aggregate counter.");
  return value as number;
}

// Read the latest source and checkpoint atomically. Delayed schedules and
// backfill retries cannot lose events or double-count accepted measurements.
export async function projectBannerShard(
  tx: Transaction, sourceRef: DocumentReference
): Promise<void> {
  const database = sourceRef.firestore;
  const checkpointRef = database.collection(bannerProjectionCollection).doc(sourceRef.id);
  const [source, checkpoint] = await tx.getAll(sourceRef, checkpointRef);
  if (!source.exists) return;
  const row = source.data()!;
  const impressions = count(source.get("impressions") ?? 0);
  const clicks = count(source.get("clicks") ?? 0);
  const impressionDelta = impressions - count(checkpoint.get("impressions") ?? 0);
  const clickDelta = clicks - count(checkpoint.get("clicks") ?? 0);
  if (impressionDelta < 0 || clickDelta < 0) throw new Error("Banner counters regressed; reconciliation required.");
  if (impressionDelta === 0 && clickDelta === 0) return;
  const {day, bannerID, section, shard, expiresAt} = row;
  const region = row.displayRegion ?? "unknown";
  if (typeof day !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(day)
    || typeof bannerID !== "string" || !Number.isInteger(shard) || shard < 0 || shard >= bannerReportShardCount
    || !["home", "events", "organizations", "directory"].includes(section)
    || !["unknown", "allAustria", "burgenland", "kaernten", "niederoesterreich", "oberoesterreich", "salzburg", "steiermark", "tirol", "vorarlberg", "wien"].includes(region)
    || !(expiresAt instanceof Timestamp)) throw new Error("Invalid banner aggregate dimensions.");
  const bucket = `${section}_${region}`;
  for (const scope of [undefined, bannerID]) {
    tx.set(database.collection(bannerReportCollection).doc(bannerReportID(day, scope, shard)), {
      day, scope: scope == null ? "overview" : "banner", ...(scope == null ? {} : {bannerID}),
      buckets: {[bucket]: {section, displayRegion: region,
        impressions: FieldValue.increment(impressionDelta), clicks: FieldValue.increment(clickDelta)}},
      expiresAt, updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  tx.set(checkpointRef, {impressions, clicks, expiresAt}, {merge: true});
}

export async function readBannerReport(
  dayCount: number, bannerID: string | undefined, now: Date = new Date()
) {
  if (![1, 7, 30].includes(dayCount)) throw new HttpsError("invalid-argument", "Invalid report period.");
  if (bannerID !== undefined && !/^[A-Za-z0-9_-]{1,128}$/.test(bannerID)) throw new HttpsError("invalid-argument", "Invalid banner.");
  const state = await db.doc(bannerReportState).get();
  if (state.get("ready") !== true) {
    throw new HttpsError("unavailable", "Banner summaries are being prepared. Retry shortly.");
  }
  const refs: DocumentReference[] = [];
  for (let offset = dayCount - 1; offset >= 0; offset--) {
    const day = new Date(now.getTime() - offset * 86400000).toISOString().slice(0, 10);
    for (let shard = 0; shard < bannerReportShardCount; shard++) refs.push(db.collection(bannerReportCollection).doc(bannerReportID(day, bannerID, shard)));
  }
  const rows = new Map<string, {day: string; bannerID: string; section: string; displayRegion: string; impressions: number; clicks: number}>();
  for (let offset = 0; offset < refs.length; offset += 100) {
    const page = await db.getAll(...refs.slice(offset, offset + 100));
    for (const doc of page) {
      if (!doc.exists) continue;
      const day = doc.get("day") as string;
      for (const value of Object.values(doc.get("buckets") ?? {}) as DocumentData[]) {
        const key = `${day}_${value.section}_${value.displayRegion}`;
        const row = rows.get(key) ?? {day, bannerID: bannerID ?? "all", section: value.section, displayRegion: value.displayRegion, impressions: 0, clicks: 0};
        row.impressions += count(value.impressions); row.clicks += count(value.clicks);
        rows.set(key, row);
      }
    }
  }
  return {counts: [...rows.values()], periodAnchorMilliseconds: now.getTime(), generatedAtMilliseconds: (state.get("completedAt") as Timestamp | undefined)?.toMillis() ?? now.getTime(), calendar: "UTC"};
}

export const getBannerMeasurementReport = onCall(
  {region: "europe-west3", maxInstances: 10, enforceAppCheck: true}, async request => {
    const actor = await requireVerifiedActiveUser(request); assertOwner(actor.permissions);
    const input = request.data;
    if (!input || typeof input !== "object" || Array.isArray(input)
      || Object.keys(input).some(key => !["dayCount", "bannerID"].includes(key))) throw new HttpsError("invalid-argument", "Invalid report request.");
    return readBannerReport(input.dayCount, input.bannerID);
  }
);

// Materialize changed source shards in batches, not three extra aggregate writes
// for every impression. Durable page cursors bound memory and resume interrupted
// runs. A fixed upper bound prevents a moving source from losing late writes.
export const rollupBannerMeasurementReports = onSchedule({
  schedule: "*/5 * * * *", timeZone: "UTC", region: "europe-west3",
  maxInstances: 1, concurrency: 1, timeoutSeconds: 540, memory: "256MiB",
  retryCount: 3,
}, async () => { await materializeBannerReports(); });

export async function materializeBannerReports(now: Date = new Date(), maximumPages = 40) {
  const stateRef = db.doc(bannerReportState);
  const state = (await stateRef.get()).data();
  if (state?.ready !== true) return;
  const upper = state.scanUpper instanceof Timestamp ? state.scanUpper : Timestamp.fromDate(now);
  const lower = state.completedThrough instanceof Timestamp ? state.completedThrough : Timestamp.fromMillis(0);
  let afterTime = state.afterTime instanceof Timestamp ? state.afterTime : undefined;
  let afterID = typeof state.afterID === "string" ? state.afterID : undefined;
  await stateRef.set({scanUpper: upper}, {merge: true});
  for (let pageNumber = 0; pageNumber < maximumPages; pageNumber++) {
    let query = db.collection("bannerMeasurementDailyShards")
      .where("updatedAt", ">=", lower).where("updatedAt", "<=", upper)
      .orderBy("updatedAt").orderBy(FieldPath.documentId()).limit(250);
    if (afterTime && afterID) query = query.startAfter(afterTime, afterID);
    const page = await query.get();
    // Five bounded transactions at a time; retries re-read the current counter.
    for (let offset = 0; offset < page.size; offset += 5) {
      await Promise.all(page.docs.slice(offset, offset + 5).map(doc =>
        db.runTransaction(tx => projectBannerShard(tx, doc.ref))));
    }
    if (page.size < 250) {
      await stateRef.set({completedThrough: upper, completedAt: FieldValue.serverTimestamp(),
        scanUpper: FieldValue.delete(), afterTime: FieldValue.delete(), afterID: FieldValue.delete()}, {merge: true});
      return;
    }
    const last = page.docs[page.size - 1];
    afterTime = last.get("updatedAt"); afterID = last.id;
    await stateRef.set({afterTime, afterID}, {merge: true});
  }
}
