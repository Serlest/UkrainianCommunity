import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp, mkdir, writeFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {ensureSharedScan} from "./newsEnsureSharedScan.mjs";

test("a territorial reader creates a missing shared scan once and then reuses it", async () => {
  const root = await mkdtemp(join(tmpdir(), "news-ensure-"));
  try {
    await mkdir(join(root, "snapshots"));
    await writeFile(join(root, "manifest.json"), JSON.stringify({status: "active", activeSourceCount: 1}));
    let calls = 0;
    const scan = async () => { calls++; await writeFile(join(root, "snapshots", "news-2026-10-16T09.json"),
      JSON.stringify([{checkedAt: "2026-10-16T07:00:00Z", httpStatus: 200}])); };
    const options = {run: true, scan, now: new Date("2026-10-16T07:20:00Z")};
    assert.equal((await ensureSharedScan(root, "news-2026-10-16T09", options)).fresh, true);
    assert.equal((await ensureSharedScan(root, "news-2026-10-16T09", options)).existing, true);
    assert.equal(calls, 1);
    assert.equal((await ensureSharedScan(root, "news-2026-10-16T09", {...options, now: new Date("2026-10-16T10:00:00Z")})).fresh, false);
    assert.equal(calls, 1, "never overwrite an old immutable snapshot");
  } finally { await rm(root, {recursive: true, force: true}); }
});
