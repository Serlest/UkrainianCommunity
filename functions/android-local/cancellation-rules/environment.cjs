"use strict";

const projectId = "demo-uac-cancellation-rules";
const host = "127.0.0.1";
const port = 8098;
const emulatorHost = `${host}:${port}`;
const forbidden = /(?:CREDENTIAL|PRIVATE_KEY|ACCESS_TOKEN|REFRESH_TOKEN|FIREBASE_TOKEN|GOOGLE_API_KEY|GCE_METADATA_HOST|GCE_METADATA_IP|PROXY|NODE_OPTIONS|NODE_PATH)/i;

function validateEnvironment(env) {
  if (env.UAC_CANCELLATION_RULES_LOCAL !== "1" || env.FIRESTORE_EMULATOR_HOST !== emulatorHost || env.GCLOUD_PROJECT !== projectId) {
    throw new Error("Cancellation Rules require the exact opt-in, isolated demo project and localhost emulator.");
  }
  for (const key of ["GOOGLE_CLOUD_PROJECT", "GCP_PROJECT"]) {
    if (env[key] && env[key] !== projectId) throw new Error("Cancellation Rules reject a different project alias.");
  }
  for (const key of ["FIREBASE_CONFIG", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
    if (env[key]) throw new Error("Cancellation Rules reject unrelated Firebase configuration.");
  }
  for (const [key, value] of Object.entries(env)) {
    if (value && forbidden.test(key)) throw new Error("Cancellation Rules reject credential, proxy or loader environment.");
  }
  return {projectId, host, port};
}

function isolatedEnvironment(source = process.env) {
  const result = {};
  for (const key of ["PATH", "TMPDIR", "TEMP", "TMP", "LANG", "LC_ALL", "TERM"]) {
    if (source[key]) result[key] = source[key];
  }
  return {...result, UAC_CANCELLATION_RULES_LOCAL: "1", FIRESTORE_EMULATOR_HOST: emulatorHost,
    GCLOUD_PROJECT: projectId, GOOGLE_CLOUD_PROJECT: projectId, METADATA_SERVER_DETECTION: "none"};
}

module.exports = {projectId, host, port, emulatorHost, validateEnvironment, isolatedEnvironment};
