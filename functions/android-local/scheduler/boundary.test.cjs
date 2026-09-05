"use strict";

// Separate child processes make each guard/import assertion independent. No emulator listener is needed.
const assert = require("node:assert/strict");
const {test} = require("node:test");
const {spawnSync} = require("node:child_process");
const path = require("node:path");
const {validateEnvironment, isolatedEnvironment, projectId} = require("./environment.cjs");
validateEnvironment(process.env);
assert.equal(process.env.UAC_SCHEDULER_MODE, "boundary");
const boundaryPath = JSON.stringify(path.join(__dirname, "boundary.cjs"));
const registryPath = JSON.stringify(path.join(__dirname, "registry.cjs"));
function child(source, override = {}) {
  const result = spawnSync(process.execPath, ["-e", `"use strict"; const assert = require("node:assert/strict"); ${source}`], {
    cwd: path.resolve(__dirname, "../.."), env: {...isolatedEnvironment(), ...override}, encoding: "utf8", timeout: 20_000, maxBuffer: 128 * 1024,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, `Boundary child failed: ${result.stderr}`);
}

test("wrong project, aliases, port and host fail before Admin import", () => {
  for (const change of [
    {UAC_SCHEDULER_LOCAL: "0"}, {GCLOUD_PROJECT: "production-not-allowed"}, {GOOGLE_CLOUD_PROJECT: "demo-other"},
    {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8088"}, {FIRESTORE_EMULATOR_HOST: "localhost:8098"},
    {FIRESTORE_EMULATOR_HOST: "firestore.googleapis.com:443"}, {FIRESTORE_EMULATOR_HOST: "127.0.0.1:8098/path"},
  ]) child(`assert.throws(() => require(${boundaryPath})); assert.equal(Object.keys(require.cache).some(p => p.includes("/firebase-admin/")), false);`, change);
});
test("credentials, metadata, extra Firebase config and proxy fail before Admin", () => {
  for (const change of [
    {GOOGLE_APPLICATION_CREDENTIALS: "/synthetic/not-a-key.json"}, {FIREBASE_TOKEN: "synthetic-not-a-token"},
    {HTTPS_PROXY: "http://127.0.0.1:8098"}, {GCE_METADATA_HOST: "metadata.google.internal"},
    {METADATA_SERVER_DETECTION: ""}, {FIREBASE_CONFIG: "{}"}, {FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9098"},
    {FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9198"},
  ]) child(`assert.throws(() => require(${boundaryPath})); assert.equal(Object.keys(require.cache).some(p => p.includes("/firebase-admin/")), false);`, change);
});
test("inherited loaders are rejected by validation and never copied into child environment", () => {
  const base = isolatedEnvironment();
  for (const key of ["NODE_OPTIONS", "NODE_PATH", "GOOGLE_ACCESS_TOKEN", "HTTP_PROXY"]) {
    assert.throws(() => validateEnvironment({...base, [key]: "synthetic"}));
    assert.equal(Object.hasOwn(isolatedEnvironment({...base, [key]: "synthetic"}), key), false);
  }
  assert.equal(Object.hasOwn(isolatedEnvironment({HOME: "/synthetic", PATH: process.env.PATH}), "HOME"), false);
});
test("Admin imported before the boundary is rejected without initialization", () => {
  child(`require("firebase-admin/app"); assert.throws(() => require(${boundaryPath}), /before the guard/); assert.equal(require("firebase-admin/app").getApps().length, 0);`);
});
test("only exact loopback HTTP target is accepted, URL credentials and alternative ports denied", () => {
  child(`const b = require(${boundaryPath}); b.assertURL("http://127.0.0.1:8098/v1/projects/${projectId}");
    for (const value of ["https://127.0.0.1:8098", "http://localhost:8098", "http://127.0.0.1:8088", "http://user:pass@127.0.0.1:8098", "http://169.254.169.254", "https://firestore.googleapis.com", "file:///synthetic"]) assert.throws(() => b.assertURL(value));
    assert.equal(b.snapshot().blockedAttempts, 7);`);
});
test("actual network/process entry points reject outbound, metadata, Unix and inherited sockets", () => {
  child(`const b = require(${boundaryPath});
    const attempts = [
      () => require("node:net").connect({host: "169.254.169.254", port: 80}),
      () => require("node:net").connect({path: "/synthetic/socket"}),
      () => require("node:net").connect({fd: 9}),
      () => require("node:net").createConnection({fd: 9}),
      () => new (require("node:net").Socket)({fd: 9}),
      () => require("node:net").Socket({fd: 9}),
      () => new (require("node:net").Socket)({handle: {}}),
      () => require("node:http").request("http://firestore.googleapis.com"),
      () => require("node:https").request("https://example.invalid"),
      () => require("node:tls").connect({host: "example.invalid", port: 443}),
      () => require("node:http2").connect("https://firestore.googleapis.com"),
      () => require("node:dns").lookup("metadata.google.internal", () => {}),
      () => require("node:dns").resolve4("example.invalid", () => {}),
      () => require("node:child_process").spawn("false"),
      () => require("node:dgram").createSocket("udp4"),
      () => new (require("node:worker_threads").Worker)("synthetic"),
    ];
    for (const attempt of attempts) assert.throws(attempt, /boundary blocked/);
    assert.equal(b.snapshot().blockedAttempts, attempts.length);`);
});
test("fetch validates destination and forces redirect error without opening a socket", () => {
  child(`let captured; globalThis.fetch = async (input, options) => { captured = options; return {status: 200}; };
    const b = require(${boundaryPath});
    (async () => {
      await assert.rejects(fetch("https://example.invalid"), /boundary blocked/);
      await fetch("http://127.0.0.1:8098/synthetic", {redirect: "follow"}); assert.equal(captured.redirect, "error");
      assert.equal(b.snapshot().blockedAttempts, 1);
    })().catch(error => { console.error(error); process.exitCode = 1; });`);
});
test("Auth, Storage, Messaging, ADC and additional Admin are throw-only", () => {
  child(`const b = require(${boundaryPath}); const app = require("firebase-admin/app");
    const attempts = [() => require("firebase-admin/auth").getAuth().deleteUser("synthetic"),
      () => require("firebase-admin/storage").getStorage().bucket(),
      () => require("firebase-admin/messaging").getMessaging().send({}),
      () => app.applicationDefault(), () => app.initializeApp(), () => app.cert({}), () => app.refreshToken({}),
      () => require("firebase-admin")];
    for (const attempt of attempts) assert.throws(attempt, /boundary blocked/);
    assert.equal(app.getApps().length, 1); assert.equal(app.getApp().options.projectId, "${projectId}");
    assert.equal(b.snapshot().blockedAttempts, attempts.length);`);
});
test("real worker import only registers a disabled schedule, never invokes it", () => {
  child(`const b = require(${boundaryPath}); const worker = require("./lib/content/scheduledPublishing.js");
    assert.equal(typeof worker.publishScheduledCandidate, "function"); assert.equal(b.snapshot().schedulesRegistered, 1);
    assert.equal(b.snapshot().mutations, 0); assert.throws(() => worker.publishScheduledContent(), /cron invocation/);
    assert.equal(b.snapshot().cronCalls, 1); assert.equal(b.snapshot().blockedAttempts, 1);`);
});
test("finite registry rejects altered project, extra paths, bad phase and replacing scope", () => {
  child(`const r = require(${registryPath}); const b = require(${boundaryPath});
    const runId = "00000000-0000-4000-8000-000000000001";
    const value = {version: 1, runId, projectId: "${projectId}", runnerPid: process.pid, workerPid: process.pid, phase: "active", paths: r.expectedPaths(runId)};
    assert.equal(value.paths.length, 105); assert.equal(new Set(value.paths).size, 105); r.validate(value);
    for (const invalid of [{...value, projectId: "demo-other"}, {...value, phase: "unknown"}, {...value, paths: [...value.paths, "news/unrelated"]}, {...value, extra: true}]) assert.throws(() => r.validate(invalid));
    assert.throws(() => b.installRegistry({...value, phase: "prepared"}), /inactive registry/);
    b.installRegistry(value); assert.throws(() => b.installRegistry(value), /registry replacement/);
    for (const method of ["create", "set", "update", "delete"]) {
      const batch = b.db.batch(); assert.throws(() => batch[method](b.db.doc("news/unregistered"), {synthetic: true}), /unregistered mutation path/);
    }
    assert.throws(() => b.db.bulkWriter(), /bulk writer/); assert.throws(() => b.db.recursiveDelete(), /recursive delete/);
    assert.equal(b.snapshot().mutations, 0);`);
});
test("cleanup attempts every exact owned path and retains marker after one failure", () => {
  child(`const r = require(${registryPath}); let removed = false; r.removeAfterReadback = () => { removed = true; };
    const {cleanupOwned} = require(${JSON.stringify(path.join(__dirname, "cleanup.cjs"))});
    const deletes = [], reads = [];
    const db = {doc: path => ({delete: async () => { deletes.push(path); if (path === "news/two") throw new Error("synthetic-cleanup-failure"); }, get: async () => { reads.push(path); return {exists: false}; }})};
    (async () => {
      await assert.rejects(cleanupOwned(db, {phase: "active", paths: ["news/one", "news/two", "news/three"]}), AggregateError);
      assert.deepEqual(deletes, ["news/three", "news/two", "news/one"]); assert.deepEqual(reads, ["news/three", "news/one"]); assert.equal(removed, false);
    })().catch(error => { console.error(error); process.exitCode = 1; });`);
});
test("cleanup cannot delete a pre-activation collision or silently ignore failed read-back", () => {
  child(`const r = require(${registryPath}); let removed = false; r.removeAfterReadback = () => { removed = true; };
    const {cleanupOwned} = require(${JSON.stringify(path.join(__dirname, "cleanup.cjs"))});
    let deletes = 0, reads = 0;
    const db = {doc: path => ({delete: async () => { deletes++; }, get: async () => { reads++; return {exists: path === "news/collision"}; }})};
    (async () => {
      await assert.rejects(cleanupOwned(db, {phase: "prepared", paths: ["news/collision", "news/absent"]}), AggregateError);
      assert.equal(deletes, 0); assert.equal(reads, 2); assert.equal(removed, false);
      await assert.rejects(cleanupOwned(db, {phase: "active", paths: ["news/collision"]}), AggregateError);
      assert.equal(deletes, 1); assert.equal(removed, false);
    })().catch(error => { console.error(error); process.exitCode = 1; });`);
});
test("successful exact cleanup reads all absences before removing marker", () => {
  child(`const r = require(${registryPath}); const events = []; r.removeAfterReadback = () => { events.push("remove-marker"); };
    const {cleanupOwned} = require(${JSON.stringify(path.join(__dirname, "cleanup.cjs"))});
    const db = {doc: path => ({delete: async () => { events.push("delete:" + path); }, get: async () => { events.push("get:" + path); return {exists: false}; }})};
    (async () => {
      await cleanupOwned(db, {phase: "active", paths: ["news/one", "news/two"]});
      assert.deepEqual(events, ["delete:news/two", "get:news/two", "delete:news/one", "get:news/one", "remove-marker"]);
    })().catch(error => { console.error(error); process.exitCode = 1; });`);
});
