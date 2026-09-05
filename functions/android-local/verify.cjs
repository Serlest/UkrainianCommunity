"use strict";

const {spawnSync} = require("node:child_process");
const path = require("node:path");
const {validateEnvironment, isolatedEnvironment} = require("./environment.cjs");
validateEnvironment(process.env);
const root = path.resolve(__dirname, "../..");
const preload = path.join(__dirname, "preload.cjs");
const scripts = [
  path.join(__dirname, "scenarios.cjs"),
  path.join(root, "Android/scripts/local-fixtures.mjs"),
  path.join(root, "functions/smoke-tests/notificationPushRegistrationRules.test.mjs"),
  path.join(root, "functions/lib/notifications/workflowNotifications.integration.test.js"),
  path.join(root, "functions/lib/notifications/pushRegistrationMutations.integration.test.js"),
];
for (const script of scripts) {
  const result = spawnSync(process.execPath, ["--require", preload, script], {
    cwd: root, env: isolatedEnvironment(), stdio: "inherit", timeout: 120_000,
  });
  if (result.error || result.status !== 0) {
    console.error(`Android local verification failed: ${path.basename(script)}`);
    process.exitCode = 1;
    break;
  }
}
