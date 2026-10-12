import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {buildNewsScopeLayout, prepareNewsScopeLayout} from "./newsScopeCoordination.mjs";
import {closeNewsCandidateBatch, recordNewsCandidateBatch} from "./newsScopeDecisions.mjs";

const legacy = {sourceProgress: {
  city: {url: "https://example.gv.at/news", type: "official", scopes: ["wien"]},
}};
const runId = "news-2026-10-12T14";
const candidate = {url: "https://example.gv.at/story?utm_source=x", sourceId: "city"};
const receipt = (decisions) => ({scope: "wien", runId, candidates: [candidate], decisions});

test("a candidate batch cannot close with pending or missing decisions", () => {
  const layout = buildNewsScopeLayout(legacy);
  const state = layout.scopeStates.wien;
  assert.throws(() => closeNewsCandidateBatch(layout.registry, state, receipt([])), /Unresolved candidates/);
  assert.throws(() => closeNewsCandidateBatch(layout.registry, state,
    receipt([{url: candidate.url, outcome: "pending"}])), /Nonterminal/);
  assert.deepEqual(state.candidateDecisions, {});
});

test("rejection closes the pass with a minimal terminal technical trace", () => {
  const layout = buildNewsScopeLayout(legacy);
  const result = closeNewsCandidateBatch(layout.registry, layout.scopeStates.wien,
    receipt([{url: "https://example.gv.at/story", outcome: "rejected", reason: "no_practical_effect"}]),
    "2026-10-12T12:00:00Z");
  assert.equal(result.lastCandidateBatch.candidateDecisionsComplete, true);
  assert.equal(result.lastCandidateBatch.rejected, 1);
  assert.deepEqual(Object.keys(result.candidateDecisions), ["https://example.gv.at/story"]);
  assert.equal(result.candidateDecisions["https://example.gv.at/story"].reason, "no_practical_effect");
  assert.equal("pending" in result.candidateDecisions["https://example.gv.at/story"], false);
});

test("a published outcome needs a matching verified production receipt before durable closure", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uac-news-decisions-"));
  try {
    const root = join(directory, "news-scopes");
    const legacyPath = join(directory, "legacy.json");
    await writeFile(legacyPath, JSON.stringify(legacy));
    await prepareNewsScopeLayout(legacyPath, root, {write: true});
    const manifestPath = join(root, "manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.status = "active";
    await writeFile(manifestPath, JSON.stringify(manifest));
    const readbackPath = join(directory, "readback.json");
    const manifestFile = join(directory, "manifest.json");
    const editorialPath = join(directory, "editorial.json");
    const manifestContent = '{"kind":"news"}';
    await writeFile(manifestFile, manifestContent);
    await writeFile(editorialPath, JSON.stringify({passed: true, scope: "wien",
      canonicalURL: "https://example.gv.at/story", reviewedAt: new Date().toISOString(),
      manifestSHA256: createHash("sha256").update(manifestContent).digest("hex")}));
    const publication = receipt([{url: candidate.url, outcome: "published", contentId: "news-1",
      editorialReceiptPath: editorialPath, manifestPath: manifestFile,
      productionReadback: {verified: true, contentId: "news-1", receiptPath: readbackPath}}]);
    await writeFile(manifestFile, '{"kind":"event"}');
    await assert.rejects(() => recordNewsCandidateBatch(root, publication, {write: true}), /Editorial preflight receipt/);
    await writeFile(manifestFile, manifestContent);
    await writeFile(readbackPath, JSON.stringify({allVerified: false, id: "news-1",
      moderationStatus: "approved", regionScope: "federalState", federalState: "wien"}));
    await assert.rejects(() => recordNewsCandidateBatch(root, publication, {write: true}), /does not verify/);
    await writeFile(readbackPath, JSON.stringify({allVerified: true, id: "news-1",
      moderationStatus: "approved", regionScope: "federalState", federalState: "wien"}));
    const result = await recordNewsCandidateBatch(root, publication, {write: true});
    assert.equal(result.published, 1);
    const state = JSON.parse(await readFile(join(root, "scopes", "wien.json"), "utf8"));
    assert.equal(state.candidateDecisions["https://example.gv.at/story"].contentId, "news-1");
    await assert.rejects(() => recordNewsCandidateBatch(root, publication, {write: true}), /already closed/);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
