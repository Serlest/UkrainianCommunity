import {strict as assert} from "node:assert";
import {test, afterEach} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {acceptLegalDocument} from "./legalDocuments";
import {hasValidPublishedLegalContent, legalSHA256} from "./legalDocumentIntegrity";

function document(type: "terms" | "privacy" = "terms") {
  const locales = Object.fromEntries(["de", "uk"].map(locale => {
    const contentMarkdown = "# " + locale + "\n\n" + "Explicit legal document " + locale;
    return [locale, {title: locale, contentMarkdown, contentHash: legalSHA256(contentMarkdown)}];
  }));
  const contentHash = legalSHA256(Object.entries(locales).map(([locale, content]) =>
    [locale, content.title, content.contentMarkdown, content.contentHash].join("\n")).join("\n---\n"));
  return {documentType: type, version: "2026.23", versionNumber: 202623, status: "published",
    defaultLocale: "de", canonicalLocale: "de", locales, contentHash};
}
const pointer = {activeVersion: "2026.23", versionNumber: 202623, status: "published"};
test("legal integrity accepts current and historical seed hashes, rejects missing and changed text", () => {
  const current = document();
  assert.ok(hasValidPublishedLegalContent("terms", "2026.23", pointer, current));
  const legacy = {...current, contentHash: legalSHA256(Object.entries(current.locales).map(([locale, content]) =>
    [locale, content.title, content.contentMarkdown, "", content.contentHash].join("\n")).join("\n---\n"))};
  assert.ok(hasValidPublishedLegalContent("terms", "2026.23", pointer, legacy));
  assert.equal(hasValidPublishedLegalContent("terms", "2026.23", pointer, {...current, contentHash: null}), false);
  assert.equal(hasValidPublishedLegalContent("privacy", "2026.23", pointer, current), false);
  current.locales.de.contentMarkdown += " tampered";
  assert.equal(hasValidPublishedLegalContent("terms", "2026.23", pointer, current), false);
});

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
const createdUIDs: string[] = [];
afterEach(async () => {
  if (!enabled) return;
  for (const uid of createdUIDs.splice(0)) {
    const records = await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get();
    await Promise.all(records.docs.map(record => record.ref.delete()));
    await db.doc(`users/${uid}`).delete();
  }
});
function request(uid: string, data: Record<string, unknown> = {}) {
  return {auth: {uid, token: {email_verified: true}}, data: {documentType: "terms", version: "2026.23", ...data}} as any;
}
async function seed() {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const uid = "ack-test-" + randomUUID(); createdUIDs.push(uid);
  await db.doc(`users/${uid}`).set({globalRole: "user", accountStatus: "active", blockState: "active"});
  await db.doc("legalDocuments/terms").set(pointer);
  await db.doc("legalDocuments/terms/versions/2026.23").set(document());
  return uid;
}

test("repeated and concurrent old-format acknowledgements create exactly one immutable receipt", {skip: !enabled}, async () => {
  const uid = await seed();
  const first = await acceptLegalDocument.run(request(uid));
  const replies = await Promise.all([acceptLegalDocument.run(request(uid)), acceptLegalDocument.run(request(uid))]);
  assert.ok(replies.every(reply => reply.acceptedAt === first.acceptedAt));
  const receipts = await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get();
  assert.equal(receipts.size, 1);
  assert.equal(receipts.docs[0].get("acceptedAt").toDate().toISOString(), first.acceptedAt);
  assert.equal((await db.doc(`users/${uid}`).get()).get("acceptedTermsAt").toDate().toISOString(), first.acceptedAt);
});
test("initial and legacy random-ID receipts are reused without rewriting their recorded data", {skip: !enabled}, async () => {
  for (const idKind of ["initial", "random"]) {
    const uid = await seed(), id = idKind === "initial" ? `${uid}_terms_2026.23` : randomUUID();
    const ref = db.doc(`legalAcceptanceLogs/${id}`), date = Timestamp.fromMillis(1700000000000);
    const value = {userId: uid, documentType: "terms", version: "2026.23", contentHash: document().contentHash,
      acceptedAt: date, locale: "de", historicalMarker: "preserve"};
    await ref.set(value);
    const result = await acceptLegalDocument.run(request(uid, {locale: "uk"}));
    assert.equal(result.acceptedAt, date.toDate().toISOString());
    assert.deepEqual((await ref.get()).data(), value);
    assert.equal((await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get()).size, 1);
  }
});
test("new exact reaffirmation preserves older incomplete receipts", {skip: !enabled}, async () => {
  const uid = await seed(), legacy = db.doc(`legalAcceptanceLogs/old_${uid}`);
  await legacy.set({userId: uid, documentType: "terms", version: "2026.23", acceptedAt: Timestamp.fromMillis(1), contentHash: null});
  await acceptLegalDocument.run(request(uid)); await acceptLegalDocument.run(request(uid));
  const snapshot = await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get();
  assert.equal(snapshot.size, 2); assert.equal((await legacy.get()).get("contentHash"), null);
  assert.equal(snapshot.docs.filter(doc => doc.get("contentHash") === document().contentHash).length, 1);
});
test("unpublished, mismatched and corrupted active versions cannot create evidence or update profile", {skip: !enabled}, async () => {
  const uid = await seed(), version = db.doc("legalDocuments/terms/versions/2026.23");
  for (const change of [{contentHash: null}, {documentType: "privacy"}, {versionNumber: 202624}, {status: "draft"}]) {
    await version.set({...document(), ...change});
    await assert.rejects(acceptLegalDocument.run(request(uid)), {code: "failed-precondition"});
  }
  assert.equal((await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get()).size, 0);
  assert.equal((await db.doc(`users/${uid}`).get()).get("acceptedTermsVersion"), undefined);
});
test("stale versions, unverified, blocked and MFA-incomplete principals remain denied", {skip: !enabled}, async () => {
  const uid = await seed();
  await assert.rejects(acceptLegalDocument.run({data: {documentType: "terms", version: "2026.23"}} as any), {code: "unauthenticated"});
  const unverified = request(uid); unverified.auth.token.email_verified = false;
  await assert.rejects(acceptLegalDocument.run(unverified), {code: "permission-denied"});
  await db.doc(`users/${uid}`).update({accountStatus: "bannedPermanent"});
  await assert.rejects(acceptLegalDocument.run(request(uid)), {code: "permission-denied"});
  await db.doc(`users/${uid}`).update({accountStatus: "active", globalRole: "owner", requiresMultiFactorAuth: true});
  await assert.rejects(acceptLegalDocument.run(request(uid)), {code: "failed-precondition"});
  await db.doc(`users/${uid}`).update({globalRole: "user", requiresMultiFactorAuth: false});
  await assert.rejects(acceptLegalDocument.run(request(uid, {version: "2026.22"})), {code: "failed-precondition"});
  assert.equal((await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get()).size, 0);
});
