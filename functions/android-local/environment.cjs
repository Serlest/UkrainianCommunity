"use strict";

// Deliberately fixed: this harness cannot be pointed at a cloud project.
const projectId = "demo-uac-android";
const emulatorHosts = Object.freeze({
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:8088",
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9098",
  FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9198",
});
const blockedEnvironment = /(?:CREDENTIAL|PRIVATE_KEY|ACCESS_TOKEN|REFRESH_TOKEN|FIREBASE_TOKEN|GOOGLE_API_KEY|GCE_METADATA_HOST|GCE_METADATA_IP|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NODE_OPTIONS|NODE_PATH)/i;

function validateEnvironment(env) {
  if (env.UAC_ANDROID_LOCAL !== "1") throw new Error("Android Functions harness requires the explicit local opt-in.");
  if (env.GCLOUD_PROJECT !== projectId) throw new Error("Android Functions harness requires the exact demo project.");
  for (const [key, value] of Object.entries(emulatorHosts)) {
    if (env[key] !== value) throw new Error(`Android Functions harness rejects ${key}.`);
  }
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCP_PROJECT"]) {
    if (env[key] && env[key] !== projectId) throw new Error(`Android Functions harness rejects ${key}.`);
  }
  for (const [key, value] of Object.entries(env)) {
    if (value && blockedEnvironment.test(key)) {
      // Never echo credential values, paths or URLs into diagnostics.
      throw new Error(`Android Functions harness rejects environment field ${key}.`);
    }
  }
  if (env.FIREBASE_CONFIG) {
    let config;
    try { config = JSON.parse(env.FIREBASE_CONFIG); }
    catch { throw new Error("Android Functions harness requires inline demo FIREBASE_CONFIG."); }
    if (config.projectId !== projectId
      || (config.storageBucket && config.storageBucket !== `${projectId}.appspot.com`)
      // Firebase CLI inserts this non-existent demo RTDB placeholder even when
      // RTDB is disabled. It is never passed to Admin initialization below.
      || (config.databaseURL && config.databaseURL !== `https://${projectId}.firebaseio.com`)
      || config.credential) {
      throw new Error("Android Functions harness rejects cloud Firebase configuration.");
    }
  }
  return Object.freeze({projectId, emulatorHosts});
}

function isolatedEnvironment(source = process.env) {
  // Allowlist, not a copy of the caller's possibly authenticated environment.
  const result = {};
  for (const key of ["PATH", "JAVA_HOME", "TMPDIR", "TEMP", "TMP", "LANG", "LC_ALL", "TERM"]) {
    if (source[key]) result[key] = source[key];
  }
  return {
    ...result,
    UAC_ANDROID_LOCAL: "1",
    GCLOUD_PROJECT: projectId,
    GOOGLE_CLOUD_PROJECT: projectId,
    METADATA_SERVER_DETECTION: "none",
    ...emulatorHosts,
    FIREBASE_CONFIG: JSON.stringify({projectId, storageBucket: `${projectId}.appspot.com`}),
  };
}

module.exports = {projectId, emulatorHosts, validateEnvironment, isolatedEnvironment};
