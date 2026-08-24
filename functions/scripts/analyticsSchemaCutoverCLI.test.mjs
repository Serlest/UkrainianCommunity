import assert from "node:assert/strict";
import {mkdtemp, readFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {
  assertProductionFirestoreEndpoint,
  immutableAtomicWrite,
} from "./migrateAnalyticsSchemaV2.mjs";

test("production cutover CLI rejects an emulator endpoint", () => {
  assert.doesNotThrow(() => assertProductionFirestoreEndpoint({}));
  assert.throws(
    () => assertProductionFirestoreEndpoint({
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    }),
    /production endpoint/
  );
});

test("cutover evidence reports are immutable", async () => {
  const directory = await mkdtemp(join(tmpdir(), "analytics-cutover-report-"));
  const reportPath = join(directory, "prepare.json");
  try {
    await immutableAtomicWrite(reportPath, "first\n");
    assert.equal(await readFile(reportPath, "utf8"), "first\n");
    await assert.rejects(
      immutableAtomicWrite(reportPath, "replacement\n"),
      (error) => error?.code === "EEXIST"
    );
    assert.equal(await readFile(reportPath, "utf8"), "first\n");
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});
