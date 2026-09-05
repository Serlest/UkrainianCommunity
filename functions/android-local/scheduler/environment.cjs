"use strict";

const projectId = "demo-uac-android-scheduler";
const host = "127.0.0.1";
const port = 8098;
const emulatorHost = `${host}:${port}`;
const forbidden = /(?:CREDENTIAL|PRIVATE_KEY|ACCESS_TOKEN|REFRESH_TOKEN|FIREBASE_TOKEN|GOOGLE_API_KEY|GCE_METADATA_HOST|GCE_METADATA_IP|PROXY|NODE_OPTIONS|NODE_PATH)/i;

function validateEnvironment(env) {
  if (env.UAC_SCHEDULER_LOCAL !== "1" || env.GCLOUD_PROJECT !== projectId || env.FIRESTORE_EMULATOR_HOST !== emulatorHost) {
    throw new Error("Scheduler harness requires its exact opt-in, demo project and isolated loopback emulator.");
  }
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCP_PROJECT"]) {
    if (env[key] && env[key] !== projectId) throw new Error("Scheduler harness rejects a different project alias.");
  }
  for (const key of ["FIREBASE_CONFIG", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
    if (env[key]) throw new Error("Scheduler harness rejects unrelated Firebase configuration.");
  }
  if (env.METADATA_SERVER_DETECTION !== "none") throw new Error("Scheduler harness requires metadata detection disabled.");
  for (const [key, value] of Object.entries(env)) {
    if (value && forbidden.test(key)) throw new Error("Scheduler harness rejects credentials, proxies or loaders.");
  }
  return Object.freeze({projectId, host, port});
}

function isolatedEnvironment(source = process.env) {
  const result = {};
  for (const key of ["PATH", "TMPDIR", "TEMP", "TMP", "LANG", "LC_ALL", "TERM"]) {
    if (source[key]) result[key] = source[key];
  }
  return {...result, UAC_SCHEDULER_LOCAL: "1", GCLOUD_PROJECT: projectId, GOOGLE_CLOUD_PROJECT: projectId,
    FIRESTORE_EMULATOR_HOST: emulatorHost, METADATA_SERVER_DETECTION: "none"};
}

module.exports = {projectId, host, port, emulatorHost, validateEnvironment, isolatedEnvironment};
