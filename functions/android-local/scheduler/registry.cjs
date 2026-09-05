"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const {randomUUID} = require("node:crypto");
const {projectId} = require("./environment.cjs");

const cases = Object.freeze([
  "future", "news", "event", "austria", "admin", "moderator", "role-lost", "restricted", "missing-org", "unapproved-org",
  "duplicate-news", "duplicate-event", "concurrent", "active-lease", "expired-lease", "changed-date", "changed-role",
  "lookup-error", "replaced-lease", "deleted-candidate", "sentinel",
]);
const file = path.join(__dirname, "run.local");
const nextFile = path.join(__dirname, "handoff.local");
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function target(runId, name) {
  assert.match(runId, uuid); assert.ok(cases.includes(name));
  const base = `sched-${runId}-${name}`;
  const collection = ["event", "duplicate-event"].includes(name) ? "events" : "news";
  return Object.freeze({name, collection, uid: `${base}-user`, orgId: `${base}-org`, id: `${base}-content`, duplicateId: `${base}-duplicate`,
    user: `users/${base}-user`, organization: `organizations/${base}-org`, content: `${collection}/${base}-content`,
    duplicate: `${collection}/${base}-duplicate`, lease: `scheduledPublicationLeases/${collection}_${base}-content`});
}
function expectedPaths(runId) {
  return cases.flatMap(name => { const value = target(runId, name); return [value.user, value.organization, value.content, value.duplicate, value.lease]; }).sort();
}
function validate(value) {
  assert.deepEqual(Object.keys(value).sort(), ["paths", "phase", "projectId", "runId", "runnerPid", "version", "workerPid"]);
  assert.equal(value.version, 1); assert.equal(value.projectId, projectId); assert.match(value.runId, uuid);
  assert.ok(Number.isSafeInteger(value.runnerPid) && value.runnerPid > 0);
  assert.ok(Number.isSafeInteger(value.workerPid) && value.workerPid >= 0);
  assert.ok(["prepared", "active"].includes(value.phase));
  assert.deepEqual(value.paths, expectedPaths(value.runId));
  return Object.freeze({...value, paths: Object.freeze([...value.paths])});
}
function read() {
  assert.equal(fs.existsSync(nextFile), false, "Incomplete scheduler ownership handoff retained; inspect before recovery.");
  const stat = fs.lstatSync(file);
  assert.ok(stat.isFile() && !stat.isSymbolicLink() && stat.size > 0 && stat.size <= 32_768);
  return validate(JSON.parse(fs.readFileSync(file, "utf8")));
}
function prepare() {
  const runId = randomUUID();
  assert.equal(fs.existsSync(nextFile), false);
  const value = validate({version: 1, projectId, runId, runnerPid: process.pid, workerPid: 0, phase: "prepared", paths: expectedPaths(runId)});
  // Exclusive write: an earlier/partial manifest cannot be silently replaced or treated as absence.
  const descriptor = fs.openSync(file, "wx", 0o600);
  try { fs.writeFileSync(descriptor, JSON.stringify(value)); fs.fsyncSync(descriptor); }
  finally { fs.closeSync(descriptor); }
  const directory = fs.openSync(__dirname, "r");
  try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
  assert.deepEqual(read(), value);
  return value;
}
function removeAfterReadback(value) {
  assert.deepEqual(read(), value);
  fs.unlinkSync(file);
  const directory = fs.openSync(__dirname, "r");
  try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
  assert.equal(fs.existsSync(file), false);
}
function ownerAlive(value) {
  validate(value);
  return [value.runnerPid, value.workerPid].filter(pid => pid > 0).some(pid => {
    try { process.kill(pid, 0); return true; }
    catch (error) { return error.code !== "ESRCH"; }
  });
}
function replace(value) {
  validate(value);
  const descriptor = fs.openSync(nextFile, "wx", 0o600);
  try { fs.writeFileSync(descriptor, JSON.stringify(value)); fs.fsyncSync(descriptor); }
  finally { fs.closeSync(descriptor); }
  assert.deepEqual(JSON.parse(fs.readFileSync(nextFile, "utf8")), value);
  fs.renameSync(nextFile, file);
  const directory = fs.openSync(__dirname, "r");
  try { fs.fsyncSync(directory); } finally { fs.closeSync(directory); }
  assert.deepEqual(read(), value);
  return value;
}
function attachWorker() {
  const old = read();
  assert.equal(old.workerPid, 0); assert.equal(old.phase, "prepared");
  assert.equal(process.ppid, old.runnerPid);
  return replace({...old, workerPid: process.pid});
}
// Caller must prove every finite target absent first. No mutation is allowed before this durable activation.
function activateOwned(value) {
  assert.deepEqual(read(), value); assert.equal(value.workerPid, process.pid); assert.equal(value.phase, "prepared");
  return replace({...value, phase: "active"});
}
module.exports = {cases, target, expectedPaths, validate, read, prepare, attachWorker, activateOwned, removeAfterReadback, ownerAlive, file};
