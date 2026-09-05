"use strict";

const assert = require("node:assert/strict");
const {test} = require("node:test");
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const {isolatedEnvironment, validateEnvironment} = require("./environment.cjs");

function child(script, override = {}) {
  return spawnSync(process.execPath, ["-e", script], {
    cwd: __dirname,
    env: {...isolatedEnvironment(), ...override},
    encoding: "utf8", timeout: 15_000,
  });
}

test("environment requires the exact opt-in, project and all three emulator endpoints", () => {
  assert.doesNotThrow(() => validateEnvironment(isolatedEnvironment()));
  for (const [key, value] of [
    ["UAC_ANDROID_LOCAL", ""], ["GCLOUD_PROJECT", "ukrainiancommunity-dbd5f"],
    ["GOOGLE_CLOUD_PROJECT", "other"], ["FIRESTORE_EMULATOR_HOST", ""],
    ["FIRESTORE_EMULATOR_HOST", "localhost:8088"], ["FIREBASE_AUTH_EMULATOR_HOST", "accounts.google.com:443"],
    ["FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199"],
    ["FIREBASE_CONFIG", JSON.stringify({projectId: "production"})],
    ["FIREBASE_CONFIG", JSON.stringify({projectId: "demo-uac-android", storageBucket: "production.appspot.com"})],
    ["FIREBASE_CONFIG", "/secret/file.json"],
    ["GOOGLE_APPLICATION_CREDENTIALS", "/not-read.json"], ["FIREBASE_TOKEN", "not-a-real-token"],
    ["HTTPS_PROXY", "http://example.invalid"], ["NODE_OPTIONS", "--require /other.js"],
  ]) assert.throws(() => validateEnvironment({...isolatedEnvironment(), [key]: value}), /harness/);
});

test("rejects invalid configuration before loading any Admin application", () => {
  const result = child(`const assert = require('node:assert/strict');
    const admin = require('firebase-admin/app');
    assert.throws(() => require('./preload.cjs'), /harness/);
    assert.equal(admin.getApps().length, 0);`, {GCLOUD_PROJECT: "production"});
  assert.equal(result.status, 0, result.stderr);
});

test("refuses an already initialized Admin app instead of adopting its credentials", () => {
  const result = child(`require('firebase-admin/app').initializeApp({projectId: 'production'});
    require('node:assert/strict').throws(() => require('./preload.cjs'), /previous Admin/);`);
  assert.equal(result.status, 0, result.stderr);
});

test("all configured emulator URLs are accepted and other protocols, ports, credentials and hosts fail closed", () => {
  const result = child(`const assert = require('node:assert/strict');
    const boundary = require('./preload.cjs');
    for (const port of [8088, 9098, 9198, 5008]) boundary.assertURL('http://127.0.0.1:' + port + '/demo');
    for (const target of ['http://example.invalid:8088', 'https://127.0.0.1:8088',
      'http://127.0.0.1:9998', 'http://169.254.169.254', 'http://localhost:9999',
      'http://user:pass@localhost:8088', 'file:///tmp/value']) {
      assert.throws(() => boundary.assertURL(target), /boundary/);
    }`);
  assert.equal(result.status, 0, result.stderr);
});

test("blocks actual outbound attempts across Node HTTP, fetch, sockets, DNS, TLS, HTTP2, UDP and children", () => {
  const result = child(`(async () => {
    const assert = require('node:assert/strict');
    const boundary = require('./preload.cjs');
    const attempts = [
      () => require('node:http').get('http://example.invalid'),
      () => require('node:https').get('https://fcm.googleapis.com'),
      () => require('node:net').connect(443, 'example.invalid'),
      () => require('node:net').connect({path: '/tmp/socket'}),
      () => require('node:tls').connect(443, 'example.invalid'),
      () => require('node:http2').connect('https://firestore.googleapis.com'),
      () => require('node:dns').lookup('example.invalid', () => {}),
      () => require('node:dns').resolve4('example.invalid', () => {}),
      () => require('node:dgram').createSocket('udp4'),
      () => require('node:child_process').execFile('curl', ['https://example.invalid']),
      () => new (require('node:worker_threads').Worker)('', {eval: true}),
    ];
    for (const attempt of attempts) assert.throws(attempt, /boundary/);
    await assert.rejects(fetch('https://example.invalid'), /boundary/);
    const {request} = await import('node:https');
    assert.throws(() => request('https://example.invalid'), /boundary/);
    assert.equal(boundary.snapshot().blockedAttempts, attempts.length + 2);
  })().catch(error => { console.error(error); process.exitCode = 1; });`);
  assert.equal(result.status, 0, result.stderr);
});

test("Admin uses only dummy emulator credentials and Messaging is an in-memory fake", () => {
  const result = child(`(async () => {
    const assert = require('node:assert/strict');
    const boundary = require('./preload.cjs');
    const admin = require('firebase-admin/app');
    assert.equal(admin.getApp().options.projectId, 'demo-uac-android');
    assert.equal((await admin.getApp().options.credential.getAccessToken()).access_token, 'owner');
    assert.throws(() => admin.initializeApp({projectId:'production'}, 'other'), /boundary/);
    assert.throws(() => admin.applicationDefault(), /boundary/);
    const sender = require('firebase-admin/messaging').getMessaging();
    const response = await sender.sendEachForMulticast({tokens: ['synthetic-token'], fids: ['a123456789012345678901']});
    assert.equal(response.successCount, 2);
    assert.equal(response.responses.every(value => value.messageId.startsWith('android-local-fake-')), true);
    assert.equal(boundary.snapshot().fakePushTargets, 2);
  })().catch(error => { console.error(error); process.exitCode = 1; });`);
  assert.equal(result.status, 0, result.stderr);
});

test("compiled application exports only callable endpoints: no scheduler, Firestore trigger or public HTTP", () => {
  const result = child(`const assert = require('node:assert/strict');
    const callables = require('./index.cjs');
    assert.ok(Object.keys(callables).length >= 60);
    for (const value of Object.values(callables)) {
      assert.ok(value.__endpoint.callableTrigger);
      assert.equal(value.__endpoint.eventTrigger, undefined);
      assert.equal(value.__endpoint.scheduleTrigger, undefined);
      assert.equal(value.__endpoint.httpsTrigger, undefined);
    }
    assert.equal(callables.registerForEvent instanceof Function, true);
    assert.equal(callables.notifyFeedbackCreated, undefined);
    assert.equal(require('./preload.cjs').snapshot().blockedAttempts, 0);
    console.log('Callable-only endpoints:', Object.keys(callables).length);`);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Callable-only endpoints:/);
});

test("clean child environment never copies credentials or user cloud configuration", () => {
  const env = isolatedEnvironment({PATH: process.env.PATH, HOME: '/not-copied',
    GOOGLE_APPLICATION_CREDENTIALS: '/not-copied', FIREBASE_TOKEN: 'not-copied'});
  assert.equal(env.HOME, undefined);
  assert.equal(env.GOOGLE_APPLICATION_CREDENTIALS, undefined);
  assert.equal(env.FIREBASE_TOKEN, undefined);
  assert.equal(path.isAbsolute(__dirname), true);
});
