import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {db} from "../firebase/admin";
import {analyticsConsentReceiptID, parseAnalyticsConsentMutation, persistAnalyticsConsentMutation, requireCurrentAnalyticsConsent} from "./analyticsConsent";

test("2026.13 preserves historical receipt evidence and authorizes a new choice", {skip: !process.env.FIRESTORE_EMULATOR_HOST}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):/);
  const uid = "privacy-correction-" + randomUUID();
  const oldID = randomUUID(), newID = randomUUID();
  const profile = db.doc(`users/${uid}`), state = db.doc(`analyticsConsentStates/${uid}`);
  const oldReceipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, oldID)}`);
  const newReceipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, newID)}`);
  const mutate = (consentID: string, privacyVersion: string, enabled = true) => persistAnalyticsConsentMutation(uid, parseAnalyticsConsentMutation({
    consentID, privacyVersion, enabled, locale: "de", appVersion: "1.0.3", disclosureVersion: "2026-08-25.1",
  }));
  try {
    await profile.set({accountStatus: "active"});
    await mutate(oldID, "2026.12");
    const original = (await oldReceipt.get()).data();
    await mutate(oldID, "2026.13");
    assert.deepEqual((await oldReceipt.get()).data(), original);
    assert.equal((await state.get()).get("privacyVersion"), "2026.12");
    await requireCurrentAnalyticsConsent(uid, oldID);
    await mutate(oldID, "2026.12", false);
    await mutate(newID, "2026.13");
    assert.equal((await newReceipt.get()).get("privacyVersion"), "2026.13");
    assert.equal((await oldReceipt.get()).get("privacyVersion"), "2026.12");
    assert.equal((await oldReceipt.get()).get("enabled"), false);
    assert.equal(await mutate(oldID, "2026.12"), false);
    await requireCurrentAnalyticsConsent(uid, newID);
    await assert.rejects(requireCurrentAnalyticsConsent(uid, oldID), {code: "failed-precondition"});
  } finally {
    await Promise.all([profile, state, oldReceipt, newReceipt].map(ref => ref.delete()));
  }
});

test("2026.21 keeps an existing content-analytics grant and allows a separate new choice", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST,
}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const uid = "privacy-banner-" + randomUUID();
  const existingID = randomUUID();
  const newID = randomUUID();
  const profile = db.doc(`users/${uid}`);
  const state = db.doc(`analyticsConsentStates/${uid}`);
  const existingReceipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, existingID)}`);
  const newReceipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, newID)}`);
  const mutate = (consentID: string, privacyVersion: string, enabled = true) =>
    persistAnalyticsConsentMutation(uid, parseAnalyticsConsentMutation({
      consentID, privacyVersion, enabled, locale: "uk", appVersion: "1.2",
      disclosureVersion: "2026-08-25.1",
    }));
  try {
    await profile.set({accountStatus: "active", acceptedPrivacyVersion: "2026.20"});
    assert.equal(await mutate(existingID, "2026.20"), true);
    await profile.update({acceptedPrivacyVersion: "2026.21"});
    await requireCurrentAnalyticsConsent(uid, existingID);
    assert.equal((await existingReceipt.get()).get("privacyVersion"), "2026.20");
    assert.equal(await mutate(existingID, "2026.21"), true);
    assert.equal((await state.get()).get("privacyVersion"), "2026.20");
    assert.equal(await mutate(existingID, "2026.20", false), false);
    assert.equal(await mutate(newID, "2026.21"), true);
    await requireCurrentAnalyticsConsent(uid, newID);
    assert.equal((await newReceipt.get()).get("privacyVersion"), "2026.21");
    await assert.rejects(requireCurrentAnalyticsConsent(uid, existingID), {code: "failed-precondition"});
  } finally {
    await Promise.all([profile, state, existingReceipt, newReceipt].map(ref => ref.delete()));
  }
});
