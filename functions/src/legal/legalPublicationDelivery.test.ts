import {strict as assert} from "node:assert";
import {test} from "node:test";
import {adminAuth, db} from "../firebase/admin";
import {deliverLegalPublicationPage, queueLegalPublication} from "./legalPublicationDelivery";

test("legal publication resumes after 100 accounts, retries safely and ignores superseded versions", {
  skip: !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST,
}, async () => {
  const ids = Array.from({length: 103}, (_, i) => `legal-page-${String(i).padStart(3, "0")}`);
  await Promise.all(ids.map(async uid => {
    await adminAuth.createUser({uid, email: `${uid}@example.com`, emailVerified: true});
    await db.doc(`users/${uid}`).set({globalRole: "user", accountStatus: "active"});
  }));
  await db.doc("legalDocuments/terms").set({activeVersion: "2026.50"});
  await queueLegalPublication("terms", {activeVersion: "2026.50", requiresAcceptance: true});
  await queueLegalPublication("terms", {activeVersion: "2026.50", requiresAcceptance: true});
  await deliverLegalPublicationPage("terms_2026.50", 0);
  const job = db.doc("legalPublicationDelivery/terms_2026.50");
  assert.equal((await job.get()).get("complete"), false);
  const first = await db.collectionGroup("notificationInbox").where("type", "==", "legalDocumentsUpdated").get();
  assert.equal(first.size, 100);
  await deliverLegalPublicationPage("terms_2026.50", 0);
  assert.equal((await job.get()).get("sequence"), 1);
  await deliverLegalPublicationPage("terms_2026.50", 1);
  assert.equal((await job.get()).get("complete"), true);
  assert.equal((await db.collectionGroup("notificationInbox").where("type", "==", "legalDocumentsUpdated").get()).size, 103);
  await queueLegalPublication("terms", {activeVersion: "2026.49"});
  await deliverLegalPublicationPage("terms_2026.49", 0);
  assert.equal((await db.doc("legalPublicationDelivery/terms_2026.49").get()).get("superseded"), true);
});
