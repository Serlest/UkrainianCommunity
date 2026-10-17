#!/usr/bin/env node
import {readFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {NEWS_SCOPES} from "./newsScopeCoordination.mjs";

// Read-only evidence index. Flags request editorial examination, never a story,
// retry, publication quota, or a replacement for reading a rejected article.
export async function auditNewsWave(root, runId) {
  if (!/^news-\d{4}-\d{2}-\d{2}T\d{2}$/.test(runId)) throw new Error("Invalid wave run ID.");
  const read = async (path) => JSON.parse(await readFile(join(root, path), "utf8"));
  const snapshot = await read(`snapshots/${runId}.json`);
  const versions = new Set(snapshot.map((row) => row.sourcePolicyVersion ?? 1));
  if (versions.size !== 1) throw new Error("Missing or mixed snapshot source policy.");
  const version = [...versions][0];
  const registry = await read(`source-policies/v${version}.json`);
  const expected = new Set(registry.sources.filter((source) => source.active).map((source) => source.sourceId));
  const observed = new Set(snapshot.map((row) => row.sourceId));
  const scopes = [];
  for (const scope of NEWS_SCOPES) {
    let report;
    try { report = await read(`reports/${runId}/${scope}.json`); }
    catch (error) { if (error.code !== "ENOENT") throw error; scopes.push({scope, reportMissing: true}); continue; }
    const state = await read(`scopes/${scope}.json`);
    const batch = state.lastCandidateBatch?.runId === runId ? state.lastCandidateBatch : null;
    const decisions = Object.values(state.candidateDecisions ?? {}).filter((value) => value.runId === runId);
    const publications = [];
    for (const decision of decisions.filter((value) => value.outcome === "published")) {
      try {
        const receipt = JSON.parse(await readFile(decision.readbackReceiptPath, "utf8"));
        publications.push({contentId: decision.contentId, receiptPath: decision.readbackReceiptPath,
          verifiedReceipt: receipt.allVerified === true && receipt.contentId === decision.contentId});
      } catch (error) { publications.push({contentId: decision.contentId, verifiedReceipt: false, error: error.message}); }
    }
    const unverified = decisions.filter((value) => value.reason === "unverified").length;
    const reasons = Object.fromEntries([...new Set(decisions.map((value) => value.reason).filter(Boolean))]
      .map((reason) => [reason, decisions.filter((value) => value.reason === reason).length]));
    scopes.push({scope, reportedStatus: report.status, batch,
      evidenceLimits: {unverifiedCandidates: unverified, sourceErrors: report.sourceErrors ?? [],
        coverageErrors: report.coverageErrors ?? []},
      publications, rejectionReasons: reasons,
      reviewRejectionRationales: decisions.some((value) => value.reason === "no_practical_effect"),
      // Existing published duplicates retain their historic ID/run in the ledger.
      ledgerNote: "Earlier published duplicates remain under their original run; inspect this wave's report for duplicate rejections.",
    });
  }
  return {checkedAt: new Date().toISOString(), runId, role: "read_only_wave_evidence_audit",
    sourcePolicyVersion: version, snapshot: {expectedSources: expected.size, observedSources: snapshot.length,
      duplicateSourceIds: snapshot.length - observed.size,
      missingSourceIds: [...expected].filter((id) => !observed.has(id)),
      unexpectedSourceIds: [...observed].filter((id) => !expected.has(id)),
      errors: snapshot.filter((row) => row.error).map(({sourceId, error}) => ({sourceId, error})),
      emptySourceIds: snapshot.filter((row) => !row.links?.length).map((row) => row.sourceId)},
    completedReports: scopes.filter((item) => !item.reportMissing).length,
    publicationCountFromRetainedDecisions: scopes.flatMap((item) => item.publications ?? []).length,
    scopes, note: "Saved receipts are historical evidence, not fresh production read-back. Read current production, direct articles and rejected important topics before concluding QA. No mutation or editorial queue."};
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { console.log(JSON.stringify(await auditNewsWave(process.argv[2], process.argv[3]), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
