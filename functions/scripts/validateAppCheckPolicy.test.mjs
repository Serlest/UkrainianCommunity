import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  inspectAppCheckPolicy,
  policySummary,
} from "./validateAppCheckPolicy.mjs";

function withFixture(files, operation) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "uac-app-check-policy-"));
  try {
    for (const [filename, contents] of Object.entries(files)) {
      const absolutePath = path.join(root, filename);
      fs.mkdirSync(path.dirname(absolutePath), {recursive: true});
      fs.writeFileSync(absolutePath, contents);
    }
    operation(root);
  } finally {
    fs.rmSync(root, {recursive: true, force: true});
  }
}

test("accepts explicit enforced, monitoring, and dynamic policies", () => {
  withFixture({
    "callables.ts": `
      const monitored = {region: "europe-west3", enforceAppCheck: false};
      const runtimeGate = false;
      export const a = onCall({enforceAppCheck: true}, async () => ({}));
      export const b = onCall(monitored, async () => ({}));
      export const c = onCall({enforceAppCheck: runtimeGate}, async () => ({}));
    `,
  }, (root) => {
    const inspection = inspectAppCheckPolicy(root);
    assert.deepEqual(inspection.violations, []);
    assert.deepEqual(policySummary(inspection.results), {
      enforced: 1,
      monitoring: 1,
      dynamic: 1,
    });
  });
});

test("rejects implicit defaults and unresolved option objects", () => {
  withFixture({
    "implicit.ts": `
      const incomplete = {region: "europe-west3"};
      export const a = onCall(async () => ({}));
      export const b = onCall(incomplete, async () => ({}));
      export const c = onCall(importedOptions, async () => ({}));
    `,
  }, (root) => {
    const inspection = inspectAppCheckPolicy(root);
    assert.equal(inspection.results.length, 0);
    assert.equal(inspection.violations.length, 3);
  });
});
