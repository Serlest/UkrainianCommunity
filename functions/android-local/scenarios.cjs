"use strict";

const boundary = require("./preload.cjs");
const assert = require("node:assert/strict");
const {db, adminAuth, adminStorage} = require("../lib/firebase/admin.js");
const {Timestamp} = require("firebase-admin/firestore");
const {deliverPushDurably} = require("../lib/notifications/durablePushDelivery.js");
const {sendPushToRegistrationDocuments} = require("../lib/notifications/pushRegistrations.js");
const {projectId} = require("./environment.cjs");

const userId = "android-harness-user";
const otherId = "android-harness-other";
const ownerId = "android-harness-owner";
const password = "Local-only-synthetic-984!";
let assertions = 0;

async function jsonRequest(url, body, headers = {}) {
  const response = await fetch(url, {method: "POST", headers: {"Content-Type": "application/json", ...headers},
    body: JSON.stringify(body), signal: AbortSignal.timeout(20_000)});
  return {status: response.status, body: await response.json()};
}

async function tokenFor(uid) {
  const result = await jsonRequest("http://127.0.0.1:9098/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-demo", {
    email: `${uid}@example.invalid`, password, returnSecureToken: true,
  });
  assert.equal(result.status, 200);
  assert.equal(typeof result.body.idToken, "string");
  return result.body.idToken;
}

async function callable(name, data, token) {
  assert.match(name, /^[A-Za-z][A-Za-z0-9]+$/);
  return jsonRequest(`http://127.0.0.1:5008/${projectId}/europe-west3/${name}`, {data},
    token ? {Authorization: `Bearer ${token}`} : {});
}

async function seedUser(uid, globalRole = "user") {
  try {
    await adminAuth.createUser({uid, email: `${uid}@example.invalid`, password, emailVerified: true});
  } catch (error) {
    if (error.code !== "auth/uid-already-exists" && error.code !== "auth/email-already-exists") throw error;
    await adminAuth.updateUser(uid, {emailVerified: true, password});
  }
  await db.collection("users").doc(uid).set({id: uid, displayName: "Synthetic local person",
    globalRole, accountStatus: "active", blockState: "active", requiresMultiFactorAuth: false});
}

async function run() {
  for (const [uid, role] of [[userId, "user"], [otherId, "user"], [ownerId, "owner"]]) await seedUser(uid, role);
  const token = await tokenFor(userId);
  const ownerToken = await tokenFor(ownerId);
  const block = {targetUserId: otherId, isBlocked: true};
  let result = await callable("setUserBlocked", block);
  assert.equal(result.body.error?.status, "UNAUTHENTICATED"); assertions++;
  result = await callable("setUserBlocked", block, token);
  assert.equal(result.status, 200); assert.equal(result.body.result?.isBlocked, true); assertions++;
  assert.equal((await db.doc(`users/${userId}/blockedUsers/${otherId}`).get()).exists, true); assertions++;
  result = await callable("setUserBlocked", block, token);
  assert.equal(result.status, 200); assertions++;
  result = await callable("setUserBlocked", {targetUserId: userId, isBlocked: true}, token);
  assert.equal(result.body.error?.status, "FAILED_PRECONDITION"); assertions++;
  await adminAuth.updateUser(userId, {emailVerified: false});
  result = await callable("setUserBlocked", block, await tokenFor(userId));
  assert.equal(result.body.error?.status, "PERMISSION_DENIED"); assertions++;
  await adminAuth.updateUser(userId, {emailVerified: true});

  const owner = db.collection("users").doc(ownerId);
  await owner.collection("notificationPreferences").doc("settings").set({notificationsEnabled: true});
  await owner.collection("notificationPushTokens").doc("synthetic-android").set({token: "synthetic-android-token",
    platform: "android", registrationType: "token"});
  result = await callable("sendTestPushNotification", {}, ownerToken);
  assert.equal(result.status, 200); assert.equal(result.body.result?.successCount, 1); assertions++;
  result = await callable("sendTestPushNotification", {}, token);
  assert.equal(result.body.error?.status, "PERMISSION_DENIED"); assertions++;
  await owner.update({requiresMultiFactorAuth: true});
  result = await callable("sendTestPushNotification", {}, ownerToken);
  assert.equal(result.body.error?.status, "FAILED_PRECONDITION"); assertions++;

  // Storage read/write is a real emulator RPC with synthetic bytes, never cloud.
  const file = adminStorage.bucket().file("android-local-harness/synthetic-proof.txt");
  await file.save(Buffer.from("Synthetic Android harness proof"), {contentType: "text/plain"});
  assert.equal((await file.download())[0].toString(), "Synthetic Android harness proof"); assertions++;
  await file.delete();

  // Six separate inbox records survive a provider simulation and receipt retry.
  // This proves server history/receipt semantics, NOT FCM offline display.
  const registrations = [{id: "synthetic-android", data: () => ({token: "synthetic-android-token", platform: "android"}),
    ref: {delete: async () => {throw new Error("Unexpected valid-token deletion");}}}];
  const sent = [];
  for (let index = 0; index < 6; index++) {
    const ref = db.collection("users").doc(userId).collection("notificationInbox").doc(`android-offline-notice-${index}`);
    await ref.set({createdAt: Timestamp.now(), isRead: false, title: `Synthetic ${index}`});
    const sender = async message => {
      sent.push(message);
      return {successCount: 1, failureCount: 0, responses: [{success: true}]};
    };
    const payload = {notification: {title: `Synthetic ${index}`}, data: {notificationId: ref.id}};
    await deliverPushDurably(ref, payload, registrations, sender);
    await deliverPushDurably(ref, payload, registrations, sender);
    assert.equal((await ref.get()).exists, true);
    assert.equal((await ref.collection("privateDelivery").doc("push").get()).data().status, "complete");
  }
  assert.equal(sent.length, 6); assertions++;
  assert.equal(new Set(sent.map(message => message.android.notification.tag)).size, 6); assertions++;
  assert.equal((await db.collection("users").doc(userId).collection("notificationInbox").get()).size, 6); assertions++;
  const fake = await sendPushToRegistrationDocuments(registrations, {notification: {title: "Synthetic"}});
  assert.equal(fake.successCount, 1);
  assert.equal(boundary.snapshot().fakePushTargets, 1); assertions++;
  assert.equal(boundary.snapshot().blockedAttempts, 0); assertions++;
  console.log(`PASS: ${assertions} local callable/Auth/Firestore/Storage/fake-push/receipt assertions.`);
  console.log("Synthetic emulator evidence only. No real FCM, email, App Check or background-trigger proof.");
}

run().catch(error => {
  console.error("Android local harness scenarios failed:", error.message);
  process.exitCode = 1;
}).finally(async () => {await db.terminate();});
