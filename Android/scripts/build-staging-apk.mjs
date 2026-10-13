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
const oauth = client?.oauth_client ?? [];
const webClient = oauth.find((entry) => entry.client_type === 3)?.client_id;
const androidClient = oauth.find((entry) =>
  entry.client_type === 1 &&
  entry.android_info?.package_name === "at.serlest.ukrainiancommunity.staging");
const env = {
  ...process.env,
  UAC_STAGING_FIREBASE_PROJECT_ID: config.project_info?.project_id ?? "",
  UAC_STAGING_FIREBASE_APPLICATION_ID: client?.client_info?.mobilesdk_app_id ?? "",
  UAC_STAGING_FIREBASE_API_KEY: client?.api_key?.[0]?.current_key ?? "",
  UAC_STAGING_FIREBASE_BUCKET: config.project_info?.storage_bucket ?? "",
  // A web ID alone cannot prove the Android package/certificate is registered.
  UAC_STAGING_GOOGLE_WEB_CLIENT_ID: webClient && androidClient ? webClient : "",
};
for (const key of ["UAC_STAGING_FIREBASE_PROJECT_ID", "UAC_STAGING_FIREBASE_APPLICATION_ID",
  "UAC_STAGING_FIREBASE_API_KEY", "UAC_STAGING_FIREBASE_BUCKET"]) {
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
