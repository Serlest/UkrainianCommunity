import {test} from "node:test";
import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {Timestamp, FieldValue} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {bannerReportCollection, bannerProjectionCollection, bannerReportState, projectBannerShard, readBannerReport, materializeBannerReports, getBannerMeasurementReport} from "./bannerMeasurementReports";

const integration = {skip: !process.env.FIRESTORE_EMULATOR_HOST};
test("banner report migration and scheduled projection preserve dimensions and retries", integration, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const now = new Date("2026-10-22T22:30:00Z"), day = "2026-10-22";
  const banner = `report-${randomUUID()}`;
  const refs = [0, 1, 2].map(shard => db.collection("bannerMeasurementDailyShards").doc(`${banner}_${shard}`));
  const state = db.doc(bannerReportState), before = await state.get();
  try {
    await state.delete();
    await assert.rejects(readBannerReport(7, banner, now), {code: "unavailable"});
    for (let i = 0; i < refs.length; i++) {
      await refs[i].set({day, bannerID: banner, section: i === 2 ? "events" : "home", displayRegion: i === 2 ? "wien" : "tirol",
        shard: i, impressions: 10, clicks: i, updatedAt: Timestamp.fromDate(new Date(now.getTime() - 60000)),
        expiresAt: Timestamp.fromDate(new Date("2027-11-22"))});
      await Promise.all([db.runTransaction(tx => projectBannerShard(tx, refs[i])), db.runTransaction(tx => projectBannerShard(tx, refs[i]))]);
    }
    await state.set({ready: true, completedAt: Timestamp.fromDate(now)});
    let report = await readBannerReport(1, banner, now);
    assert.equal(report.counts.reduce((n, r) => n + r.impressions, 0), 30);
    assert.equal(report.counts.reduce((n, r) => n + r.clicks, 0), 3);
    assert.equal(report.counts.find(r => r.displayRegion === "tirol")?.impressions, 20);
    // A late update after backfill must be projected once, without a lost delta.
    await refs[0].update({impressions: FieldValue.increment(4), updatedAt: Timestamp.fromDate(now)});
    await materializeBannerReports(now);
    await materializeBannerReports(now);
    report = await readBannerReport(1, banner, now);
    assert.equal(report.counts.reduce((n, r) => n + r.impressions, 0), 34);
    assert.equal((await readBannerReport(1, banner, new Date("2026-10-23T00:01:00Z"))).counts.length, 0);
    // Resume a fixed scan window after a source moved beyond its upper bound.
    await materializeBannerReports(now, 0);
    await refs[0].update({impressions: FieldValue.increment(3), updatedAt: Timestamp.fromDate(new Date(now.getTime() + 5000))});
    await materializeBannerReports(new Date(now.getTime() + 10000));
    await materializeBannerReports(new Date(now.getTime() + 11000));
    assert.equal((await readBannerReport(1, banner, now)).counts.reduce((n, r) => n + r.impressions, 0), 37);
    await assert.rejects(readBannerReport(2, banner, now), {code: "invalid-argument"});
    await assert.rejects(readBannerReport(1, "../bad", now), {code: "invalid-argument"});
    const uid = `reader-${randomUUID()}`;
    const legalRefs = [db.doc("legalDocuments/terms"), db.doc("legalDocuments/privacy")];
    const legalBefore = await db.getAll(...legalRefs);
    await Promise.all(legalRefs.map(ref => ref.set({activeVersion: "audit"})));
    await db.doc(`users/${uid}`).set({accountStatus: "active", globalRole: "user", acceptedTermsVersion: "audit", acceptedPrivacyVersion: "audit"});
    try {
      await db.doc(`users/${uid}`).update({globalRole: "admin"});
      await assert.rejects(getBannerMeasurementReport.run({auth: {uid, token: {email_verified: true}}, data: {dayCount: 1}} as never), {code: "permission-denied"});
      await db.doc(`users/${uid}`).update({globalRole: "owner", requiresMultiFactorAuth: true});
      await assert.rejects(getBannerMeasurementReport.run({auth: {uid, token: {email_verified: true}}, data: {dayCount: 1}} as never), {code: "failed-precondition"});
      const result = await getBannerMeasurementReport.run({auth: {uid, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}}, data: {dayCount: 1}} as never);
      assert.equal(result.calendar, "UTC");
    } finally {
      await db.doc(`users/${uid}`).delete();
      await Promise.all(legalBefore.map(doc => doc.exists ? doc.ref.set(doc.data()!) : doc.ref.delete()));
    }
  } finally {
    await Promise.all(refs.flatMap(ref => [ref.delete(), db.collection(bannerProjectionCollection).doc(ref.id).delete()]));
    const rows = await db.collection(bannerReportCollection).where("bannerID", "==", banner).get();
    await Promise.all(rows.docs.map(d => d.ref.delete()));
    if (before.exists) await state.set(before.data()!); else await state.delete();
  }
});
