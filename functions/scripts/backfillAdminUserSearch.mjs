#!/usr/bin/env node
// Prepared migration only. No activation, deployment, or implicit project selection.
import {createRequire} from "node:module";
import {initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, FieldPath} from "firebase-admin/firestore";
const require = createRequire(import.meta.url);
const {buildAdminSearchGrams, adminSearchFields, adminSearchIndexField} =
  require("../lib/users/adminUserSearch.js");

const args = process.argv.slice(2);
const project = args.find(arg => arg.startsWith("--project="))?.slice(10);
const apply = args.includes("--apply");
const confirm = args.find(arg => arg.startsWith("--confirm-project="))?.slice(18);
if (!project || !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(project)
  || (apply && confirm !== project)
  || args.some(arg => !arg.startsWith("--project=") && !arg.startsWith("--confirm-project=") && arg !== "--apply")) {
  throw new Error("Usage: --project=ID [--apply --confirm-project=ID]. Default is read-only verification.");
}
const app = initializeApp({projectId: project, credential: applicationDefault()});
const db = getFirestore(app);
const counts = {scanned: 0, mismatched: 0, written: 0, concurrentlyDeleted: 0};
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
// Stream every user; never cap verification/backfill at one page. No identities in logs.
const stream = db.collection("users").orderBy(FieldPath.documentId())
  .select(...adminSearchFields, adminSearchIndexField).stream();
try {
  for await (const user of stream) {
    counts.scanned++;
    const data = user.data();
    if (same(data[adminSearchIndexField], buildAdminSearchGrams(user.id, data))) continue;
    counts.mismatched++;
    if (!apply) continue;
    const result = await db.runTransaction(async transaction => {
      // Read the CURRENT profile inside the write transaction; never overwrite a
      // newer index from the earlier scan snapshot. No source fields are changed.
      const fresh = await transaction.get(user.ref);
      if (!fresh.exists) return "concurrentlyDeleted";
      const current = fresh.data();
      const grams = buildAdminSearchGrams(fresh.id, current);
      if (same(current[adminSearchIndexField], grams)) return null;
      transaction.update(fresh.ref, {[adminSearchIndexField]: grams});
      return "written";
    });
    if (result) counts[result]++;
  }
} finally {
  stream.destroy();
  await db.terminate();
}
console.log(JSON.stringify({mode: apply ? "backfill" : "verify", readiness: "incomplete", ...counts}));
// Even a clean scan does NOT establish atomic maintenance or mark an index ready.
if (!apply && counts.mismatched > 0) process.exitCode = 2;
