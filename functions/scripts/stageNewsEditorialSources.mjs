#!/usr/bin/env node

import {readFile, readdir, rename, writeFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {randomUUID} from "node:crypto";

import {NEWS_SCOPES, applyNewsEditorialSources} from "./newsScopeCoordination.mjs";

async function readJSON(path) { return JSON.parse(await readFile(path, "utf8")); }
async function writeJSON(path, value) {
  const temporary = `${path}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(value, null, 2) + "\n");
  await rename(temporary, path);
}

export async function stageNewsEditorialSources(root, {write = false} = {}) {
  const manifestPath = join(root, "manifest.json");
  const registryPath = join(root, "source-registry.json");
  const manifest = await readJSON(manifestPath);
  if (manifest.status !== "prepared_not_active") {
    throw new Error("Only an inactive prepared news scope layout can be curated.");
  }
  const snapshotNames = await readdir(join(root, "snapshots")).catch((error) => {
    if (error.code === "ENOENT") return [];
    throw error;
  });
  if (snapshotNames.length) throw new Error("Prepared layout has discovery snapshots; curate it before scanning.");
  const registry = applyNewsEditorialSources(await readJSON(registryPath));
  const active = registry.sources.filter((source) => source.active);
  const countsByScope = Object.fromEntries(NEWS_SCOPES.map((scope) => [scope,
    active.filter((source) => source.scopes.includes(scope)).length]));
  const report = {dryRun: !write, sourceCount: registry.sources.length,
    scanSources: active.length,
    adapterSources: registry.sources.filter((source) => source.editorialMode === "adapter").length,
    referenceSources: registry.sources.filter((source) => source.editorialMode === "reference").length,
    excludedLegacySources: registry.sources.filter((source) => source.editorialMode === "excluded").length,
    countsByScope};
  if (!write) return report;

  const sharedPath = join(root, "shared-source-state.json");
  const shared = await readJSON(sharedPath);
  const scopes = Object.fromEntries(await Promise.all(NEWS_SCOPES.map(async (scope) =>
    [scope, await readJSON(join(root, "scopes", `${scope}.json`))])));
  for (const source of registry.sources) {
    shared.sources[source.sourceId] ||= {lastFetchAt: null, lastSnapshotId: null, etag: null, lastModified: null};
    for (const scope of source.scopes) {
      if (source.active) scopes[scope].sourceProgress[source.sourceId] ||= {
        processedThrough: null, nextPage: null, lastReviewedAt: null,
      };
    }
  }
  Object.assign(manifest, {sourceCount: registry.sources.length,
    activeSourceCount: active.length,
    sharedSourceCount: active.filter((source) => source.scopes.length > 1).length,
    editorialPolicyVersion: 1});
  await writeJSON(registryPath, registry);
  await writeJSON(sharedPath, shared);
  for (const scope of NEWS_SCOPES) await writeJSON(join(root, "scopes", `${scope}.json`), scopes[scope]);
  await writeJSON(manifestPath, manifest);
  return {...report, dryRun: false};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root, mode] = process.argv.slice(2);
  if (!root || (mode && mode !== "--apply")) {
    console.error("Usage: node stageNewsEditorialSources.mjs <news-scopes-directory> [--apply]");
    process.exitCode = 1;
  } else {
    try { console.log(JSON.stringify(await stageNewsEditorialSources(resolve(root), {write: mode === "--apply"}))); }
    catch (error) { console.error(error.message); process.exitCode = 1; }
  }
}
