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
for (const key of ["UAC_PRODUCTION_APPLE_SIGN_IN_ENABLED", "UAC_PRODUCTION_PASSKEY_ENABLED"]) {
  if (!["true", "false"].includes(process.env[key])) {
    throw new Error(`Explicit release feature choice required: ${key}=true|false`);
  }
}

const project = "ukrainiancommunity-dbd5f";
const appId = "1:919042658790:android:c3e9447ac6f2a120ac4627";
const packageName = "at.serlest.ukrainiancommunity";
const firebaseKeys = [
  "UAC_PRODUCTION_FIREBASE_PROJECT_ID",
  "UAC_PRODUCTION_FIREBASE_APPLICATION_ID",
  "UAC_PRODUCTION_FIREBASE_API_KEY",
  "UAC_PRODUCTION_FIREBASE_BUCKET",
];
const suppliedFirebaseKeys = firebaseKeys.filter((key) => process.env[key]);
if (suppliedFirebaseKeys.length !== 0 && suppliedFirebaseKeys.length !== firebaseKeys.length) {
  const missingFirebaseKeys = firebaseKeys.filter((key) => !process.env[key]);
  throw new Error(`Production Firebase configuration incomplete: ${missingFirebaseKeys.join(", ")}`);
}

const config = JSON.parse(
  execFileSync("firebase", ["apps:sdkconfig", "ANDROID", appId, "--project", project], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  }),
);
const client = config.client?.[0];
if (config.client?.length !== 1 ||
    client?.client_info?.android_client_info?.package_name !== packageName) {
  throw new Error("Production Firebase Android package does not match the Play app");
}
const firebaseConfig = {
  UAC_PRODUCTION_FIREBASE_PROJECT_ID: config.project_info?.project_id ?? "",
  UAC_PRODUCTION_FIREBASE_APPLICATION_ID: client.client_info?.mobilesdk_app_id ?? "",
  UAC_PRODUCTION_FIREBASE_API_KEY: client.api_key?.[0]?.current_key ?? "",
  UAC_PRODUCTION_FIREBASE_BUCKET: config.project_info?.storage_bucket ?? "",
};
for (const key of suppliedFirebaseKeys) {
  if (process.env[key] !== firebaseConfig[key]) {
    throw new Error(`Keychain production Firebase value does not match live config: ${key}`);
  }
}
const webClients = client.oauth_client?.filter((entry) => entry.client_type === 3) ?? [];
if (webClients.length !== 1 ||
    !/^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(webClients[0].client_id ?? "")) {
  throw new Error("Production Firebase Android config must contain exactly one Google web OAuth client");
}
if (process.env.UAC_PRODUCTION_GOOGLE_WEB_CLIENT_ID &&
    process.env.UAC_PRODUCTION_GOOGLE_WEB_CLIENT_ID !== webClients[0].client_id) {
  throw new Error("Configured Google web client ID does not match production Firebase");
}
firebaseConfig.UAC_PRODUCTION_GOOGLE_WEB_CLIENT_ID = webClients[0].client_id;
const env = {
  ...process.env,
  ...firebaseConfig,
};
for (const key of Object.keys(env).filter((key) => key.startsWith("UAC_PRODUCTION_FIREBASE_"))) {
  if (!env[key]) throw new Error(`Missing production configuration: ${key}`);
}
const result = spawnSync(
  "./gradlew",
  [":app:assembleProductionRelease", ":app:bundleProductionRelease", "--no-daemon"],
  {
  cwd: new URL("..", import.meta.url),
  env,
  stdio: "inherit",
  },
);
if (result.status !== 0) process.exit(result.status ?? 1);
const artifact = new URL("../app/build/outputs/bundle/productionRelease/app-production-release.aab", import.meta.url);
const apk = new URL("../app/build/outputs/apk/production/release/app-production-release.apk", import.meta.url);
const digest = createHash("sha256").update(readFileSync(artifact)).digest("hex");
const apkDigest = createHash("sha256").update(readFileSync(apk)).digest("hex");
console.log(`Production AAB SHA-256: ${digest}`);
console.log(`Production APK SHA-256: ${apkDigest}`);
