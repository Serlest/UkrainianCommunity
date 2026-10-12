#!/usr/bin/env node

import {resolve} from "node:path";
import {prepareNewsScopeLayout} from "./newsScopeCoordination.mjs";

const [legacyPath, outputPath, mode] = process.argv.slice(2);
if (!legacyPath || !outputPath || (mode && mode !== "--write")) {
  console.error("Usage: node scripts/prepareNewsScopes.mjs <legacy-progress.json> <new-directory> [--write]");
  process.exitCode = 1;
} else {
  try {
    const manifest = await prepareNewsScopeLayout(resolve(legacyPath), resolve(outputPath), {write: mode === "--write"});
    console.log(JSON.stringify(manifest, null, 2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
