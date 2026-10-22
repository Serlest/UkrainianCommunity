import {execFileSync} from "node:child_process";
import {OAuth2Client} from "google-auth-library";
import {initializeApp} from "firebase-admin/app";
import {Firestore, FieldPath, FieldValue} from "firebase-admin/firestore";
const project = process.argv.find(v => v.startsWith("--project="))?.slice(10);
const apply = process.argv.includes("--apply");
if (!project) throw new Error("Use --project=<id>. Dry run by default; --apply updates only derived search fields.");
initializeApp({projectId: project});
let authClient;
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  authClient = new OAuth2Client();
  authClient.setCredentials({access_token: execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8", stdio: ["ignore", "pipe", "pipe"]}).trim(), expiry_date: Date.now() + 3000000});
}
const db = new Firestore({projectId: project, ...(authClient ? {authClient} : {})});
const {buildJournalGrams, journalIndexField, journalIndexState, reconcileJournalIndex, queryJournal} = await import("../lib/systemLogs/journalQuery.js");
let after, scanned = 0;
if (apply) await db.doc(journalIndexState).set({ready: false, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
while (true) {
  let q = db.collection("systemLogs").orderBy(FieldPath.documentId()).limit(100);
  if (after) q = q.startAfter(after);
  const page = await q.get();
  for (const doc of page.docs) { if (apply) await reconcileJournalIndex(db, doc.id); scanned++; }
  if (page.size < 100) break;
  after = page.docs.at(-1);
}
let verified = false;
if (apply) {
  await db.runTransaction(async tx => {
    const docs = await tx.get(db.collection("systemLogs"));
    for (const doc of docs.docs) {
      if (JSON.stringify(doc.get(journalIndexField)) !== JSON.stringify(buildJournalGrams(doc.id, doc.data()))) throw new Error("Source changed during verification; rerun backfill.");
    }
    tx.set(db.doc(journalIndexState), {ready: true, version: 1, verifiedAt: FieldValue.serverTimestamp()}, {merge: true});
  });
  try {
    // Actually execute every composite query shape before leaving the switch enabled.
    for (const role of ["owner", "admin"]) for (const sort of ["newestFirst", "oldestFirst", "severityHighToLow", "severityLowToHigh", "category"])
      await queryJournal("migration-verifier", role, {sort, filter: {searchText: "verification"}}, db);
    verified = true;
  } catch (error) {
    await db.doc(journalIndexState).set({ready: false, reason: "query-verification-failed"}, {merge: true});
    throw error;
  }
}
console.log(JSON.stringify({project, apply, scanned, verified}));
