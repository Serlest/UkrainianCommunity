"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const {isolatedEnvironment, validateEnvironment, projectId, emulatorHost} = require("./environment.cjs");
const boundaryPath = path.join(__dirname, "boundary.cjs");
const clean = () => isolatedEnvironment({PATH: process.env.PATH});
function child(script, overrides = {}) {
  const result = spawnSync(process.execPath, ["-e", script], {env: {...clean(), ...overrides}, timeout: 10_000, encoding: "utf8"});
  assert.equal(result.status, 0, result.stderr);
}

test("accepts only the exact local opt-in and isolated demo host/project", () => {
  assert.deepEqual(validateEnvironment(clean()), {projectId, host: "127.0.0.1", port: 8098});
  for (const patch of [{UAC_CANCELLATION_RULES_LOCAL: ""}, {GCLOUD_PROJECT: "ukrainiancommunity-dbd5f"},
    {GCLOUD_PROJECT: "demo-uac-android"}, {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8088"},
    {FIRESTORE_EMULATOR_HOST: "example.invalid:8098"}, {FIRESTORE_EMULATOR_HOST: "localhost:8098"},
    {GOOGLE_CLOUD_PROJECT: "other"}, {GCP_PROJECT: "other"}]) assert.throws(() => validateEnvironment({...clean(), ...patch}));
});

test("rejects credentials/proxies/loader injection and unrelated Firebase services before import", () => {
  for (const key of ["GOOGLE_APPLICATION_CREDENTIALS", "FIREBASE_TOKEN", "PRIVATE_KEY", "HTTPS_PROXY", "http_proxy", "ALL_PROXY",
    "NODE_OPTIONS", "NODE_PATH", "FIREBASE_CONFIG", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
    assert.throws(() => validateEnvironment({...clean(), [key]: "synthetic-not-a-secret"}));
  }
});

test("runner environment does not copy credentials, proxy, home, login or project overrides", () => {
  const value = isolatedEnvironment({PATH: "/synthetic/bin", HOME: "/synthetic/home", FIREBASE_TOKEN: "synthetic",
    HTTPS_PROXY: "https://example.invalid", GCLOUD_PROJECT: "production-example", NODE_OPTIONS: "synthetic"});
  assert.equal(value.HOME, undefined); assert.equal(value.FIREBASE_TOKEN, undefined); assert.equal(value.HTTPS_PROXY, undefined);
  assert.equal(value.NODE_OPTIONS, undefined); assert.equal(value.GCLOUD_PROJECT, projectId); assert.equal(value.FIRESTORE_EMULATOR_HOST, emulatorHost);
  validateEnvironment(value);
});

test("all attempted nonlocal network mechanisms are blocked without making a request", () => {
  child(`
    const assert = require('node:assert/strict');
    const guard = require(${JSON.stringify(boundaryPath)});
    guard.assertURL('http://127.0.0.1:8098/');
    for (const input of ['https://127.0.0.1:8098/', 'http://127.0.0.1:8088/', 'http://example.invalid:8098/', 'http://user@127.0.0.1:8098/'])
      assert.throws(() => guard.assertURL(input), /boundary blocked/);
    assert.throws(() => require('node:net').connect(443, 'example.invalid'), /boundary blocked/);
    assert.throws(() => require('node:http').request('http://example.invalid:8098/'), /boundary blocked/);
    assert.throws(() => require('node:https').request('https://example.invalid/'), /boundary blocked/);
    assert.throws(() => require('node:http2').connect('https://example.invalid/'), /boundary blocked/);
    assert.throws(() => require('node:tls').connect(443, 'example.invalid'), /boundary blocked/);
    assert.throws(() => require('node:dns').lookup('example.invalid', () => {}), /boundary blocked/);
    assert.throws(() => require('node:dgram').createSocket('udp4'), /boundary blocked/);
    (async () => { await assert.rejects(fetch('https://example.invalid/'), /boundary blocked/); assert.equal(guard.snapshot().blockedAttempts, 12); })()
      .catch(error => { console.error(error); process.exitCode = 1; });
  `);
});

test("Admin/Functions, subprocess and workers are blocked inside the guarded suite", () => {
  child(`
    const assert = require('node:assert/strict');
    const guard = require(${JSON.stringify(boundaryPath)});
    assert.throws(() => require('firebase-admin/app'), /boundary blocked/);
    assert.throws(() => require('firebase-functions/v2'), /boundary blocked/);
    assert.throws(() => require('node:child_process').spawn('unused'), /boundary blocked/);
    assert.throws(() => new (require('node:worker_threads').Worker)('unused'), /boundary blocked/);
    assert.equal(guard.snapshot().blockedAttempts, 4);
  `);
});

test("invalid environment fails before any Firebase module is imported", () => {
  child(`
    const assert = require('node:assert/strict');
    const Module = require('node:module'); const original = Module._load; let imported = false;
    Module._load = function(name, ...args) { if (name.startsWith('firebase')) imported = true; return original.call(this, name, ...args); };
    assert.throws(() => require(${JSON.stringify(boundaryPath)}), /exact opt-in/);
    assert.equal(imported, false);
  `, {GCLOUD_PROJECT: "production-example"});
});
