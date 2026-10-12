#!/usr/bin/env node

import {readFile} from "node:fs/promises";
import {buildScopeDiscoveryBatch} from "./newsScopeCoordination.mjs";

const [registryPath, discoveryPath, scope] = process.argv.slice(2);
if (!registryPath || !discoveryPath || !scope) {
  console.error("Usage: node scripts/newsScopeBatch.mjs <source-registry.json> <shared-discovery.json> <scope>");
  process.exitCode = 1;
} else {
  try {
    const [registry, discovery] = await Promise.all([
      readFile(registryPath, "utf8").then(JSON.parse),
      readFile(discoveryPath, "utf8").then(JSON.parse),
    ]);
    console.log(JSON.stringify(buildScopeDiscoveryBatch(registry, discovery, scope), null, 2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
