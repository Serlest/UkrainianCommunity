import {archiveBannerMeasurementConfiguration, bannerMeasurementHistoryCollection} from "./bannerMeasurementHistory";
import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {analyticsRateLimitID} from "../analytics/analyticsEventGuard";
import {
  bannerConsentDisclosureVersion, bannerConsentPrivacyVersion,
  bannerConsentPurpose, bannerConsentReceiptCollection, bannerConsentReceiptID,
  bannerConsentStateCollection, hasAcknowledgedBannerPrivacy, isCurrentBannerConsent,
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
  assert.equal(hasAcknowledgedBannerPrivacy("2026.21", "2026.21"), true);
  assert.equal(hasAcknowledgedBannerPrivacy("2026.21", "2026.22"), false);
  assert.equal(hasAcknowledgedBannerPrivacy("2026.22", "2026.22"), true);
  assert.equal(hasAcknowledgedBannerPrivacy("2026.23", "2026.23"), false);
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
  assert.equal(parseBannerMeasurement({...value, displayRegion: "wien"}, now).displayRegion, "wien");
  assert.throws(() => parseBannerMeasurement({...value, displayRegion: "gps:48.2,16.3"}, now));
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
  const migratedEventID = randomUUID();
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
  const click = parseBannerMeasurement({id: randomUUID(), bannerID, section: "home", kind: "click",
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
    assert.deepEqual(await persistBannerMeasurement(uid, click, now), {counted: true, duplicate: false});
    assert.deepEqual(await persistBannerMeasurement(uid, click, now), {counted: true, duplicate: true});
    const regional = {...event, id: randomUUID(), displayRegion: "tirol"};
    assert.deepEqual(await persistBannerMeasurement(uid, regional, now), {counted: true, duplicate: false});
    assert.deepEqual(await persistBannerMeasurement(uid, regional, now), {counted: true, duplicate: true});
    await assert.rejects(persistBannerMeasurement(uid, {...regional, displayRegion: "wien"}, now), {code: "invalid-argument"});
    await policyRef.set({activeVersion: "2026.22"});
    await assert.rejects(persistBannerMeasurement(uid, {...event, id: randomUUID()}, now),
      {code: "failed-precondition"});
    await profileRef.update({acceptedPrivacyVersion: "2026.22"});
    assert.equal(await persistBannerMeasurementConsent(uid, consent), true);
    assert.deepEqual(await persistBannerMeasurement(uid, {...event, id: migratedEventID}, now),
      {counted: true, duplicate: false});
    await policyRef.set({activeVersion: bannerConsentPrivacyVersion});
    await profileRef.update({acceptedPrivacyVersion: bannerConsentPrivacyVersion});
    await assert.rejects(persistBannerMeasurement(uid, {...event, kind: "click"}, now),
      {code: "invalid-argument"});
    const shards = await db.collection(bannerMeasurementShardCollection).where("bannerID", "==", bannerID).get();
    assert.equal(shards.docs.reduce((total, shard) => total + shard.get("impressions"), 0), 3);
    assert.equal(shards.docs.reduce((total, shard) => total + shard.get("clicks"), 0), 1);
    assert.ok(shards.docs.every(shard => shard.get("day") === "2026-10-12"
      && shard.get("bannerID") === bannerID && shard.get("section") === "home"));
    // An already observed event remains valid after the campaign is deleted.
    await db.runTransaction(async transaction => {
      const snapshot = await transaction.get(bannerRef);
      await archiveBannerMeasurementConfiguration(transaction, snapshot, Timestamp.fromMillis(now.getTime() + 1000));
      transaction.delete(bannerRef);
    });
    assert.deepEqual(await persistBannerMeasurement(uid, {...event, id: randomUUID()}, now),
      {counted: true, duplicate: false});
    await assert.rejects(persistBannerMeasurement(uid, {...event, id: randomUUID(),
      occurredAtMilliseconds: now.getTime() + 2000}, now), {code: "not-found"});
    await persistBannerMeasurementConsent(uid, {...consent, enabled: false});
    await assert.rejects(persistBannerMeasurement(uid, event, now), {code: "failed-precondition"});
    assert.equal(await persistBannerMeasurementConsent(uid, {...consent, consentID: laterConsentID, disclosureVersion: "2026-10-12.1"}), true);
    await assert.rejects(persistBannerMeasurement(uid, {...event, id: randomUUID(),
      consentID: laterConsentID, displayRegion: "wien"}, now), {code: "failed-precondition"});
    await assert.rejects(persistBannerMeasurement(uid, {...event, consentID: laterConsentID}, now),
      {code: "invalid-argument"});
  } finally {
    const remainingShards = await db.collection(bannerMeasurementShardCollection).where("bannerID", "==", bannerID).get();
    await Promise.all(remainingShards.docs.map(doc => doc.ref.delete()));
    if (policyBefore.exists) await policyRef.set(policyBefore.data()!);
    else await policyRef.delete();
    await Promise.all([db.collection(bannerMeasurementHistoryCollection).doc(bannerID),
      profileRef, bannerRef, stateRef, consentReceiptRef,
      db.collection(bannerConsentReceiptCollection).doc(bannerConsentReceiptID(uid, laterConsentID)),
      eventReceiptRef,
      db.collection(bannerMeasurementReceiptCollection).doc(bannerMeasurementEventReceiptID(uid, migratedEventID)),
      db.collection(bannerMeasurementReceiptCollection).doc(bannerMeasurementEventReceiptID(uid, click.id)),
      db.collection(bannerMeasurementRateLimitCollection).doc(analyticsRateLimitID(uid, now))
    ].map(ref => ref.delete()));
  }
});
