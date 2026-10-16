#!/usr/bin/env node
import {mkdir, open, readFile, rename, rmdir, unlink, writeFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import {randomUUID} from "node:crypto";
import {pathToFileURL} from "node:url";
import {applyNewsEditorialSources, NEWS_SCOPES} from "./newsScopeCoordination.mjs";

export async function updateNewsDiscoveryPolicy(root, {apply = false} = {}) {
  const read = async (name) => JSON.parse(await readFile(join(root, name), "utf8"));
  const manifest = await read("manifest.json");
  const oldRegistry = await read("source-registry.json");
  const registry = applyNewsEditorialSources(oldRegistry);
  const active = registry.sources.filter((s) => s.active);
  const report = {dryRun: !apply, before: manifest.activeSourceCount, after: active.length,
    policyVersion: registry.editorialPolicyVersion,
    coreSources: active.map(({sourceId, editorialMode, scopes}) => ({sourceId, editorialMode, scopes}))};
  if (!apply) return report;
  if (manifest.status !== "active") throw new Error("Only an active news layout can be updated.");
  const scanLock = join(root, "shared-scan.lock");
  const token = randomUUID();
  await mkdir(scanLock);
  const held = [];
  try {
    await writeFile(join(scanLock, "owner.json"), JSON.stringify({token, runId: "news-policy-v2-update", startedAt: new Date().toISOString()}));
    for (const scope of NEWS_SCOPES) {
      const path = join(root, "scopes", `${scope}.json.lock`);
      const lock = await open(path, "wx");
      await lock.writeFile(token); await lock.close(); held.push(path);
    }
    const files = ["manifest.json", "source-registry.json", "shared-source-state.json",
      ...NEWS_SCOPES.map((s) => `scopes/${s}.json`)];
    const original = Object.fromEntries(await Promise.all(files.map(async (n) => [n, await readFile(join(root, n))])));
    // Archived registry versions let an already-running wave keep using its
    // immutable snapshot after the next discovery policy is activated.
    const policies = join(root, "source-policies");
    await mkdir(policies, {recursive: true});
    for (const value of [oldRegistry, registry]) {
      const path = join(policies, `v${value.editorialPolicyVersion ?? 1}.json`);
      const bytes = JSON.stringify(value, null, 2) + "\n";
      try { await writeFile(path, bytes, {flag: "wx"}); }
      catch (error) { if (error.code !== "EEXIST") throw error; }
    }
    const backup = join(root, "policy-backups", new Date().toISOString().replace(/[:.]/g, "-"));
    await mkdir(join(backup, "scopes"), {recursive: true});
    for (const [name, bytes] of Object.entries(original)) await writeFile(join(backup, name), bytes, {flag: "wx"});
    const shared = JSON.parse(original["shared-source-state.json"]);
    const next = {"source-registry.json": registry, "shared-source-state.json": shared};
    for (const source of registry.sources) shared.sources[source.sourceId] ??= {
      lastFetchAt: null, lastSnapshotId: null, etag: null, lastModified: null};
    for (const scope of NEWS_SCOPES) {
      const name = `scopes/${scope}.json`;
      const state = JSON.parse(original[name]);
      for (const source of active.filter((s) => s.scopes.includes(scope))) {
        state.sourceProgress[source.sourceId] ??= {processedThrough: null, nextPage: null, lastReviewedAt: null};
      }
      next[name] = state;
    }
    next["manifest.json"] = {...manifest, sourceCount: registry.sources.length,
      activeSourceCount: active.length,
      sharedSourceCount: active.filter((s) => s.scopes.length > 1).length,
      editorialPolicyVersion: registry.editorialPolicyVersion, discoveryPolicyUpdatedAt: new Date().toISOString()};
    const written = [];
    try {
      for (const [name, value] of Object.entries(next)) {
        const path = join(root, name); const temporary = `${path}.${token}.tmp`;
        await writeFile(temporary, JSON.stringify(value, null, 2) + "\n");
        await rename(temporary, path); written.push(name);
      }
    } catch (error) {
      for (const name of written) {
        const path = join(root, name);const temporary = `${path}.${token}.restore`;
        await writeFile(temporary, original[name]); await rename(temporary, path);
      }
      throw error;
    }
    return {...report, backup, dryRun: false};
  } finally {
    for (const path of held.reverse()) {
      if (await readFile(path, "utf8") !== token) throw new Error("Scope update lock owner changed.");
      await unlink(path);
    }
    const ownerPath = join(scanLock, "owner.json");
    const owner = JSON.parse(await readFile(ownerPath, "utf8"));
    if (owner.token !== token) throw new Error("Scan update lock owner changed.");
    await unlink(ownerPath); await rmdir(scanLock);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root, mode] = process.argv.slice(2);
  try {
    if (!root || (mode && mode !== "--apply")) throw new Error("Usage: node updateNewsDiscoveryPolicy.mjs <news-scopes-root> [--apply]");
    console.log(JSON.stringify(await updateNewsDiscoveryPolicy(resolve(root), {apply: mode === "--apply"})));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
