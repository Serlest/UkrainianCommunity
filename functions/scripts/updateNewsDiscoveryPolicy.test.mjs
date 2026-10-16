import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, mkdir, readFile, writeFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {buildNewsScopeLayout} from "./newsScopeCoordination.mjs";
import {updateNewsDiscoveryPolicy} from "./updateNewsDiscoveryPolicy.mjs";

test("policy activation preserves terminal decisions and immutable old snapshots and archives their registry", async () => {
  const root = await mkdtemp(join(tmpdir(), "news-policy-"));
  try {
    const layout = buildNewsScopeLayout({sourceProgress: {source: {url: "https://www.noe.gv.at/noe/Uebersicht.html", scopes: ["niederoesterreich"]}}});
    layout.manifest.status = "active";
    layout.scopeStates.wien.candidateDecisions["https://example.at/old"] = {outcome: "published", contentId: "kept"};
    layout.scopeStates.wien.lastCandidateBatch = {runId: "news-2026-10-16T09", candidates: 1};
    await mkdir(join(root, "scopes")); await mkdir(join(root, "snapshots"));
    for (const [name, value] of Object.entries({"manifest.json": layout.manifest, "source-registry.json": layout.registry,
      "shared-source-state.json": layout.sharedState,
      ...Object.fromEntries(Object.entries(layout.scopeStates).map(([s, v]) => [`scopes/${s}.json`, v]))})) {
      await writeFile(join(root, name), JSON.stringify(value));
    }
    const snapshot = join(root, "snapshots/news-2026-10-16T09.json");
    await writeFile(snapshot, "[]\n");
    assert.equal((await updateNewsDiscoveryPolicy(root)).dryRun, true);
    assert.equal(JSON.parse(await readFile(join(root, "manifest.json"))).activeSourceCount, 1);
    const result = await updateNewsDiscoveryPolicy(root, {apply: true});
    assert.equal(result.after, 53);
    const state = JSON.parse(await readFile(join(root, "scopes/wien.json")));
    assert.equal(state.candidateDecisions["https://example.at/old"].contentId, "kept");
    assert.equal(state.lastCandidateBatch.runId, "news-2026-10-16T09");
    assert.equal(await readFile(snapshot, "utf8"), "[]\n");
    assert.equal(JSON.parse(await readFile(join(root, "source-policies/v1.json"))).sources.length, 1);
    const foreignLock = join(root, "scopes/wien.json.lock");
    await writeFile(foreignLock, "foreign");
    await assert.rejects(updateNewsDiscoveryPolicy(root, {apply: true}), /EEXIST/);
    assert.equal(await readFile(foreignLock, "utf8"), "foreign");
  } finally { await rm(root, {recursive: true, force: true}); }
});
