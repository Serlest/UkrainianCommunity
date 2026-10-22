import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {dailyDocumentIDFor} from "./analyticsDate";
import {analyticsConsentReceiptID, persistAnalyticsConsentMutation} from "./analyticsConsent";
import {trackAnalyticsEvent} from "./trackAnalyticsEvent";

// Exercise the public callable handler, including legal/consent gates and the
// real Firestore transaction; parser-only tests cannot prove counter agreement.
test("callable counting is atomic across retries, days, content types and withdrawal", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):/);
  const uid = `audit-${randomUUID()}`;
  const consentID = randomUUID();
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 3_600_000);
  const todayID = dailyDocumentIDFor(now), yesterdayID = dailyDocumentIDFor(yesterday);
  const globals = ["legalDocuments/terms", "legalDocuments/privacy", "analyticsSchemaState/current",
    ...[todayID, yesterdayID].flatMap(day => ["analyticsDailyStats", "analyticsTopContent", "analyticsRegionStats"].map(c => `${c}/${day}`))];
  const before = await db.getAll(...globals.map(path => db.doc(path)));
  const profile = db.doc(`users/${uid}`);
  const content = ["news", "events", "organizations"].map(collection => db.doc(`${collection}/${uid}`));
  const like = db.doc(`likes/${uid}_${uid}`);
  const send = (name: string, occurredAt = now) => trackAnalyticsEvent.run({
    auth: {uid, token: {email_verified: true}},
    data: {name, consentID, occurredAtMilliseconds: occurredAt.getTime(), parameters: {
      content_id: uid, federal_state: "wien", content_title: "Forged client metadata",
    }},
  } as never);
  try {
    await Promise.all([
      db.doc(globals[0]).set({activeVersion: "audit"}),
      db.doc(globals[1]).set({activeVersion: "2026.22"}),
      db.doc(globals[2]).set({schemaVersion: 2, status: "complete", generation: "audit", cutoverDay: todayID}),
      profile.set({accountStatus: "active", globalRole: "user", acceptedTermsVersion: "audit", acceptedPrivacyVersion: "2026.22"}),
      ...content.map(ref => ref.set({title: "Canonical", name: "Canonical", moderationStatus: "approved", regionScope: "federalState", federalState: "tirol"})),
      ...globals.slice(3).map(path => db.doc(path).delete()),
    ]);
    await persistAnalyticsConsentMutation(uid, {enabled: true, consentID, locale: "uk", privacyVersion: "2026.22", disclosureVersion: "2026-08-25.1"});
    for (const name of ["news_view", "event_view", "organization_view"]) {
      const responses = await Promise.all(Array.from({length: 4}, () => send(name)));
      assert.equal(responses.filter(response => response.tracked).length, 1);
    }
    assert.deepEqual(await send("news_view", yesterday), {tracked: true});
    assert.deepEqual(await send("news_view", yesterday), {tracked: false});
    await assert.rejects(send("news_like"), {code: "failed-precondition"});
    await like.set({userId: uid, newsId: uid, createdAt: Timestamp.fromDate(now)});
    assert.deepEqual(await send("news_like"), {tracked: true});
    assert.deepEqual(await send("news_like"), {tracked: false});
    const daily = await db.doc(`analyticsDailyStats/${todayID}`).get();
    assert.equal(daily.get("metrics.totalViews"), 3);
    assert.equal(daily.get("metrics.newsLikes"), 1);
    const top = await db.doc(`analyticsTopContent/${todayID}`).get();
    const items = Object.values(top.get("itemsByKey")) as Array<Record<string, unknown>>;
    assert.equal(items.length, 3);
    assert.ok(items.every(item => item.viewCount === 1 && item.title === "Canonical" && item.federalState === "tirol"));
    const regions = await db.doc(`analyticsRegionStats/${todayID}`).get();
    const rows = Object.values(regions.get("regionsByKey")) as Array<Record<string, unknown>>;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].viewCount, 3);
    assert.equal(rows[0].federalState, "tirol");
    await persistAnalyticsConsentMutation(uid, {enabled: false, consentID, locale: "uk"});
    await assert.rejects(send("news_view"), {code: "failed-precondition"});
    assert.equal((await db.doc(`analyticsDailyStats/${todayID}`).get()).get("metrics.totalViews"), 3);
  } finally {
    await Promise.all(before.map(snapshot => snapshot.exists ? snapshot.ref.set(snapshot.data()!) : snapshot.ref.delete()));
    await Promise.all([profile, ...content, like, db.doc(`analyticsUserActivity/${uid}`),
      db.doc(`analyticsConsentStates/${uid}`), db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, consentID)}`)]
      .map(ref => db.recursiveDelete(ref)));
  }
});
