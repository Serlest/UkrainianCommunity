"use strict";

const {spawn} = require("node:child_process");
const {mkdtempSync} = require("node:fs");
const {tmpdir} = require("node:os");
const path = require("node:path");
const {isolatedEnvironment, emulatorHost, projectId, validateEnvironment} = require("./environment.cjs");

// No Firebase CLI, login, emulator lifecycle, inherited credentials or arbitrary test arguments.
if (process.argv.length !== 2 || process.env.UAC_A01B_RULES_LOCAL !== "1"
    || process.env.UAC_CANCELLATION_RULES_LOCAL !== "1"
    || process.env.FIRESTORE_EMULATOR_HOST !== emulatorHost || process.env.GCLOUD_PROJECT !== projectId) {
  throw new Error("A01-B requires explicit opt-in and the already-running isolated demo Firestore on 127.0.0.1:8098.");
}
const registryDirectory = mkdtempSync(path.join(tmpdir(), "uac-a01b-rules-"));
const registryPath = path.join(registryDirectory, "owned-fixtures.json");
const environment = {...isolatedEnvironment(), UAC_A01B_RULES_LOCAL: "1", UAC_A01B_REGISTRY_PATH: registryPath};
validateEnvironment(environment);
console.log(`A01B exact synthetic cleanup registry: ${registryPath}`);
const child = spawn(process.execPath, ["--test", "--test-concurrency=1",
  path.join(__dirname, "boundary.test.cjs"), path.join(__dirname, "contentModerationRules.test.cjs")], {
  cwd: path.resolve(__dirname, "../../.."), env: environment, stdio: "inherit",
});
let timedOut = false;
let escalation;
const deadline = setTimeout(() => {
  timedOut = true;
  console.error("A01B four-minute deadline reached; use the exact registry to check cleanup. Never replay the suite automatically.");
  child.kill("SIGTERM");
  escalation = setTimeout(() => child.kill("SIGKILL"), 5_000);
}, 240_000);
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("error", () => {
  clearTimeout(deadline); clearTimeout(escalation);
  console.error("Could not start the isolated A01B Rules test process."); process.exitCode = 1;
});
child.on("exit", (code) => {
  clearTimeout(deadline); clearTimeout(escalation);
  process.exitCode = timedOut ? 124 : code ?? 1;
});
