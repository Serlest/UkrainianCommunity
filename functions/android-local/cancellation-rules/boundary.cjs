"use strict";

const {validateEnvironment, host, port} = require("./environment.cjs");
validateEnvironment(process.env); // Before any Firebase SDK import or initialization.
const net = require("node:net");
const http = require("node:http");
const https = require("node:https");
const http2 = require("node:http2");
const tls = require("node:tls");
const dns = require("node:dns");
const childProcess = require("node:child_process");
const dgram = require("node:dgram");
const workers = require("node:worker_threads");
const Module = require("node:module");
let blockedAttempts = 0;
function blocked(kind) { blockedAttempts++; throw new Error(`Cancellation Rules boundary blocked ${kind}.`); }
function assertURL(input) {
  let url;
  try { url = new URL(input); } catch { blocked("invalid URL"); }
  if (url.protocol !== "http:" || url.hostname !== host || Number(url.port) !== port || url.username || url.password) blocked("HTTP target");
}
function assertSocket(args) {
  if (Array.isArray(args[0])) return assertSocket(args[0]);
  const first = args[0];
  const value = first && typeof first === "object" ? first : {port: first, host: args[1]};
  if (value.path || value.fd !== undefined || (value.hostname ?? value.host) !== host || Number(value.port) !== port) blocked("socket target");
}
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) { assertSocket(args); return connect.apply(this, args); };
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
http.get = function (...args) { const value = http.request(...args); value.end(); return value; };
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
  for (const key of Object.keys(target)) if (key.startsWith("resolve") || key === "reverse") target[key] = () => blocked("DNS");
  const lookup = target.lookup;
  target.lookup = function (hostname, ...args) {
    if (hostname !== host) blocked("DNS host");
    return lookup.call(this, host, ...args);
  };
}
for (const key of ["spawn", "spawnSync", "fork", "exec", "execSync", "execFile", "execFileSync"]) childProcess[key] = () => blocked("child process");
dgram.createSocket = () => blocked("UDP");
workers.Worker = function () { blocked("worker"); };
const load = Module._load;
Module._load = function (name, ...args) {
  if (/^firebase-admin(?:\/|$)|^firebase-functions(?:\/|$)/.test(name)) blocked("Admin or Functions import");
  return load.call(this, name, ...args);
};
Module.syncBuiltinESMExports();
module.exports = {assertURL, assertSocket, snapshot: () => ({blockedAttempts})};
