"use strict";

// Install the exact localhost boundary before loading either Firebase package.
const boundary = require("./boundary.cjs");
const {projectId, host, port} = require("./environment.cjs");
const {after, before, test} = require("node:test");
const assert = require("node:assert/strict");
const {readFileSync} = require("node:fs");
const {randomUUID} = require("node:crypto");
const path = require("node:path");
const {initializeTestEnvironment} = require("@firebase/rules-unit-testing");
const {doc, getDocFromServer: getDoc, setDoc, updateDoc, deleteDoc, deleteField, serverTimestamp} = require("firebase/firestore");

const prefix = `o09-${randomUUID()}`;
const roles = ["org-owner", "org-admin", "org-moderator", "app-owner"];
const uid = (role) => `${prefix}-${role}`;
const organizationId = `${prefix}-organization`;
const time = new Date();
const protectedValues = {
  cancellationState: "cancelled", cancelledAt: time,
  cancelledBy: uid("org-owner"), cancellationReason: "Synthetic cancellation reason",
};
const owned = new Set();
let environment;
let serial = 0;
let assertions = 0;
function track(value) {
  const parts = value.split("/");
  const allowedRoot = ["events", "news", "organizations", "users", "registrations"].includes(parts[0]);
  const ownTopLevel = parts.length === 2 && parts[1].startsWith(prefix);
  const ownRegistration = parts.length === 2 && parts[0] === "registrations" && parts[1].startsWith(`event_${prefix}-`) && parts[1].includes(`_${prefix}-`);
  const ownToken = parts.length === 4 && parts[0] === "users" && parts[1].startsWith(`${prefix}-`)
    && parts[2] === "notificationPushTokens" && parts[3].startsWith(`${prefix}-`);
  assert.ok(allowedRoot && (ownTopLevel || ownRegistration || ownToken), "Only process-owned synthetic fixture paths");
  owned.add(value); return value;
}
function reference(database, value) { assert.ok(owned.has(value)); return doc(database, value); }
function client(role, verified = true) {
  return environment.authenticatedContext(uid(role), {email_verified: verified}).firestore();
}
function item(collection = "events") { return track(`${collection}/${prefix}-${++serial}`); }
function event(value, author = "org-owner", overrides = {}) {
  return {
    id: value.split("/")[1], title: "Synthetic canonical event", summary: "Synthetic summary", details: "Complete isolated event details",
    sourceType: "organization", organizationId, authorId: uid(author), city: "Vienna", venue: "Synthetic hall",
    startDate: new Date(time.getTime() + 86_400_000), endDate: new Date(time.getTime() + 90_000_000),
    createdAt: time, updatedAt: time, requiresRegistration: true, price: 0, registeredCount: 0,
    moderationStatus: "approved", registrationState: "notRegistered", likeCount: 0, likeState: "notLiked",
    viewCount: 0, commentCount: 0, visibility: "public", isAllDay: false, ...overrides,
  };
}
async function seed(value, fields) {
  track(value);
  await environment.withSecurityRulesDisabled(async (context) => setDoc(reference(context.firestore(), value), fields));
}
async function success(promise) { const result = await promise; assertions++; return result; }
async function denied(promise) {
  await assert.rejects(promise, (error) => { assert.equal(error?.code, "permission-denied", "Exact Rules denial, not connectivity or schema transport failure"); return true; });
  assertions++;
}
async function fresh(value) {
  let result;
  await environment.withSecurityRulesDisabled(async (context) => { result = await getDoc(reference(context.firestore(), value)); });
  return result;
}

before(async () => {
  environment = await initializeTestEnvironment({projectId, firestore: {host, port,
    rules: readFileSync(path.resolve(__dirname, "../../..", "Firebase/firestore.rules"), "utf8")}});
  for (const role of [...roles, "app-admin", "stranger", "attendee", "blocked", "mfa-owner"]) {
    await seed(`users/${uid(role)}`, {id: uid(role), globalRole: role === "app-owner" || role === "mfa-owner" ? "owner" : role === "app-admin" ? "admin" : "user",
      accountStatus: role === "blocked" ? "blocked" : "active", blockState: "active", requiresMultiFactorAuth: role === "mfa-owner"});
  }
  await seed(`organizations/${organizationId}`, {id: organizationId, name: "Synthetic cancellation Rules organization", ownerId: uid("org-owner"),
    adminIds: [uid("org-admin"), uid("blocked")], moderatorIds: [uid("org-moderator")], moderationStatus: "approved"});
}, {timeout: 25_000});

after(async () => {
  const failures = [];
  if (environment) {
    // No clearFirestore, collection delete, recursive delete, import or shared Android project.
    for (const value of [...owned].reverse()) {
      try { await environment.withSecurityRulesDisabled(async (context) => {
        const target = reference(context.firestore(), value);
        await deleteDoc(target);
        assert.equal((await getDoc(target)).exists(), false, "Exact synthetic cleanup server read-back");
      }); }
      catch (error) { failures.push(error); }
    }
    try { await environment.cleanup(); } catch (error) { failures.push(error); }
  }
  assert.equal(boundary.snapshot().blockedAttempts, 0, "The SDK must not attempt an outbound or unrelated-service request");
  if (failures.length) throw new AggregateError(failures, "Some exact synthetic fixture cleanup steps failed; all were attempted.");
  console.log(`LOCAL_CANCELLATION_RULES: ${assertions} exact assertions; process-owned fixture cleanup completed; no cloud or delivery claim.`);
}, {timeout: 90_000});

for (const role of roles) {
  test(`${role}: normal create/edit stays allowed; client cancellation fields cannot be created`, async () => {
    const database = client(role); const value = item();
    await success(setDoc(reference(database, value), event(value, role)));
    await success(updateDoc(reference(database, value), {title: "Updated synthetic title", summary: "Updated summary", details: "Updated complete details",
      venue: "Updated hall", contactURL: "https://example.invalid/contact", imageURL: "https://example.invalid/image.jpg",
      localizations: {de: {title: "Titel", summary: "Kurz", details: "Inhalt"}}, mediaMetadata: {alternativeText: "Synthetic description"}, updatedAt: serverTimestamp()}));
    const actual = await fresh(value);
    assert.equal(actual.get("title"), "Updated synthetic title"); assert.equal(actual.get("registeredCount"), 0);
    for (const field of Object.keys(protectedValues)) assert.equal(actual.get(field), undefined);
    for (const [field, content] of Object.entries(protectedValues)) {
      for (const proposed of [content, null]) {
        const target = item();
        await denied(setDoc(reference(database, target), event(target, role, {[field]: proposed})));
        assert.equal((await fresh(target)).exists(), false);
      }
    }
    const active = item();
    await denied(setDoc(reference(database, active), event(active, role, {cancellationState: "active"})));
    const combined = item();
    await denied(setDoc(reference(database, combined), event(combined, role, protectedValues)));
  });

  test(`${role}: cancellation cannot be added by update, merge or full replacement`, async () => {
    const database = client(role); const value = item(); const original = event(value, role);
    await success(setDoc(reference(database, value), original));
    for (const [field, content] of Object.entries(protectedValues)) {
      await denied(updateDoc(reference(database, value), {[field]: content, updatedAt: serverTimestamp()}));
      await denied(setDoc(reference(database, value), {[field]: content, updatedAt: serverTimestamp()}, {merge: true}));
      await denied(setDoc(reference(database, value), {...original, [field]: content}));
    }
    const actual = await fresh(value);
    for (const field of Object.keys(protectedValues)) assert.equal(actual.get(field), undefined);
    assert.equal(actual.get("moderationStatus"), "approved");
  });

  test(`${role}: existing legacy/server cancellation fields cannot be changed, nulled or removed`, async () => {
    const database = client(role);
    for (const [field, content] of Object.entries(protectedValues)) {
      const value = item(); const original = event(value, role, {[field]: content});
      await seed(value, original);
      // cancelledBy was already absent from the client schema. Do not claim this patch
      // enables normal editing of a server-cancelled document or broaden that schema.
      if (field === "cancelledBy") await denied(updateDoc(reference(database, value), {title: "No new editing permission", updatedAt: serverTimestamp()}));
      else await success(updateDoc(reference(database, value), {title: "Preserve legacy marker", updatedAt: serverTimestamp()}));
      const changed = field === "cancelledAt" ? new Date(time.getTime() + 60_000) : "changed-synthetic-value";
      await denied(updateDoc(reference(database, value), {[field]: changed, updatedAt: serverTimestamp()}));
      await denied(updateDoc(reference(database, value), {[field]: null, updatedAt: serverTimestamp()}));
      await denied(updateDoc(reference(database, value), {[field]: deleteField(), updatedAt: serverTimestamp()}));
      const replacement = {...original}; delete replacement[field];
      await denied(setDoc(reference(database, value), replacement));
      const actual = (await fresh(value)).get(field);
      if (content instanceof Date) assert.equal(actual.toMillis(), content.getTime()); else assert.equal(actual, content);
    }
  });
}

test("ordinary denied actors remain denied for normal edits and cancellation attempts", async () => {
  const value = item(); await seed(value, event(value));
  for (const database of [environment.unauthenticatedContext().firestore(), client("stranger"), client("org-owner", false), client("blocked"), client("mfa-owner")]) {
    await denied(updateDoc(reference(database, value), {title: "Denied normal edit", updatedAt: serverTimestamp()}));
    await denied(updateDoc(reference(database, value), {cancellationState: "cancelled", updatedAt: serverTimestamp()}));
  }
  assert.equal((await fresh(value)).get("cancellationState"), undefined);
});

test("app-owned events keep existing app-owner editing but no client cancellation override", async () => {
  const value = item(); const fields = event(value, "app-owner", {sourceType: "app"}); delete fields.organizationId;
  await seed(value, fields); const database = client("app-owner");
  await success(updateDoc(reference(database, value), {title: "App owner normal edit", updatedAt: serverTimestamp()}));
  await denied(updateDoc(reference(database, value), {cancellationState: "cancelled", updatedAt: serverTimestamp()}));
  await denied(updateDoc(reference(client("app-admin"), value), {title: "No admin rewrite", updatedAt: serverTimestamp()}));
});

test("scheduled create/read/text update remains scoped and does not allow cancellation fields", async () => {
  const value = item(); const database = client("org-owner");
  await success(setDoc(reference(database, value), event(value, "org-owner", {moderationStatus: "draft", scheduledAt: new Date(time.getTime() + 3_600_000)})));
  await success(getDoc(reference(database, value)));
  await denied(getDoc(reference(client("stranger"), value)));
  await success(updateDoc(reference(database, value), {details: "Revised scheduled body", updatedAt: serverTimestamp()}));
  await denied(updateDoc(reference(database, value), {cancellationReason: "No scheduled bypass", updatedAt: serverTimestamp()}));
});

test("moderation-only platform path preserves all server cancellation fields", async () => {
  const value = item(); await seed(value, event(value, "org-owner", {...protectedValues, moderationStatus: "archived"}));
  await success(updateDoc(reference(client("app-admin"), value), {moderationStatus: "rejected", updatedAt: serverTimestamp()}));
  await success(updateDoc(reference(client("app-owner"), value), {moderationStatus: "archived", updatedAt: serverTimestamp()}));
  await denied(updateDoc(reference(client("app-owner"), value), {moderationStatus: "approved", cancellationState: "active", updatedAt: serverTimestamp()}));
  const actual = await fresh(value);
  assert.equal(actual.get("cancellationState"), "cancelled"); assert.equal(actual.get("cancelledBy"), uid("org-owner"));
});

test("trusted cancellation marker remains readable to the registered user and denied to strangers", async () => {
  const value = item(); const id = value.split("/")[1];
  await seed(value, event(value, "org-owner", {...protectedValues, moderationStatus: "archived", registeredCount: 1}));
  const marker = `event_${id}_${uid("attendee")}`;
  await seed(`registrations/${marker}`, {id: marker, eventId: id, userId: uid("attendee"), registeredAt: time});
  await success(getDoc(reference(client("attendee"), value)));
  await denied(getDoc(reference(client("stranger"), value)));
  await denied(deleteDoc(reference(client("org-owner"), value)));
});

test("News authoring and direct-delete denial are unchanged", async () => {
  const database = client("org-owner"); const value = item("news");
  await success(setDoc(reference(database, value), {id: value.split("/")[1], title: "Synthetic News", subtitle: "Summary", body: "Complete body",
    sourceType: "organization", organizationId, authorId: uid("org-owner"), authorName: "Synthetic owner", publishedAt: time,
    createdAt: time, updatedAt: time, moderationStatus: "approved", likeCount: 0, likeState: "notLiked", viewCount: 0, commentCount: 0}));
  await success(updateDoc(reference(database, value), {title: "Updated News", updatedAt: serverTimestamp()}));
  await denied(deleteDoc(reference(database, value)));
});

test("existing BC01 iOS and Android token gates remain intact", async () => {
  const value = track(`users/${uid("attendee")}/notificationPushTokens/${prefix}-device`);
  const token = (platform) => ({id: value.split("/")[3], token: "synthetic-only-token", registrationType: "token", platform, updatedAt: serverTimestamp()});
  for (const platform of ["ios", "android"]) await success(setDoc(reference(client("attendee"), value), token(platform)));
  await denied(setDoc(reference(client("attendee"), value), token("unknown")));
  await denied(setDoc(reference(client("attendee", false), value), token("android")));
  await denied(setDoc(reference(client("stranger"), value), token("android")));
});
