import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  parseLegalEvidenceAccountRequest,
  parseLegalEvidenceLimit,
  parseLegalEvidenceUserRequest,
} from "./legalEvidence";

test("legal evidence list uses a bounded owner-screen page", () => {
  assert.equal(parseLegalEvidenceLimit(undefined), 100);
  assert.equal(parseLegalEvidenceLimit({}), 100);
  assert.equal(parseLegalEvidenceLimit({limit: 1}), 1);
  assert.equal(parseLegalEvidenceLimit({limit: 200}), 200);
});

test("legal evidence list rejects malformed and unbounded limits", () => {
  assert.throws(() => parseLegalEvidenceLimit("100"));
  assert.throws(() => parseLegalEvidenceLimit({limit: 0}));
  assert.throws(() => parseLegalEvidenceLimit({limit: 201}));
  assert.throws(() => parseLegalEvidenceLimit({limit: 10.5}));
});

test("legal evidence account list supports browsing, search, and a stable cursor", () => {
  assert.deepEqual(parseLegalEvidenceAccountRequest(undefined), {
    query: null,
    limit: 50,
    cursor: null,
  });
  assert.deepEqual(parseLegalEvidenceAccountRequest({query: "  philipp  ", limit: 25}), {
    query: "philipp",
    limit: 25,
    cursor: null,
  });
  assert.deepEqual(parseLegalEvidenceAccountRequest({
    limit: 50,
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  }), {
    query: null,
    limit: 50,
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  });
});

test("legal evidence account requests reject ambiguous searches and invalid users", () => {
  assert.throws(() => parseLegalEvidenceAccountRequest({query: "x"}));
  assert.throws(() => parseLegalEvidenceAccountRequest({limit: 101}));
  assert.throws(() => parseLegalEvidenceAccountRequest({
    query: "user",
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  }));
  assert.equal(parseLegalEvidenceUserRequest({userId: " user-1 "}), "user-1");
  assert.throws(() => parseLegalEvidenceUserRequest({userId: "bad/id"}));
});

import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {getLegalEvidencePage, listLegalEvidenceAccounts} from "./legalEvidence";
const integrationEnabled = !!process.env.FIRESTORE_EMULATOR_HOST;

test("paged history merges receipts chronologically, removes profile duplicates and binds filters", {skip: !integrationEnabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const uid = "evidence-" + randomUUID(), owner = "owner-" + randomUUID();
  const refs = [db.doc(`users/${owner}`), db.doc(`users/${uid}`)];
  const request = (data: unknown) => ({data, auth: {uid: owner, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}}}) as any;
  try {
    await refs[0].set({globalRole: "owner", accountStatus: "active", requiresMultiFactorAuth: true});
    await refs[1].set({createdAt: Timestamp.fromMillis(1), displayName: "Selected Account",
      acceptedTermsAt: Timestamp.fromMillis(200), acceptedTermsVersion: "2026.13",
      acceptedPrivacyAt: Timestamp.fromMillis(150), acceptedPrivacyVersion: "2026.13",
      minimumAgeConfirmedAt: Timestamp.fromMillis(100)});
    await seedCurrentLegalForIntegration(owner);
    const legal = db.doc(`legalAcceptanceLogs/${uid}-legal`); refs.push(legal);
    await legal.set({userId: uid, documentType: "terms", version: "2026.13", acceptedAt: Timestamp.fromMillis(200), contentHash: "hash", locale: "de"});
    for (let i = 0; i < 63; i++) {
      const ref = db.doc(`analyticsConsentReceipts/${uid}-${String(i).padStart(3, "0")}`); refs.push(ref);
      await ref.set({userId: uid, grantedAt: new Timestamp(2 + i, i), withdrawnAt: i % 2 ? new Timestamp(3 + i, i) : null,
        privacyVersion: "2026.13", disclosureText: "Explicit analytics consent", enabled: i % 2 === 0});
    }
    const state = db.doc(`analyticsConsentStates/${uid}`);refs.push(state);
    await state.set({enabled: false, withdrawnAt: Timestamp.fromMillis(65000), privacyVersion: "2026.13"});
    const legacy = await getLegalEvidencePage.run(request({userId: uid}));
    assert.equal(legacy.events.some(event => event.eventType === "termsAccepted"), false);
    assert.equal(legacy.events.find(event => event.eventType === "privacyAcknowledged")?.source, "profileSnapshot");
    let cursor: string | null = null;
    const events: any[] = [];
    let pageCount = 0;
    do {
      assert.ok(++pageCount <= 100, "History cursor must finish");
      const page = await getLegalEvidencePage.run(request({userId: uid, format: 2, limit: 7, cursor}));
      assert.ok(page.events.length <= 7);
      if (!cursor && "summary" in page) assert.equal(page.summary?.find(item => item.kind === "analytics")?.state, "withdrawn");
      events.push(...page.events); cursor = page.nextCursor;
    } while (cursor);
    assert.equal(events.length, 63 + 31 + 3);
    assert.equal(new Set(events.map(event => event.id)).size, events.length);
    assert.equal(events.filter(event => event.eventType === "termsAccepted").length, 1);
    assert.deepEqual(events.map(event => event.occurredAt), events.map(event => event.occurredAt).sort().reverse());
    const first = await getLegalEvidencePage.run(request({userId: uid, format: 2, limit: 2, filter: "terms", query: "2026.13"}));
    assert.ok(first.nextCursor);
    await assert.rejects(getLegalEvidencePage.run(request({userId: uid, format: 2, cursor: first.nextCursor, filter: "privacy", query: "2026.13"})), {code: "invalid-argument"});
    let next: string | null = first.nextCursor;
    const terms = [...first.events];
    pageCount = 0;
    while (next) {
      assert.ok(++pageCount <= 100, "Filtered history cursor must finish");
      const page = await getLegalEvidencePage.run(request({userId: uid, format: 2, limit: 7, cursor: next, filter: "terms", query: "2026.13"}));
      terms.push(...page.events); next = page.nextCursor;
    }
    assert.equal(terms.length, 1);
    await assert.rejects(getLegalEvidencePage.run({auth: {uid, token: {email_verified: true}}, data: {userId: uid, format: 2}} as any));
  } finally {await Promise.all(refs.map(ref => ref.delete()));}
});

test("account search can continue beyond fifty matches without duplicate accounts", {skip: !integrationEnabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const owner = "owner-" + randomUUID(), tag = "search" + randomUUID().replaceAll("-", "");
  const refs = [db.doc(`users/${owner}`)];
  const request = (data: unknown) => ({data, auth: {uid: owner, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}}}) as any;
  try {
    await refs[0].set({globalRole: "owner", accountStatus: "active", requiresMultiFactorAuth: true});
    await seedCurrentLegalForIntegration(owner);
    for (let i = 0; i < 61; i++) {
      const ref = db.doc(`users/${tag}-${i}`); refs.push(ref);
      await ref.set({displayName: tag, createdAt: Timestamp.fromMillis(i)});
    }
    const first = await listLegalEvidenceAccounts.run(request({query: tag, limit: 50}));
    assert.equal(first.accounts.length, 50); assert.ok(first.nextCursor);
    const second = await listLegalEvidenceAccounts.run(request({query: tag, limit: 50, cursor: first.nextCursor}));
    assert.equal(second.accounts.length, 11); assert.equal(second.nextCursor, null);
    assert.equal(new Set([...first.accounts, ...second.accounts].map(account => account.userId)).size, 61);
    await assert.rejects(listLegalEvidenceAccounts.run(request({query: "other", cursor: first.nextCursor})), {code: "invalid-argument"});
  } finally {await Promise.all(refs.map(ref => ref.delete()));}
});
