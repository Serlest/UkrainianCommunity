#!/usr/bin/env node
// Explicit project + confirmation for all writes. No profile source fields changed.
import {createRequire} from "node:module";
import {execFileSync} from "node:child_process";
import {initializeApp, applicationDefault} from "firebase-admin/app";
import {getFirestore, Firestore, FieldPath, FieldValue} from "firebase-admin/firestore";
import {OAuth2Client} from "google-auth-library";
const require = createRequire(import.meta.url);
const {buildAdminSearchGrams, adminSearchFields, adminSearchIndexField, adminSearchControlPath,
  normalizeAdminSearch, adminSearchAnchor, adminSearchDocuments, collectAdminSearch} = require("../lib/users/adminUserSearch.js");
const {reconcileAdminSearchUser} = require("../lib/users/adminUserSearchIndex.js");
const {userDocumentMatchesSearch} = require("../lib/users/userManagementQueries.js");
const args = process.argv.slice(2);
const project = args.find(arg => arg.startsWith("--project="))?.slice(10);
const apply = args.includes("--apply"), activate = args.includes("--activate"), disable = args.includes("--disable");
const confirm = args.find(arg => arg.startsWith("--confirm-project="))?.slice(18);
if (!project || !/^[a-z][a-z0-9-]{4,61}[a-z0-9]$/.test(project)
  || ((apply || activate || disable) && confirm !== project) || (disable && (apply || activate))
  || args.some(arg => !arg.startsWith("--project=") && !arg.startsWith("--confirm-project=")
    && !["--apply", "--activate", "--disable", "--gcloud"].includes(arg))) {
  throw new Error("Usage: --project=ID [--gcloud] [--apply] [--activate|--disable] --confirm-project=ID for writes. Default: read-only verification.");
}
if (process.env.FIRESTORE_EMULATOR_HOST && !project.startsWith("demo-")) throw new Error("Emulator requires a demo project.");
const credential = args.includes("--gcloud") ? {getAccessToken: async () => ({
  access_token: execFileSync("gcloud", ["auth", "print-access-token"], {encoding: "utf8"}).trim(), expires_in: 3000,
})} : applicationDefault();
let db;
if (args.includes("--gcloud")) {
  const authClient = new OAuth2Client();
  const token = await credential.getAccessToken();
  authClient.setCredentials({access_token: token.access_token, expiry_date: Date.now() + token.expires_in * 1000});
  db = new Firestore({projectId: project, authClient});
} else {
  db = getFirestore(initializeApp({projectId: project, credential}, "admin-search-migration"));
}
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const control = db.doc(adminSearchControlPath);
try {
  if (disable) {
    await control.set({ready: false, version: 1, disabledReason: "operator", disabledAt: FieldValue.serverTimestamp()}, {merge: true});
    console.log(JSON.stringify({mode: "disabled", ready: false}));
  } else {
    if (activate && !process.env.FIRESTORE_EMULATOR_HOST) {
      const token = await credential.getAccessToken();
      const response = await fetch(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/europe-west3/functions/maintainAdminUserSearchIndex`,
        {headers: {Authorization: `Bearer ${token.access_token}`}});
      if (!response.ok) throw new Error(`Cannot verify live index writer: HTTP ${response.status}`);
      const writer = await response.json();
      if (writer.state !== "ACTIVE" || writer.eventTrigger?.retryPolicy !== "RETRY_POLICY_RETRY"
        || writer.eventTrigger?.eventFilters?.find(f => f.attribute === "document")?.value !== "users/{userId}") {
        throw new Error("Index writer is not ACTIVE with retries and the required document filter.");
      }
    }
    const controlBefore = await control.get();
    const counts = {scanned: 0, mismatched: 0, written: 0};
    const queries = new Set(["zzzznotpresent", "a b"]);
    const stream = db.collection("users").orderBy(FieldPath.documentId()).select(...adminSearchFields, adminSearchIndexField).stream();
    try {
      for await (const user of stream) {
        counts.scanned++;
        const data = user.data();
        if (queries.size < 32) {
          for (const field of adminSearchFields) {
            if (typeof data[field] !== "string") continue;
            const value = normalizeAdminSearch(data[field]);
            if (value.length >= 2 && adminSearchAnchor(value)) queries.add(value);
          }
        }
        if (same(data[adminSearchIndexField], buildAdminSearchGrams(user.id, data))) continue;
        counts.mismatched++;
        if (apply && await reconcileAdminSearchUser(db, user.id)) counts.written++;
      }
    } finally { stream.destroy(); }
    // Activation always requires a separate clean pass; it can never follow a dirty scan.
    if (activate && counts.mismatched) throw new Error("Index scan has mismatches. Run backfill, then a separate --activate verification.");
    let queryChecks = 0;
    if (!counts.mismatched) {
      for (const query of queries) {
        const results = [];
        for (const mode of ["incomplete", "ready"]) {
          const result = await collectAdminSearch(adminSearchDocuments(db, query, adminSearchFields, mode),
            doc => userDocumentMatchesSearch(doc.id, doc.data(), query), 100);
          results.push({ids: result.items.map(doc => doc.id), count: result.totalMatches});
        }
        if (!same(results[0], results[1])) throw new Error("Indexed query differs from source search; retry after pending events settle. Activation refused.");
        queryChecks++;
      }
    }
    if (activate) {
      await db.runTransaction(async tx => {
        const current = await tx.get(control);
        if (!same(current.updateTime?.toJSON(), controlBefore.updateTime?.toJSON())) throw new Error("Control changed during verification; activation refused.");
        tx.set(control, {ready: true, version: 1, verifiedAt: FieldValue.serverTimestamp(),
          verifiedUsers: counts.scanned, verifiedQueries: queryChecks});
      });
    }
    const state = await control.get();
    console.log(JSON.stringify({mode: activate ? "activated" : apply ? "backfill" : "verify", ready: state.get("ready") === true,
      ...counts, queryChecks}));
    if (!apply && counts.mismatched > 0) process.exitCode = 2;
  }
} finally { await db.terminate(); }
