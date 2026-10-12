import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync, rmSync, writeFileSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";

test("automation bridge rejects event draft creation before authentication or writes", () => {
  const directory = mkdtempSync(join(tmpdir(), "uac-event-draft-policy-"));
  try {
    const manifestPath = join(directory, "manifest.json");
    writeFileSync(manifestPath, JSON.stringify([{kind: "news"}, {kind: "event"}]));
    assert.throws(
      () => execFileSync(process.execPath, [
        fileURLToPath(new URL("./contentPlanningLocalBridge.mjs", import.meta.url)),
        "save", manifestPath,
      ], {encoding: "utf8", stdio: "pipe"}),
      (error) => {
        assert.equal(error.status, 1);
        assert.match(error.stderr, /cannot create event drafts/);
        return true;
      }
    );
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }
});
