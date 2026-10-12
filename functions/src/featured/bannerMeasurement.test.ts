import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {analyticsRateLimitID} from "../analytics/analyticsEventGuard";
import {
  bannerConsentDisclosureVersion, bannerConsentPrivacyVersion,
  bannerConsentPurpose, bannerConsentReceiptCollection, bannerConsentReceiptID,
  bannerConsentStateCollection, isCurrentBannerConsent,
  parseBannerConsentInput, persistBannerMeasurementConsent,
} from "./bannerMeasurementConsent";
import {
  bannerMeasurementEventReceiptID, bannerMeasurementRateLimitCollection,
  bannerMeasurementReceiptCollection, bannerMeasurementShardCollection,
  parseBannerMeasurement, persistBannerMeasurement,
} from "./bannerMeasurementTracking";

test("banner choice is separate and requires the exact disclosed purpose", () => {
  const consentID = randomUUID();
  const value = {enabled: true, consentID, locale: "uk", privacyVersion: bannerConsentPrivacyVersion,
    disclosureVersion: bannerConsentDisclosureVersion};
  assert.equal(parseBannerConsentInput(value).consentID, consentID);
  assert.throws(() => parseBannerConsentInput({...value, privacyVersion: "2026.20"}));
  assert.throws(() => parseBannerConsentInput({...value, extra: true}));
  assert.equal(isCurrentBannerConsent({
    enabled: true, consentID, purpose: bannerConsentPurpose,
    privacyVersion: bannerConsentPrivacyVersion,
    disclosureVersion: bannerConsentDisclosureVersion,
  }, consentID), true);
  assert.equal(isCurrentBannerConsent({enabled: true, consentID, purpose: "owner-aggregate-analytics-v1",
    privacyVersion: bannerConsentPrivacyVersion, disclosureVersion: bannerConsentDisclosureVersion}, consentID), false);
});

test("measurement envelope contains only the banner, placement and receipt data", () => {
  const now = new Date("2026-10-12T12:00:00Z");
  const value = {id: randomUUID(), bannerID: "banner-1", section: "directory", kind: "impression",
    occurredAtMilliseconds: now.getTime(), consentID: randomUUID()};
  assert.equal(parseBannerMeasurement(value, now).section, "directory");
  assert.throws(() => parseBannerMeasurement({...value, userID: "forged"}, now));
  assert.throws(() => parseBannerMeasurement({...value, bannerID: "../users"}, now));
  assert.throws(() => parseBannerMeasurement({...value, occurredAtMilliseconds: now.getTime() - 49 * 3_600_000}, now));
  assert.throws(() => parseBannerMeasurement({...value, kind: "hover"}, now));
});

test("one consented measurement counts once and withdrawal stops further counts", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const uid = `banner-${randomUUID()}`;
  const consentID = randomUUID();
  const laterConsentID = randomUUID();
  const bannerID = `banner-${randomUUID()}`;
  const eventID = randomUUID();
  const now = new Date("2026-10-12T12:00:00Z");
  const policyRef = db.doc("legalDocuments/privacy");
  const profileRef = db.doc(`users/${uid}`);
  const bannerRef = db.doc(`featuredBanners/${bannerID}`);
  const stateRef = db.collection(bannerConsentStateCollection).doc(uid);
  const consentReceiptRef = db.collection(bannerConsentReceiptCollection).doc(bannerConsentReceiptID(uid, consentID));
  const eventReceiptRef = db.collection(bannerMeasurementReceiptCollection)
    .doc(bannerMeasurementEventReceiptID(uid, eventID));
  const consent = parseBannerConsentInput({enabled: true, consentID, locale: "de",
    privacyVersion: bannerConsentPrivacyVersion, disclosureVersion: bannerConsentDisclosureVersion});
  const event = parseBannerMeasurement({id: eventID, bannerID, section: "home", kind: "impression",
    occurredAtMilliseconds: now.getTime(), consentID}, now);
  const policyBefore = await policyRef.get();
  try {
    await policyRef.set({activeVersion: "2026.20"});
    await profileRef.set({accountStatus: "active", acceptedPrivacyVersion: bannerConsentPrivacyVersion});
    await bannerRef.set({isActive: true, visibleSections: ["home"], actionType: "externalURL",
      startsAt: Timestamp.fromDate(new Date("2026-10-01T00:00:00Z"))});
    await assert.rejects(persistBannerMeasurementConsent(uid, consent), {code: "failed-precondition"});
    await policyRef.set({activeVersion: bannerConsentPrivacyVersion});
    assert.equal(await persistBannerMeasurementConsent(uid, consent), true);
    await assert.rejects(persistBannerMeasurement(uid, {
      ...event, id: randomUUID(), section: "directory",
    }, now), {code: "not-found"});
    assert.deepEqual(await persistBannerMeasurement(uid, event, now), {counted: true, duplicate: false});
    assert.deepEqual(await persistBannerMeasurement(uid, event, now), {counted: true, duplicate: true});
    await policyRef.set({activeVersion: "2026.22"});
    await assert.rejects(persistBannerMeasurement(uid, {...event, id: randomUUID()}, now),
      {code: "failed-precondition"});
    await policyRef.set({activeVersion: bannerConsentPrivacyVersion});
    await assert.rejects(persistBannerMeasurement(uid, {...event, kind: "click"}, now),
      {code: "invalid-argument"});
    const shards = await db.collection(bannerMeasurementShardCollection).where("bannerID", "==", bannerID).get();
    assert.equal(shards.size, 1);
    assert.equal(shards.docs[0].get("impressions"), 1);
    await persistBannerMeasurementConsent(uid, {...consent, enabled: false});
    await assert.rejects(persistBannerMeasurement(uid, event, now), {code: "failed-precondition"});
    assert.equal(await persistBannerMeasurementConsent(uid, {...consent, consentID: laterConsentID}), true);
    await assert.rejects(persistBannerMeasurement(uid, {...event, consentID: laterConsentID}, now),
      {code: "invalid-argument"});
  } finally {
    const remainingShards = await db.collection(bannerMeasurementShardCollection).where("bannerID", "==", bannerID).get();
    await Promise.all(remainingShards.docs.map(doc => doc.ref.delete()));
    if (policyBefore.exists) await policyRef.set(policyBefore.data()!);
    else await policyRef.delete();
    await Promise.all([profileRef, bannerRef, stateRef, consentReceiptRef,
      db.collection(bannerConsentReceiptCollection).doc(bannerConsentReceiptID(uid, laterConsentID)),
      eventReceiptRef,
      db.collection(bannerMeasurementRateLimitCollection).doc(analyticsRateLimitID(uid, now))
    ].map(ref => ref.delete()));
  }
});
