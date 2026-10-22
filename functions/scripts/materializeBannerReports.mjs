import {execFileSync} from "node:child_process";
import {OAuth2Client} from "google-auth-library";
import {initializeApp} from "firebase-admin/app";
import {Firestore, FieldPath, FieldValue} from "firebase-admin/firestore";

const project = process.argv.find(a => a.startsWith("--project="))?.slice(10);
const apply = process.argv.includes("--apply");
if (!project) throw new Error("Use --project=<id>; dry-run by default, --apply to materialize.");
initializeApp({projectId: project});
let authClient;
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  authClient = new OAuth2Client();
  authClient.setCredentials({access_token: execFileSync("gcloud", ["auth", "print-access-token"],
    {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}).trim(), expiry_date: Date.now() + 3000000});
}
const db = new Firestore({projectId: project, ...(authClient ? {authClient} : {})});
const {projectBannerShard, bannerReportCollection, bannerReportState, bannerReportID} = await import("../lib/featured/bannerMeasurementReports.js");
let after, scanned = 0;
while (true) {
  let q = db.collection("bannerMeasurementDailyShards").orderBy(FieldPath.documentId()).limit(100);
  if (after) q = q.startAfter(after);
  const page = await q.get();
  for (const doc of page.docs) {
    const row = doc.data();
    if (![row.impressions, row.clicks].every(n => Number.isSafeInteger(n) && n >= 0)) throw new Error("Malformed source shard.");
    if (apply) await db.runTransaction(tx => projectBannerShard(tx, doc.ref));
    scanned++;
  }
  if (page.size < 100) break;
  after = page.docs.at(-1);
}
let verified = false;
if (apply) {
  // One transactional snapshot verifies every dimensional total before enabling
  // reads. A concurrent new measurement requires another idempotent pass.
  await db.runTransaction(async tx => {
    const source = await tx.get(db.collection("bannerMeasurementDailyShards"));
    const target = await tx.get(db.collection(bannerReportCollection));
    const expected = new Map();
    for (const doc of source.docs) {
      const r = doc.data(), bucket = `${r.section}_${r.displayRegion ?? "unknown"}`;
      for (const banner of [undefined, r.bannerID]) {
        const key = `${bannerReportID(r.day, banner, r.shard)}|${bucket}`;
        const v = expected.get(key) ?? [0, 0]; v[0] += r.impressions; v[1] += r.clicks; expected.set(key, v);
      }
    }
    for (const doc of target.docs) {
      for (const [bucket, row] of Object.entries(doc.get("buckets") ?? {})) {
        const key = `${doc.id}|${bucket}`, v = expected.get(key);
        if (!v || v[0] !== row.impressions || v[1] !== row.clicks) throw new Error("Summary verification failed; rerun backfill before enabling.");
        expected.delete(key);
      }
    }
    if (expected.size) throw new Error("Summary missing source data; rerun backfill before enabling.");
    tx.set(db.doc(bannerReportState), {ready: true, completedAt: FieldValue.serverTimestamp()}, {merge: true});
    verified = true;
  });
}
console.log(JSON.stringify({project, apply, scanned, verified}));
