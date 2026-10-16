#!/usr/bin/env node
import {readFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {runNewsSharedScan} from "./newsSharedScan.mjs";

// The first territorial reader can collect a missing snapshot when the
// coordinator chat is occupied. The scanner's existing lock serializes writers.
export async function ensureSharedScan(root, runId, {run = false,
  scan = runNewsSharedScan, wait = (ms) => new Promise((r) => setTimeout(r, ms)), now = new Date(),
} = {}) {
  const manifest = JSON.parse(await readFile(join(root, "manifest.json"), "utf8"));
  if (manifest.status !== "active") throw new Error("News scopes are not active.");
  const snapshot = join(root, "snapshots", `${runId}.json`);
  const read = async () => {
    let rows;
    try { rows = JSON.parse(await readFile(snapshot, "utf8")); }
    catch (error) { if (error.code === "ENOENT") return null; throw error; }
    const fresh = rows.length > 0 && rows.every((r) => {
      const age = now - new Date(r.checkedAt);
      return Number.isFinite(age) && age >= -5 * 60_000 && age <= 90 * 60_000;
    });
    const sourcePolicyVersion = rows[0]?.sourcePolicyVersion ?? 1;
    let expectedSources = manifest.activeSourceCount;
    if (sourcePolicyVersion !== (manifest.editorialPolicyVersion ?? 1)) {
      const policy = JSON.parse(await readFile(join(root, "source-policies", `v${sourcePolicyVersion}.json`), "utf8"));
      expectedSources = policy.sources.filter((s) => s.active).length;
    }
    return {runId, snapshotPath: snapshot, existing: true, fresh,
      sourcePolicyVersion, expectedSources, sources: rows.length,
      failed: rows.filter((r) => r.error || r.httpStatus !== 200).length};
  };
  const existing = await read();
  if (existing) return existing;
  if (!run) return {runId, dryRun: true, missing: true, expectedSources: manifest.activeSourceCount};
  for (let attempt = 0; attempt < 4; attempt++) {
    try { await scan(root, runId, {now}); return {...await read(), existing: false}; }
    catch (error) {
      if (error.code !== "EEXIST" && !error.message.includes("snapshot already exists")) throw error;
      const ready = await read();
      if (ready) return ready;
      if (attempt === 3) throw new Error("Shared scan is still busy; record this editorial pass partial.");
      await wait(10_000);
    }
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [root, runId, mode] = process.argv.slice(2);
  try {
    if (!root || !/^news-\d{4}-\d{2}-\d{2}T\d{2}$/.test(runId ?? "") || (mode && mode !== "--run")) {
      throw new Error("Usage: node newsEnsureSharedScan.mjs <news-scopes-root> <news-YYYY-MM-DDTHH> [--run]");
    }
    console.log(JSON.stringify(await ensureSharedScan(resolve(root), runId, {run: mode === "--run"})));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
