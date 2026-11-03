#!/usr/bin/env node
import {readFile} from "node:fs/promises";
import {dirname, join, resolve} from "node:path";
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
    const currentBatch = state.lastCandidateBatch?.runId === runId ? state.lastCandidateBatch : null;
    const retainedDecisions = Object.values(state.candidateDecisions ?? {}).filter((value) => value.runId === runId);
    // `lastCandidateBatch` is a mutable checkpoint and is replaced by the next
    // pass. Closed per-wave reports are immutable, so use their explicit
    // terminal counts when auditing an older wave.
    const isTerminalDecisionList = (entries) => Array.isArray(entries) && entries.length > 0 &&
      entries.every((entry) => entry.outcome === "published" || entry.outcome === "rejected");
    // `decisions` is the closed decision ledger. Some newer scope reports also
    // put terminal outcomes on `openedArticles`, but those entries can be only
    // lead summaries and omit publication IDs and read-back paths.
    const openedArticleDecisions = Array.isArray(report.openedArticles)
      ? report.openedArticles.map((entry) => entry.decision && typeof entry.decision === "object"
        ? {...entry, ...entry.decision, url: entry.decision.url ?? entry.url}
        : entry)
      : null;
    const reportDecisionEntries = isTerminalDecisionList(report.decisions) ? report.decisions
      : isTerminalDecisionList(report.openedArticles) ? report.openedArticles
        : isTerminalDecisionList(openedArticleDecisions) ? openedArticleDecisions
          : isTerminalDecisionList(report.decidedCandidates) ? report.decidedCandidates : null;
    const explicitTerminalCounts = (report.candidateDecisionsComplete === true || report.candidateBatchClosed === true) &&
      Number.isInteger(report.decidedCandidates) && Number.isInteger(report.published) &&
      Number.isInteger(report.rejected);
    // Salzburg's immutable report schema records a terminal `decisions` list
    // and `workflowComplete`, while the mutable scope checkpoint can already
    // have advanced to a later emergency batch. Derive counts from that closed
    // list instead of treating the overwritten checkpoint as missing closure.
    const derivedTerminalCounts = report.workflowComplete === true &&
      Array.isArray(report.decisions) && report.decisions.length > 0 &&
      report.decisions.every((entry) => entry.outcome === "published" || entry.outcome === "rejected");
    // Tirol's closed partial reports use a parallel candidates/decisions
    // schema. `completedAt` plus released locks and explicit no-draft/no-queue
    // fields prove the executor reached terminal closure even when source
    // coverage remains partial and `workflowComplete` is absent.
    const derivedClosedCandidateDecisionList = report.completedAt && report.locksReleased === true &&
      report.draftsCreated === 0 && report.queueCreated === false &&
      Array.isArray(report.candidates) && report.candidates.length > 0 &&
      isTerminalDecisionList(report.decisions) && report.candidates.length === report.decisions.length &&
      report.candidates.every((candidate, index) => candidate.url === report.decisions[index].url);
    const derivedCandidateCounts = isTerminalDecisionList(report.decidedCandidates);
    const derivedEntries = derivedTerminalCounts || derivedClosedCandidateDecisionList
      ? report.decisions : derivedCandidateCounts ? report.decidedCandidates : null;
    const reportHasTerminalCounts = explicitTerminalCounts || derivedTerminalCounts || derivedClosedCandidateDecisionList || derivedCandidateCounts;
    const terminalCandidates = explicitTerminalCounts ? report.decidedCandidates : derivedEntries?.length ?? 0;
    const terminalPublished = explicitTerminalCounts ? report.published : derivedEntries?.filter((entry) => entry.outcome === "published").length ?? 0;
    const terminalRejected = explicitTerminalCounts ? report.rejected : derivedEntries?.filter((entry) => entry.outcome === "rejected").length ?? 0;
    const reportBatch = reportHasTerminalCounts ? {
      runId, candidateDecisionsComplete: true, candidates: terminalCandidates,
      published: terminalPublished, rejected: terminalRejected,
    } : null;
    // Executors keep immutable terminal batches in several schemas and
    // locations. Prefer report-referenced paths, then canonical per-wave
    // artifacts; a later pass may already have replaced the mutable checkpoint.
    const artifactPaths = new Set([
      join(root, `artifacts/${runId}/${scope}/candidate-batch.json`),
      join(root, `artifacts/${runId}/${scope}/decision-batch.json`),
      join(root, `artifacts/${runId}/${scope}/decisions.json`),
    ]);
    if (typeof report.batchPath === "string") artifactPaths.add(resolve(report.batchPath));
    if (typeof report.artifacts === "string") {
      for (const name of ["candidate-batch.json", "decision-batch.json", "decisions.json"])
        artifactPaths.add(join(resolve(report.artifacts), name));
    }
    const releasePath = report.locks?.releasePath ?? report.locks?.release ?? report.locks?.releaseReceiptPath ?? report.locks?.releaseArtifact;
    let reportLockReleased = report.locksReleased === true || report.locks?.released === true;
    if (typeof releasePath === "string") {
      try {
        const release = JSON.parse(await readFile(resolve(releasePath), "utf8"));
        reportLockReleased ||= release.released === true;
      } catch (error) { if (error.code !== "ENOENT") throw error; }
    }
    const reportClosed = Boolean(report.completedAt || report.reportedAt || report.closedAt) && reportLockReleased;
    let artifactBatch = null;
    for (const artifactPath of artifactPaths) {
      if (artifactBatch) break;
      try {
        const closedBatch = JSON.parse(await readFile(artifactPath, "utf8"));
        const entries = closedBatch.decisions;
        const candidateCount = Array.isArray(closedBatch.candidates) ? closedBatch.candidates.length : closedBatch.candidates;
        const validEntries = Array.isArray(entries) && entries.length > 0 &&
          entries.every((entry) => entry.outcome === "published" || entry.outcome === "rejected");
        if ((closedBatch.scope ?? report.scope) !== scope || (closedBatch.runId ?? report.runId) !== runId ||
            !validEntries || !Number.isInteger(candidateCount) || candidateCount !== entries.length) continue;
        let receiptValid = false;
        for (const receiptPath of [join(dirname(artifactPath), "decision-receipt.json"),
          join(dirname(artifactPath), "receipt.json")]) {
          try {
            const closeReceipt = JSON.parse(await readFile(receiptPath, "utf8"));
            const published = entries.filter((entry) => entry.outcome === "published").length;
            const rejected = entries.filter((entry) => entry.outcome === "rejected").length;
            if (closeReceipt.runId === runId && closeReceipt.candidateDecisionsComplete === true &&
                closeReceipt.candidates === entries.length && closeReceipt.published === published &&
                closeReceipt.rejected === rejected) receiptValid = true;
          } catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        if (!receiptValid && !reportClosed) continue;
        if (Number.isInteger(report.decidedCandidates) && report.decidedCandidates !== entries.length) continue;
        const published = entries.filter((entry) => entry.outcome === "published").length;
        const rejected = entries.filter((entry) => entry.outcome === "rejected").length;
        artifactBatch = {batch: {runId, candidateDecisionsComplete: true, candidates: entries.length,
          published, rejected}, entries, path: artifactPath};
      } catch (error) { if (error.code !== "ENOENT") throw error; }
    }
    const batch = reportBatch ?? artifactBatch?.batch ?? currentBatch ?? null;
    const reportEntries = reportDecisionEntries ?? artifactBatch?.entries ?? null;
    const reportHasCompleteDecisionList = Boolean(batch) && Array.isArray(reportEntries) &&
      reportEntries.length === batch.candidates &&
      reportEntries.every((entry) => entry.outcome === "published" || entry.outcome === "rejected");
    // Any rejection for a URL that was already published preserves the first
    // publication's ledger entry, regardless of the new rejection reason.
    // Count that closed decision as reconciled when the content ID or URL still
    // exists as a published entry in mutable scope state.
    const canonicalUrl = (value) => typeof value === "string" ? value.replace(/\/$/, "") : value;
    const closedAtMs = Date.parse(report.completedAt ?? report.reportedAt ?? report.closedAt ?? "");
    const preservedEarlierPublishedDecisions = reportHasCompleteDecisionList
      ? reportEntries.filter((entry) => entry.outcome === "rejected" &&
        Object.entries(state.candidateDecisions ?? {}).some(([key, value]) => value.runId !== runId &&
          value.outcome === "published" && ((entry.contentId && value.contentId === entry.contentId) ||
            canonicalUrl(value.url ?? key) === canonicalUrl(entry.url)))).length
      : 0;
    const supersededByLaterRun = reportHasCompleteDecisionList && Number.isFinite(closedAtMs)
      ? reportEntries.filter((entry) => Object.entries(state.candidateDecisions ?? {}).some(([key, value]) =>
        value.runId !== runId && value.outcome && canonicalUrl(value.url ?? key) === canonicalUrl(entry.url) &&
        Date.parse(value.decidedAt ?? "") > closedAtMs)).length
      : 0;
    // Prefer the immutable per-wave decision list when it is demonstrably
    // complete. The scope ledger is keyed by URL and later waves may replace
    // an earlier terminal outcome for the same URL.
    const decisions = reportHasCompleteDecisionList ? reportEntries.map((entry) => {
      const retained = state.candidateDecisions?.[entry.url] ??
        Object.values(state.candidateDecisions ?? {}).find((value) =>
          value.runId === runId && entry.contentId && value.contentId === entry.contentId);
      const retainedReceiptPath = retained?.contentId && retained.contentId === entry.contentId
        ? retained.readbackReceiptPath : undefined;
      return {...retained, ...entry, runId,
        readbackReceiptPath: retainedReceiptPath ?? entry.readbackReceiptPath ?? entry.productionReadback?.receiptPath};
    }) : retainedDecisions;
    const publications = [];
    for (const decision of decisions.filter((value) => value.outcome === "published")) {
      try {
        const receipt = JSON.parse(await readFile(decision.readbackReceiptPath, "utf8"));
        publications.push({contentId: decision.contentId, receiptPath: decision.readbackReceiptPath,
          manifestPath: decision.manifestPath, editorialReceiptPath: decision.editorialReceiptPath,
          verifiedReceipt: receipt.allVerified === true && receipt.contentId === decision.contentId});
      } catch (error) { publications.push({contentId: decision.contentId, verifiedReceipt: false, error: error.message}); }
    }
    const unverified = decisions.filter((value) => value.reason === "unverified").length;
    const reasons = Object.fromEntries([...new Set(decisions.map((value) => value.reason).filter(Boolean))]
      .map((reason) => [reason, decisions.filter((value) => value.reason === reason).length]));
    scopes.push({scope, reportedStatus: report.status, batch,
      batchSource: reportBatch ? "closed_report" : artifactBatch ? "closed_artifact" : currentBatch ? "scope_state" : null,
      decisionLedger: batch ? {
        reportedCandidates: batch.candidates,
        retainedDecisionsForWave: retainedDecisions.length,
        retainedDecisionCountMatches: retainedDecisions.length === batch.candidates,
        preservedEarlierPublishedDecisions,
        supersededByLaterRun,
        retainedDecisionCountReconciled: retainedDecisions.length + preservedEarlierPublishedDecisions + supersededByLaterRun === batch.candidates,
        decisionsReadFrom: reportHasCompleteDecisionList
          ? (artifactBatch && !reportDecisionEntries ? "closed_artifact" : "closed_report")
          : "scope_state",
      } : undefined,
      evidenceLimits: {unverifiedCandidates: unverified, sourceErrors: report.sourceErrors ?? [],
        coverageErrors: report.coverageErrors ?? []},
      publications, rejectionReasons: reasons,
      reviewRejectionRationales: decisions.some((value) => value.reason === "no_practical_effect"),
      // Existing published duplicates retain their historic ID/run in the ledger.
      ledgerNote: "Earlier published records remain under their original run when a later decision preserves them.",
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
