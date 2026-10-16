#!/usr/bin/env node

import {readFile, readdir} from "node:fs/promises";
import {basename, dirname, join} from "node:path";
import {buildScopeDiscoveryBatch, mergeTodayDiscovery} from "./newsScopeCoordination.mjs";
import {viennaDate} from "./newsSourceEvidence.mjs";

const [registryPath, discoveryPath, scope, windowFlag, root] = process.argv.slice(2);
if (!registryPath || !discoveryPath || !scope || (windowFlag && (windowFlag !== "--today" || !root))) {
  console.error("Usage: node scripts/newsScopeBatch.mjs <source-registry.json> <shared-discovery.json> <scope> [--today <news-scopes-root>]");
  process.exitCode = 1;
} else {
  try {
    let [registry, discovery] = await Promise.all([
      readFile(registryPath, "utf8").then(JSON.parse),
      readFile(discoveryPath, "utf8").then(JSON.parse),
    ]);
    const versions = new Set(discovery.map((r) => r.sourcePolicyVersion ?? 1));
    if (versions.size !== 1) throw new Error("Mixed source policy versions in shared snapshot.");
    const snapshotVersion = [...versions][0];
    if (snapshotVersion !== (registry.editorialPolicyVersion ?? 1)) {
      registry = JSON.parse(await readFile(join(dirname(registryPath), "source-policies", `v${snapshotVersion}.json`), "utf8"));
    }
    let rows = discovery;
    if (windowFlag) {
      const day = viennaDate(new Date());
      if (!basename(discoveryPath).startsWith(`news-${day}T`) ||
          discovery.some((row) => !Number.isFinite(new Date(row.checkedAt).getTime()) ||
            Date.now() - new Date(row.checkedAt).getTime() > 90 * 60_000 ||
            new Date(row.checkedAt).getTime() - Date.now() > 5 * 60_000)) {
        throw new Error("Current snapshot is not fresh for today's Vienna discovery window.");
      }
      const directory = join(root, "snapshots");
      const names = (await readdir(directory)).filter((name) =>
        name.startsWith(`news-${day}T`) && name.endsWith(".json") && name < basename(discoveryPath));
      const history = await Promise.all(names.map((name) => readFile(join(directory, name), "utf8").then(JSON.parse)));
      rows = mergeTodayDiscovery(discovery, history, day);
    }
    console.log(JSON.stringify({...buildScopeDiscoveryBatch(registry, rows, scope), sourcePolicyVersion: snapshotVersion}, null, 2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
