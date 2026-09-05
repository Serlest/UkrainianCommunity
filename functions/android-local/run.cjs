"use strict";

const {spawn} = require("node:child_process");
const path = require("node:path");
const {copyFileSync, existsSync, mkdtempSync, readFileSync} = require("node:fs");
const {tmpdir} = require("node:os");
const {isolatedEnvironment} = require("./environment.cjs");
const mode = process.argv[2] ?? "start";
if (!["start", "check"].includes(mode) || process.argv.length > 3) {
  throw new Error("Usage: node functions/android-local/run.cjs [start|check]");
}
const root = path.resolve(__dirname, "../..");
const localConfig = path.join(__dirname, ".env.local");
const configTemplate = path.join(__dirname, ".env.example");
const expectedConfig = readFileSync(configTemplate, "utf8").trim();
if (existsSync(localConfig)) {
  if (readFileSync(localConfig, "utf8").trim() !== expectedConfig) {
    throw new Error("Refusing unknown local Functions env overrides. Review them before using this harness.");
  }
} else copyFileSync(configTemplate, localConfig);
const args = [mode === "start" ? "emulators:start" : "emulators:exec",
  "--project", "demo-uac-android", "--config", "firebase.android-functions-local.json",
  "--only", "auth,firestore,storage,functions", "--non-interactive"];
if (mode === "check") args.push("node functions/android-local/verify.cjs");
// Keep Firebase CLI's persisted login/config store outside this launch. HOME is
// not overridden or copied; Google ADC discovery is disabled in the clean env.
const cliConfigDirectory = mkdtempSync(path.join(tmpdir(), "uac-android-cli-"));
const child = spawn("firebase", args, {cwd: root,
  env: {...isolatedEnvironment(), XDG_CONFIG_HOME: cliConfigDirectory}, stdio: "inherit"});
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => child.kill(signal));
child.on("error", () => { console.error("Unable to start the installed Firebase CLI."); process.exitCode = 1; });
child.on("exit", (code) => { process.exitCode = code ?? 1; });
