import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const project = "uac-android-test-20260903";
const appId = "1:966536981122:android:2b617eb5d71f37b8dbe29b";
const config = JSON.parse(
  execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId, "--project", project], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }),
);
const client = config.client?.[0];
const env = {
  ...process.env,
  UAC_STAGING_FIREBASE_PROJECT_ID: config.project_info?.project_id ?? "",
  UAC_STAGING_FIREBASE_APPLICATION_ID: client?.client_info?.mobilesdk_app_id ?? "",
  UAC_STAGING_FIREBASE_API_KEY: client?.api_key?.[0]?.current_key ?? "",
  UAC_STAGING_FIREBASE_BUCKET: config.project_info?.storage_bucket ?? "",
};
for (const key of Object.keys(env).filter((key) => key.startsWith("UAC_STAGING_"))) {
  if (!env[key]) throw new Error(`Missing staging configuration: ${key}`);
}
const result = spawnSync("./gradlew", [":app:assembleStagingDebug", "--no-daemon"], {
  cwd: new URL("..", import.meta.url),
  env,
  stdio: "inherit",
});
if (result.status !== 0) process.exit(result.status ?? 1);
const artifact = new URL("../app/build/outputs/apk/staging/debug/app-staging-debug.apk", import.meta.url);
const digest = createHash("sha256").update(readFileSync(artifact)).digest("hex");
console.log(`Staging APK SHA-256: ${digest}`);
