"use strict";

const {spawn} = require("node:child_process");
const path = require("node:path");
const {isolatedEnvironment, emulatorHost} = require("./environment.cjs");

// This runner never starts/restarts an emulator or loads a persisted CLI login.
if (process.argv.length !== 2 || process.env.UAC_CANCELLATION_RULES_LOCAL !== "1" || process.env.FIRESTORE_EMULATOR_HOST !== emulatorHost) {
  throw new Error("Start the separately reviewed localhost:8098 demo emulator, then explicitly opt in to the Rules runner.");
}
const child = spawn(process.execPath, ["--test", "--test-concurrency=1", path.join(__dirname, "eventCancellationRules.test.cjs")], {
  cwd: path.resolve(__dirname, "../../.."), env: isolatedEnvironment(), stdio: "inherit",
});
let timedOut = false;
const deadline = setTimeout(() => { timedOut = true; child.kill("SIGTERM"); setTimeout(() => child.kill("SIGKILL"), 5_000).unref(); }, 240_000);
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("error", () => { clearTimeout(deadline); console.error("Could not start the isolated Rules test process."); process.exitCode = 1; });
child.on("exit", (code) => { clearTimeout(deadline); process.exitCode = timedOut ? 124 : code ?? 1; });
