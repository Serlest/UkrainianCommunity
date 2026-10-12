#!/usr/bin/env node

import {createHash, randomUUID} from "node:crypto";
import {open, readFile, rename, unlink, writeFile} from "node:fs/promises";
import {isAbsolute, join, resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {NEWS_SCOPES, canonicalNewsURL} from "./newsScopeCoordination.mjs";

const rejectionReasons = new Set([
  "not_article", "stale", "no_practical_effect", "excluded_topic", "wrong_scope",
  "unverified", "insufficient_facts", "duplicate", "unsupported_territory",
]);
const runPattern = /^(?:news-\d{4}-\d{2}-\d{2}T\d{2}|emergency-\d{4}-\d{2}-\d{2}T\d{2}-(?:00|30))$/;

// This closes an editorial candidate batch, not source coverage. A source
// failure must still make the overall run partial, with its cursor unchanged.
export function closeNewsCandidateBatch(registry, state, input, decidedAt = new Date().toISOString()) {
  const {scope, runId, candidates, decisions} = input ?? {};
  if (!NEWS_SCOPES.includes(scope) || state.scope !== scope || !runPattern.test(runId ?? "")) {
    throw new Error("A valid scope and run ID matching its state are required.");
  }
  if (state.lastCandidateBatch?.runId === runId) throw new Error("This candidate batch was already closed.");
  if (!Array.isArray(candidates) || !Array.isArray(decisions)) {
    throw new Error("Candidates and decisions must both be arrays.");
  }
  const sources = new Map(registry.sources
    .filter((source) => (source.active || source.editorialMode === "adapter") && source.scopes.includes(scope))
    .map((source) => [source.sourceId, source]));
  const candidateByURL = new Map();
  for (const candidate of candidates) {
    if (!sources.has(candidate?.sourceId)) throw new Error("Candidate has no active source in this scope.");
    const url = canonicalNewsURL(candidate.url);
    const existing = candidateByURL.get(url);
    if (existing) existing.sourceIds.add(candidate.sourceId);
    else candidateByURL.set(url, {url, sourceIds: new Set([candidate.sourceId])});
  }
  const decisionByURL = new Map();
  for (const decision of decisions) {
    const url = canonicalNewsURL(decision?.url);
    if (decisionByURL.has(url)) throw new Error(`Repeated decision for ${url}`);
    if (!candidateByURL.has(url)) throw new Error(`Decision without observed candidate: ${url}`);
    if (decision.outcome === "rejected") {
      if (!rejectionReasons.has(decision.reason)) throw new Error(`Invalid rejection reason for ${url}`);
    } else if (decision.outcome === "published") {
      if (typeof decision.contentId !== "string" || !decision.contentId.trim() ||
          decision.productionReadback?.verified !== true ||
          decision.productionReadback?.contentId !== decision.contentId ||
          typeof decision.productionReadback?.receiptPath !== "string" ||
          !decision.productionReadback.receiptPath.trim() ||
          typeof decision.editorialReceiptPath !== "string" ||
          typeof decision.manifestPath !== "string") {
        throw new Error(`Publication needs matching production read-back evidence: ${url}`);
      }
    } else {
      throw new Error(`Nonterminal candidate outcome for ${url}`);
    }
    decisionByURL.set(url, decision);
  }
  const missing = [...candidateByURL.keys()].filter((url) => !decisionByURL.has(url));
  if (missing.length) throw new Error(`Unresolved candidates in this pass: ${missing.length}`);

  const candidateDecisions = {...state.candidateDecisions};
  let published = 0;
  for (const [url, candidate] of candidateByURL) {
    const decision = decisionByURL.get(url);
    if (decision.outcome === "published") published++;
    // A later duplicate rejection must not erase an earlier publication ID.
    if (candidateDecisions[url]?.outcome === "published" && decision.outcome !== "published") continue;
    candidateDecisions[url] = {
      outcome: decision.outcome,
      ...(decision.outcome === "rejected" ? {reason: decision.reason} : {
        contentId: decision.contentId,
        readbackReceiptPath: decision.productionReadback.receiptPath,
      }),
      sourceIds: [...candidate.sourceIds], runId, decidedAt,
    };
  }
  return {...state, candidateDecisions, lastCandidateBatch: {
    runId, decidedAt, candidateDecisionsComplete: true,
    candidates: candidateByURL.size, published, rejected: candidateByURL.size - published,
  }};
}

export async function recordNewsCandidateBatch(root, input, {write = false} = {}) {
  const scope = input?.scope;
  if (!NEWS_SCOPES.includes(scope)) throw new Error("Unknown news scope.");
  const readJSON = async (path) => JSON.parse(await readFile(path, "utf8"));
  const [manifest, registry] = await Promise.all([
    readJSON(join(root, "manifest.json")), readJSON(join(root, "source-registry.json")),
  ]);
  const statePath = join(root, "scopes", `${scope}.json`);
  if (!write) return closeNewsCandidateBatch(registry, await readJSON(statePath), input).lastCandidateBatch;
  if (manifest.status !== "active") throw new Error("News scopes are not active; use dry-run only.");
  const lockPath = `${statePath}.lock`;
  const token = randomUUID();
  const handle = await open(lockPath, "wx");
  await handle.writeFile(token);
  await handle.close();
  try {
    const next = closeNewsCandidateBatch(registry, await readJSON(statePath), input);
    for (const decision of input.decisions) {
      if (decision.outcome !== "published") continue;
      if (!isAbsolute(decision.editorialReceiptPath) || !isAbsolute(decision.manifestPath)) {
        throw new Error("Editorial receipt and manifest paths must be absolute.");
      }
      const editorial = await readJSON(decision.editorialReceiptPath);
      const manifestHash = createHash("sha256").update(await readFile(decision.manifestPath)).digest("hex");
      const reviewedAt = new Date(editorial.reviewedAt).getTime();
      if (editorial.passed !== true || editorial.scope !== scope ||
          editorial.canonicalURL !== canonicalNewsURL(decision.url) ||
          editorial.manifestSHA256 !== manifestHash ||
          !Number.isFinite(reviewedAt) || Date.now() - reviewedAt > 4 * 60 * 60 * 1000 ||
          reviewedAt - Date.now() > 5 * 60 * 1000) {
        throw new Error(`Editorial preflight receipt does not verify ${decision.contentId}.`);
      }
      const path = decision.productionReadback.receiptPath;
      if (!isAbsolute(path)) throw new Error("Production read-back receipt path must be absolute.");
      const receipt = await readJSON(path);
      const document = receipt.document ?? receipt;
      if (receipt.allVerified !== true || document.id !== decision.contentId ||
          document.moderationStatus !== "approved" ||
          (scope === "austria" ? document.regionScope !== "austria" :
            document.regionScope !== "federalState" || document.federalState !== scope)) {
        throw new Error(`Production read-back receipt does not verify ${decision.contentId}.`);
      }
    }
    const temporary = `${statePath}.${token}.tmp`;
    try {
      await writeFile(temporary, JSON.stringify(next, null, 2) + "\n");
      await rename(temporary, statePath);
    } finally {
      await unlink(temporary).catch(() => {});
    }
    return next.lastCandidateBatch;
  } finally {
    if (await readFile(lockPath, "utf8") !== token) {
      throw new Error("News scope decision lock owner changed; refusing to release it.");
    }
    await unlink(lockPath);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root, inputPath, mode] = process.argv.slice(2);
  if (!root || !inputPath || (mode && mode !== "--apply")) {
    console.error("Usage: node newsScopeDecisions.mjs <news-scopes-root> <candidate-batch.json> [--apply]");
    process.exitCode = 1;
  } else {
    try {
      const input = JSON.parse(await readFile(resolve(inputPath), "utf8"));
      console.log(JSON.stringify(await recordNewsCandidateBatch(resolve(root), input, {write: mode === "--apply"})));
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
}
