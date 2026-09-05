"use strict";

const {validateEnvironment, projectId, host, port} = require("./environment.cjs");
validateEnvironment(process.env);
if (Object.keys(require.cache).some(value => /[/\\]node_modules[/\\]firebase-admin[/\\]/.test(value))) {
  throw new Error("Scheduler boundary refuses an Admin import made before the guard.");
}

const net = require("node:net");
const http = require("node:http");
const https = require("node:https");
const http2 = require("node:http2");
const tls = require("node:tls");
const dns = require("node:dns");
const child = require("node:child_process");
const dgram = require("node:dgram");
const workers = require("node:worker_threads");
const Module = require("node:module");
const state = {blockedAttempts: 0, schedulesRegistered: 0, cronCalls: 0, logCalls: 0, mutations: 0};
let registeredPaths;
let database;
function blocked(kind) { state.blockedAttempts++; throw new Error(`Scheduler boundary blocked ${kind}.`); }
function assertURL(input) {
  let url; try { url = new URL(input); } catch { blocked("invalid URL"); }
  if (url.protocol !== "http:" || url.hostname !== host || Number(url.port) !== port || url.username || url.password) blocked("HTTP target");
}
function assertSocket(args) {
  if (Array.isArray(args[0])) return assertSocket(args[0]);
  const first = args[0];
  const value = first && typeof first === "object" ? first : {port: first, host: args[1]};
  if (value.path || value.fd !== undefined || value.handle !== undefined || (value.hostname ?? value.host) !== host || Number(value.port) !== port) blocked("socket target");
}
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) { assertSocket(args); return connect.apply(this, args); };
// net.connect creates a Socket before it reaches prototype.connect. Reject inherited fd/handles first.
const createConnection = net.createConnection;
net.connect = net.createConnection = function (...args) {
  assertSocket(args);
  return createConnection.apply(this, args);
};
function assertSocketConstructor(args) {
  const options = args[0];
  if (options && typeof options === "object" && (options.fd !== undefined || options.handle !== undefined)) {
    blocked("inherited socket");
  }
}
net.Socket = new Proxy(net.Socket, {
  construct(target, args, newTarget) {
    assertSocketConstructor(args);
    return Reflect.construct(target, args, newTarget);
  },
  apply(target, receiver, args) {
    assertSocketConstructor(args);
    return Reflect.apply(target, receiver, args);
  },
});
const request = http.request;
http.request = function (...args) {
  if (typeof args[0] === "string" || args[0] instanceof URL) assertURL(args[0]);
  else {
    const options = args[0];
    if (options?.socketPath || options?.protocol && options.protocol !== "http:") blocked("HTTP protocol");
    assertSocket([{...options, path: undefined}]);
  }
  return request.apply(this, args);
};
http.get = function (...args) { const result = http.request(...args); result.end(); return result; };
https.request = https.get = () => blocked("HTTPS");
tls.connect = () => blocked("TLS");
const connect2 = http2.connect;
http2.connect = function (authority, ...args) { assertURL(authority); return connect2.call(this, authority, ...args); };
const fetch = globalThis.fetch;
globalThis.fetch = async function (input, options = {}) {
  assertURL(input instanceof Request ? input.url : input);
  return fetch(input, {...options, redirect: "error"});
};
for (const target of [dns, dns.promises]) {
  for (const key of Object.keys(target)) if (key.startsWith("resolve") || key === "reverse") target[key] = () => blocked("DNS resolution");
  const lookup = target.lookup;
  target.lookup = function (hostname, ...args) {
    if (hostname !== host) blocked("DNS host");
    return lookup.call(this, host, ...args);
  };
}
for (const key of ["spawn", "spawnSync", "fork", "exec", "execSync", "execFile", "execFileSync"]) child[key] = () => blocked("child process");
dgram.createSocket = () => blocked("UDP");
workers.Worker = function () { blocked("worker thread"); };
Module.syncBuiltinESMExports();

// Module hooks precede Admin initialization and every application import.
const load = Module._load;
let safeAdmin;
const service = name => new Proxy(Object.freeze({}), {get() { return () => blocked(name); }});
Module._load = function (name, parent, isMain) {
  if (name === "firebase-admin/auth") return {getAuth: () => service("Auth operation")};
  if (name === "firebase-admin/storage") return {getStorage: () => service("Storage operation")};
  if (name === "firebase-admin/messaging") return {getMessaging: () => service("Messaging operation")};
  if (name === "firebase-admin/app" && safeAdmin) return safeAdmin;
  if (name === "firebase-admin") blocked("namespace Admin import");
  if (name === "firebase-functions/logger") return Object.freeze(Object.fromEntries(["debug", "info", "warn", "error", "log", "write"]
    .map(key => [key, () => { state.logCalls++; }])));
  if (name === "firebase-functions/v2/scheduler") return {onSchedule() {
    state.schedulesRegistered++;
    return () => { state.cronCalls++; blocked("cron invocation"); };
  }};
  if (name === "firebase-functions/v2/https") return {HttpsError: load.call(this, name, parent, isMain).HttpsError};
  if (/^firebase-functions(?:\/|$)/.test(name)) blocked("unreviewed Functions import");
  return load.call(this, name, parent, isMain);
};
const admin = load.call(Module, "firebase-admin/app", module, false);
if (admin.getApps().length !== 0) blocked("previous Admin initialization");
const {privateKey} = require("node:crypto").generateKeyPairSync("rsa", {modulusLength: 2048});
const credential = admin.cert({projectId, clientEmail: `local-only@${projectId}.iam.gserviceaccount.com`,
  privateKey: privateKey.export({type: "pkcs8", format: "pem"})});
credential.getAccessToken = async () => ({access_token: "owner", expires_in: 3600});
Object.freeze(credential);
admin.initializeApp({projectId, credential});
safeAdmin = {...admin,
  initializeApp: () => blocked("additional Admin app"), applicationDefault: () => blocked("ADC"),
  cert: () => blocked("external certificate"), refreshToken: () => blocked("refresh token"),
};
const firestore = require("firebase-admin/firestore");
database = firestore.getFirestore(admin.getApp());
database.settings({ignoreUndefinedProperties: false});
function assertReference(reference) {
  if (!registeredPaths || reference?.firestore !== database || !registeredPaths.has(reference?.path)) blocked("unregistered mutation path");
}
for (const method of ["create", "set", "update", "delete"]) {
  const original = firestore.WriteBatch.prototype[method];
  if (typeof original !== "function") blocked("unknown WriteBatch implementation");
  firestore.WriteBatch.prototype[method] = function (reference, ...args) {
    assertReference(reference); state.mutations++;
    return original.call(this, reference, ...args);
  };
}
database.bulkWriter = () => blocked("bulk writer");
database.recursiveDelete = () => blocked("recursive delete");
function installRegistry(value) {
  if (registeredPaths) blocked("registry replacement");
  const valid = require("./registry.cjs").validate(value);
  if (valid.phase !== "active") blocked("inactive registry");
  registeredPaths = new Set(valid.paths);
}
module.exports = {assertURL, assertSocket, installRegistry, db: database, snapshot: () => Object.freeze({...state})};
