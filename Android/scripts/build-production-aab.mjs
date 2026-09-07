import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const requiredSigning = [
  "UAC_PRODUCTION_KEYSTORE",
  "UAC_PRODUCTION_KEYSTORE_PASSWORD",
  "UAC_PRODUCTION_KEY_ALIAS",
  "UAC_PRODUCTION_KEY_PASSWORD",
];
const missing = requiredSigning.filter((key) => !process.env[key]);
if (missing.length) throw new Error(`Release signing configuration missing: ${missing.join(", ")}`);

const project = "ukrainiancommunity-dbd5f";
const appId = "1:919042658790:android:c3e9447ac6f2a120ac4627";
const config = JSON.parse(
  execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId, "--project", project], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }),
);
const client = config.client?.[0];
const env = {
  ...process.env,
  UAC_PRODUCTION_FIREBASE_PROJECT_ID: config.project_info?.project_id ?? "",
  UAC_PRODUCTION_FIREBASE_APPLICATION_ID: client?.client_info?.mobilesdk_app_id ?? "",
  UAC_PRODUCTION_FIREBASE_API_KEY: client?.api_key?.[0]?.current_key ?? "",
  UAC_PRODUCTION_FIREBASE_BUCKET: config.project_info?.storage_bucket ?? "",
};
for (const key of Object.keys(env).filter((key) => key.startsWith("UAC_PRODUCTION_FIREBASE_"))) {
  if (!env[key]) throw new Error(`Missing production configuration: ${key}`);
}
const result = spawnSync("./gradlew", [":app:bundleProductionRelease", "--no-daemon"], {
  cwd: new URL("..", import.meta.url),
  env,
  stdio: "inherit",
});
if (result.status !== 0) process.exit(result.status ?? 1);
const artifact = new URL("../app/build/outputs/bundle/productionRelease/app-production-release.aab", import.meta.url);
const digest = createHash("sha256").update(readFileSync(artifact)).digest("hex");
console.log(`Production AAB SHA-256: ${digest}`);
