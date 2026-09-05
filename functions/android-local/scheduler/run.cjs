"use strict";

const {spawn, spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {validateEnvironment, isolatedEnvironment} = require("./environment.cjs");
validateEnvironment(process.env);
const mode = process.argv[2];
if (process.argv.length !== 3 || !["--boundary", "--worker", "--cleanup"].includes(mode)) {
  throw new Error("Use exactly --boundary, --worker or --cleanup; emulator startup is a separate root-owned action.");
}
const registry = require("./registry.cjs");
// allowedNodeEnvironmentFlags describes NODE_OPTIONS, not supported CLI arguments.
// This bounded, clean child probes the exact CLI flag without importing Admin, tests or opening a manifest.
const capability = spawnSync(process.execPath, ["--experimental-test-isolation=none", "-e", "process.stdout.write('scheduler-isolation-ready')"], {
  cwd: __dirname, env: isolatedEnvironment(), encoding: "utf8", timeout: 5_000, maxBuffer: 4_096,
});
if (capability.error || capability.signal || capability.status !== 0 || capability.stdout !== "scheduler-isolation-ready") {
  throw new Error("This Node executable does not confirm explicit no-isolation mode; no fixture manifest was opened.");
}
if (mode === "--worker") {
  for (const relative of ["content/scheduledPublishing", "firebase/admin", "permissions/userPermissions", "contentPlanning/contentPlanningRetentionPolicy"]) {
    const root = path.resolve(__dirname, "../..");
    if (fs.statSync(path.join(root, "lib", `${relative}.js`)).mtimeMs < fs.statSync(path.join(root, "src", `${relative}.ts`)).mtimeMs) {
      throw new Error("Compiled scheduler dependency is stale; request a scoped Functions build before starting.");
    }
  }
  registry.prepare(); // fsync + immutable read-back, before the child can import Admin or mutate data.
} else if (mode === "--cleanup") {
  if (registry.ownerAlive(registry.read())) throw new Error("The previous runner is still alive; cleanup refused.");
}
const entry = mode === "--boundary" ? "boundary.test.cjs" : mode === "--worker" ? "worker.test.cjs" : "cleanup.cjs";
const args = mode === "--cleanup" ? [path.join(__dirname, entry)] : ["--test", "--experimental-test-isolation=none", "--test-concurrency=1", path.join(__dirname, entry)];
const processChild = spawn(process.execPath, args, {cwd: path.resolve(__dirname, "../.."),
  env: {...isolatedEnvironment(), UAC_SCHEDULER_MODE: mode.slice(2)}, stdio: "inherit"});
let timedOut = false;
const timeout = setTimeout(() => {
  timedOut = true;
  processChild.kill("SIGTERM");
  setTimeout(() => processChild.kill("SIGKILL"), 5_000).unref();
}, mode === "--worker" ? 600_000 : 240_000);
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => processChild.kill(signal));
processChild.on("error", () => { clearTimeout(timeout); console.error("Could not start scheduler child; any manifest is retained."); process.exitCode = 1; });
processChild.on("exit", code => { clearTimeout(timeout); process.exitCode = timedOut ? 124 : code ?? 1; });
