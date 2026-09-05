"use strict";

const {validateEnvironment, projectId} = require("./environment.cjs");
validateEnvironment(process.env);

// Install the boundary before loading firebase-admin or any application module.
// This is a development guard against accidental egress, not an OS security sandbox.
const net = require("node:net");
const http = require("node:http");
const https = require("node:https");
const http2 = require("node:http2");
const tls = require("node:tls");
const dns = require("node:dns");
const childProcess = require("node:child_process");
const dgram = require("node:dgram");
const workerThreads = require("node:worker_threads");
const Module = require("node:module");

const allowedPorts = new Set([8088, 9098, 9198, 5008]);
const allowedHosts = new Set(["127.0.0.1", "localhost"]);
const state = {blockedAttempts: 0, fakePushBatches: 0, fakePushTargets: 0};

function blocked(kind) {
  state.blockedAttempts++;
  throw new Error(`Android local boundary blocked ${kind}.`);
}

function assertSocketTarget(args) {
  if (Array.isArray(args[0])) return assertSocketTarget(args[0]);
  const first = args[0];
  const options = typeof first === "object" && first !== null
    ? first : {port: first, host: typeof args[1] === "string" ? args[1] : "localhost"};
  if (options.path || options.fd !== undefined
    || !allowedHosts.has(options.hostname ?? options.host ?? "localhost")
    || !allowedPorts.has(Number(options.port))) blocked("socket target");
}

function assertURL(input) {
  let url;
  try { url = new URL(input); } catch { blocked("invalid URL"); }
  if (url.protocol !== "http:" || url.username || url.password
    || !allowedHosts.has(url.hostname) || !allowedPorts.has(Number(url.port))) {
    blocked("HTTP target");
  }
}

const socketConnect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  assertSocketTarget(args);
  return socketConnect.apply(this, args);
};
const request = http.request;
http.request = function (...args) {
  const first = args[0];
  if (typeof first === "string" || first instanceof URL) assertURL(first);
  else {
    if (first?.protocol && first.protocol !== "http:") blocked("HTTP protocol");
    if (first?.socketPath) blocked("HTTP Unix socket");
    // HTTP's path is a URL path, not net.Socket's Unix-domain path.
    assertSocketTarget([{...first, path: undefined}]);
  }
  return request.apply(this, args);
};
http.get = function (...args) { const result = http.request(...args); result.end(); return result; };
for (const key of ["request", "get"]) https[key] = () => blocked("TLS HTTP request");
tls.connect = () => blocked("TLS socket");
const connectHTTP2 = http2.connect;
http2.connect = function (authority, ...args) {
  assertURL(authority);
  return connectHTTP2.call(this, authority, ...args);
};
const originalFetch = globalThis.fetch;
globalThis.fetch = async function (input, options = {}) {
  assertURL(input instanceof Request ? input.url : input);
  return originalFetch(input, {...options, redirect: "error"});
};
for (const target of [dns, dns.promises]) {
  for (const key of Object.keys(target)) {
    if (key.startsWith("resolve") || key === "reverse") target[key] = () => blocked("DNS resolution");
  }
  const lookup = target.lookup;
  target.lookup = function (hostname, ...args) {
    if (!allowedHosts.has(hostname)) blocked("DNS lookup");
    return lookup.call(this, "127.0.0.1", ...args);
  };
}
for (const key of ["exec", "execFile", "execSync", "execFileSync", "spawn", "spawnSync", "fork"]) {
  childProcess[key] = () => blocked("child process");
}
dgram.createSocket = () => blocked("UDP socket");
workerThreads.Worker = function () { blocked("worker thread"); };
Module.syncBuiltinESMExports();

const admin = require("firebase-admin/app");
if (admin.getApps().length !== 0) blocked("previous Admin initialization");
// Admin Firestore/Storage require their concrete certificate credential class.
// Generate an unregistered, ephemeral key in memory; never read ADC/key files.
// It has no cloud authority and is not persisted. Emulator RPCs use `owner`.
const {privateKey} = require("node:crypto").generateKeyPairSync("rsa", {modulusLength: 2048});
const credential = admin.cert({projectId,
  clientEmail: `local-only@${projectId}.iam.gserviceaccount.com`,
  privateKey: privateKey.export({type: "pkcs8", format: "pem"}),
});
credential.getAccessToken = async () => ({access_token: "owner", expires_in: 3600});
Object.freeze(credential);
admin.initializeApp({projectId, storageBucket: `${projectId}.appspot.com`, credential});

const fakeMessaging = Object.freeze({
  async sendEachForMulticast(message) {
    const count = (message.tokens?.length ?? 0) + (message.fids?.length ?? 0);
    if (!Number.isSafeInteger(count) || count < 1 || count > 500) blocked("invalid fake multicast");
    state.fakePushBatches++;
    state.fakePushTargets += count;
    return {successCount: count, failureCount: 0,
      responses: Array.from({length: count}, (_, index) => ({success: true,
        messageId: `android-local-fake-${state.fakePushBatches}-${index}`}))};
  },
});
const loadModule = Module._load;
Module._load = function (name, parent, isMain) {
  if (name === "firebase-admin/messaging") {
    return {getMessaging: () => fakeMessaging};
  }
  if (name === "firebase-admin/app") {
    return {...admin,
      initializeApp(options = {}, appName) {
        if (options.credential || (options.projectId && options.projectId !== projectId)
          || (options.storageBucket && options.storageBucket !== `${projectId}.appspot.com`)
          || options.databaseURL) blocked("Admin app configuration");
        return admin.initializeApp({...options, projectId, storageBucket: `${projectId}.appspot.com`, credential}, appName);
      },
      applicationDefault: () => blocked("default credentials"),
      cert: () => blocked("service-account credentials"),
      refreshToken: () => blocked("refresh-token credentials"),
    };
  }
  return loadModule.call(this, name, parent, isMain);
};

module.exports = {snapshot: () => Object.freeze({...state}), assertURL};
