import {strict as assert} from "node:assert";
import {test, afterEach} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {acceptOrganizationRules} from "./organizationRulesAcceptance";
import {legalSHA256} from "./legalDocumentIntegrity";

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
const users: string[] = [], organizations: string[] = [];
function version() {
  const locales = Object.fromEntries(["de", "uk"].map(locale => {
    const contentMarkdown = "# Rules " + locale;
    return [locale, {title: locale, contentMarkdown, contentHash: legalSHA256(contentMarkdown)}];
  }));
  const contentHash = legalSHA256(Object.entries(locales).map(([locale, c]) => [locale, c.title, c.contentMarkdown, c.contentHash].join("\n")).join("\n---\n"));
  return {documentType: "organizationRules", status: "published", version: "2026.23", versionNumber: 202623,
    requiresAcceptance: true, defaultLocale: "de", canonicalLocale: "de", locales, contentHash};
}
async function seed() {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const uid = "org-ack-" + randomUUID(); users.push(uid);
  await db.doc(`users/${uid}`).set({globalRole: "user", accountStatus: "active", blockState: "active"});
  await seedCurrentLegalForIntegration(uid);
  await db.doc("legalDocuments/organizationRules").set({activeVersion: "2026.23", versionNumber: 202623, status: "published", requiresAcceptance: true});
  await db.doc("legalDocuments/organizationRules/versions/2026.23").set(version());
  return uid;
}
function request(uid: string, id: string, extra: Record<string, unknown> = {}) {
  return {auth: {uid, token: {email_verified: true}}, data: {organizationId: id, organizationName: "Isolated fixture", version: "2026.23", ...extra}} as any;
}
function organizationID() { const id = "org-proof-" + randomUUID(); organizations.push(id); return id; }
afterEach(async () => {
  if (!enabled) return;
  for (const uid of users.splice(0)) {
    const logs = await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get();
    await Promise.all(logs.docs.map(d => d.ref.delete())); await db.doc(`users/${uid}`).delete();
  }
  for (const id of organizations.splice(0)) { await db.doc(`organizationCreationProofs/${id}`).delete(); await db.doc(`organizations/${id}`).delete(); }
});
test("organization-bound retries reuse one exact receipt and response timestamp", {skip: !enabled}, async () => {
  const uid = await seed(), id = organizationID();
  const first = await acceptOrganizationRules.run(request(uid, id));
  const replies = await Promise.all([acceptOrganizationRules.run(request(uid, id)), acceptOrganizationRules.run(request(uid, id))]);
  const proof = await db.doc(`organizationCreationProofs/${id}`).get();
  assert.equal(first.acceptedAt, proof.get("acceptedAt").toDate().toISOString());
  assert.ok(replies.every(reply => reply.acceptedAt === first.acceptedAt));
  const logs = await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get();
  assert.equal(logs.size, 1); assert.equal(logs.docs[0].get("organizationId"), id);
});
test("another account cannot replace a reserved organization proof even after expiry", {skip: !enabled}, async () => {
  const first = await seed(), other = await seed(), id = organizationID();
  await acceptOrganizationRules.run(request(first, id));
  const proof = db.doc(`organizationCreationProofs/${id}`), original = (await proof.get()).data();
  await assert.rejects(acceptOrganizationRules.run(request(other, id)), {code: "permission-denied"});
  assert.deepEqual((await proof.get()).data(), original);
  await proof.update({expiresAt: Timestamp.fromMillis(1)});
  await assert.rejects(acceptOrganizationRules.run(request(other, id)), {code: "permission-denied"});
});
test("organization rules require a complete immutable published version", {skip: !enabled}, async () => {
  const uid = await seed(), id = organizationID();
  for (const patch of [{contentHash: null}, {documentType: "terms"}, {status: "draft"}, {locales: {}}]) {
    await db.doc("legalDocuments/organizationRules/versions/2026.23").set({...version(), ...patch});
    await assert.rejects(acceptOrganizationRules.run(request(uid, id)), {code: "failed-precondition"});
  }
  assert.equal((await db.doc(`organizationCreationProofs/${id}`).get()).exists, false);
});
test("organization proof preserves verified active access, request limit and same-owner renewal", {skip: !enabled}, async () => {
  const uid = await seed(), id = organizationID();
  const unverified = request(uid, id); unverified.auth.token.email_verified = false;
  await assert.rejects(acceptOrganizationRules.run(unverified), {code: "permission-denied"});
  await db.doc(`users/${uid}`).update({accountStatus: "bannedPermanent"});
  await assert.rejects(acceptOrganizationRules.run(request(uid, id)), {code: "permission-denied"});
  await db.doc(`users/${uid}`).update({accountStatus: "active", globalRole: "owner", requiresMultiFactorAuth: true});
  await assert.rejects(acceptOrganizationRules.run(request(uid, id)), {code: "failed-precondition"});
  const protectedOwner = request(uid, id); protectedOwner.auth.token.firebase = {sign_in_second_factor: "totp"};
  await acceptOrganizationRules.run(protectedOwner);
  await db.doc(`users/${uid}`).update({globalRole: "user", requiresMultiFactorAuth: false});
  for (let i = 0; i < 3; i++) { const existing = organizationID(); await db.doc(`organizations/${existing}`).set({submittedByUserId: uid, moderationStatus: "pendingReview"}); }
  await assert.rejects(acceptOrganizationRules.run(request(uid, id)), {code: "resource-exhausted"});
  await db.doc(`organizations/${organizations.at(-1)}`).delete();
  await acceptOrganizationRules.run(request(uid, id));
  await db.doc(`organizationCreationProofs/${id}`).update({expiresAt: Timestamp.fromMillis(1)});
  await acceptOrganizationRules.run(request(uid, id));
  assert.equal((await db.collection("legalAcceptanceLogs").where("userId", "==", uid).get()).size, 2);
});
