import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {persistAnalyticsConsentMutation, analyticsConsentReceiptID, isCurrentAnalyticsConsent, requireCurrentAnalyticsConsent, updateAnalyticsConsentV2} from "./analyticsConsent";
import {getLegalEvidencePage, listLegalEvidenceAccounts} from "../legal/legalEvidence";

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
function localOnly() {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(127\.0\.0\.1|localhost):/);
}

test("consent preserves receipts, rejects stale grants and withdrawal-before-grant", {skip: !enabled}, async () => {
  localOnly();
  const uid = "reliability-" + randomUUID();
  const ids = [randomUUID(), randomUUID(), randomUUID()];
  const state = db.doc(`analyticsConsentStates/${uid}`);
  const profile = db.doc(`users/${uid}`);
  const receipts = ids.map(id => db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, id)}`));
  const grant = (index: number, value = true) => persistAnalyticsConsentMutation(uid, {
    enabled: value, consentID: ids[index], locale: "de", appVersion: "1.0.1",
  });
  try {
    await profile.set({globalRole: "user"});
    await assert.rejects(updateAnalyticsConsentV2.run({auth: {uid, token: {email_verified: true}}, data: {
        enabled: true, consentID: ids[0], locale: "de", principalId: "different-user", privacyVersion: "2026.12", disclosureVersion: "2026-08-25.1",
      }} as any), {code: "permission-denied"});
    assert.equal((await receipts[0].get()).exists, false);
    assert.equal(await grant(0), true);
    const initial = (await receipts[0].get()).data()!;
    assert.equal(initial.privacyVersion, "2026.12");
    assert.equal(await grant(0), true);
    assert.equal((await receipts[0].get()).get("grantedAt").isEqual(initial.grantedAt), true);
    await grant(0, false);
    assert.equal(await grant(0), false);
    assert.equal((await state.get()).get("enabled"), false);
    assert.equal(await grant(1), true);
    await grant(0, false);
    assert.equal((await state.get()).get("consentID"), ids[1]);
    assert.equal(await grant(0), false);
    assert.equal((await state.get()).get("consentID"), ids[1]);
    await grant(2, false);
    assert.equal(await grant(2), false);
    assert.equal((await receipts[2].get()).get("grantedAt"), null);
    assert.equal(isCurrentAnalyticsConsent((await state.get()).data(), ids[1]), true);
    await receipts[1].update({enabled: false, withdrawnAt: Timestamp.now()});
    // Even historical state incorrectly resurrected by the old server cannot authorize delivery.
    await assert.rejects(requireCurrentAnalyticsConsent(uid, ids[1]), {code: "failed-precondition"});
    await assert.rejects(persistAnalyticsConsentMutation(uid, {
      enabled: true, consentID: randomUUID(), locale: "de", existingReceiptOnly: true,
    }), {code: "failed-precondition"});
  } finally {await Promise.all([profile, state, ...receipts].map(ref => ref.delete()));}
});

test("a late consent mutation cannot recreate data after account deletion or bypass deactivation", {skip: !enabled}, async () => {
  localOnly();
  const uid = "consent-lifecycle-" + randomUUID();
  const profile = db.doc(`users/${uid}`), state = db.doc(`analyticsConsentStates/${uid}`);
  const id = randomUUID(), laterID = randomUUID();
  const receipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, id)}`);
  const laterReceipt = db.doc(`analyticsConsentReceipts/${analyticsConsentReceiptID(uid, laterID)}`);
  const grant = {enabled: true, consentID: id, locale: "de" as const, privacyVersion: "2026.12", disclosureVersion: "2026-08-25.1"};
  try {
    await profile.set({accountStatus: "active"});
    await persistAnalyticsConsentMutation(uid, grant);
    await profile.update({accountStatus: "deactivated"});
    await assert.rejects(persistAnalyticsConsentMutation(uid, {...grant, consentID: laterID}), {code: "permission-denied"});
    assert.equal((await laterReceipt.get()).exists, false);
    assert.equal(await persistAnalyticsConsentMutation(uid, {...grant, enabled: false}), false);
    assert.equal((await state.get()).get("enabled"), false);
    await Promise.all([profile, state, receipt].map(ref => ref.delete()));
    await assert.rejects(persistAnalyticsConsentMutation(uid, grant), {code: "permission-denied"});
    assert.equal(await persistAnalyticsConsentMutation(uid, {...grant, enabled: false}), false);
    assert.equal((await state.get()).exists, false);
    assert.equal((await receipt.get()).exists, false);
  } finally {await Promise.all([profile, state, receipt, laterReceipt].map(ref => ref.delete()));}
});

test("legal history pages beyond 500 and exact account cursor survives deleted anchor", {skip: !enabled}, async () => {
  localOnly();
  const prefix = "reliability-" + randomUUID();
  const owner = db.doc(`users/${prefix}-owner`);
  const newer = db.doc(`users/${prefix}-newer`);
  const older = db.doc(`users/${prefix}-older`);
  const logs = Array.from({length: 501}, (_, i) => db.doc(`legalAcceptanceLogs/${prefix}-${String(i).padStart(4, "0")}`));
  const request = (data: unknown) => ({data, auth: {uid: owner.id, token: {email_verified: true}}}) as any;
  try {
    await owner.set({globalRole: "owner", accountStatus: "active", createdAt: Timestamp.fromMillis(0), requiresMultiFactorAuth: true});
    await newer.set({createdAt: new Timestamp(1_800_000_000, 123456000)});
    await older.set({createdAt: new Timestamp(1_800_000_000, 123455000)});
    const first = await listLegalEvidenceAccounts.run(request({limit: 1}));
    assert.equal(first.accounts[0].userId, newer.id);
    const legacy = await listLegalEvidenceAccounts.run(request({limit: 1, cursor: {userId: newer.id, createdAt: first.nextCursor!.createdAt}}));
    assert.equal(legacy.accounts[0].userId, older.id);
    await newer.delete();
    const second = await listLegalEvidenceAccounts.run(request({limit: 1, cursor: first.nextCursor}));
    assert.equal(second.accounts[0].userId, older.id);
    for (let start = 0; start < logs.length; start += 250) {
      const batch = db.batch();
      logs.slice(start, start + 250).forEach((ref, i) => batch.set(ref, {
        userId: older.id, documentType: "terms", version: "test", acceptedAt: Timestamp.fromMillis(start + i + 1),
      }));
      await batch.commit();
    }
    const ids = new Set<string>();
    let cursor: string | null = null;
    do {
      const page = await getLegalEvidencePage.run(request({userId: older.id, limit: 100, cursor}));
      page.events.forEach(event => { assert.equal(ids.has(event.id), false); ids.add(event.id); });
      cursor = page.nextCursor;
    } while (cursor);
    assert.equal(ids.size, 501);
  } finally {
    for (const ref of [owner, newer, older, ...logs]) await ref.delete();
  }
});
