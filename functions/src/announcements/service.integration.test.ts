import {createHash} from "node:crypto";
import {strict as assert} from "node:assert";
import {before, after, test} from "node:test";
import type {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {manage, feed, acknowledge, register} from "./service";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const request = (uid: string | undefined, data: unknown, totp = true) => ({data, auth: uid ? {uid, token: {email_verified: true, firebase: {sign_in_second_factor: totp ? "totp" : undefined}}} : undefined}) as CallableRequest;
const now = Date.now();
const draft = {id: "announcement-integration", title: {uk: "Тест", de: "Test"}, body: {uk: "Текст", de: "Text"}, groups: ["registered", "guests"], userIds: [], regions: ["wien"], targetPlatforms: ["ios"], mode: "acknowledge", feedback: true, push: false, startsAt: now - 1000, expiresAt: now + 3600000};
const userIDs = ["ann-owner", "ann-admin", "ann-vienna", "ann-tirol"];
before(async () => {
  if (!enabled) return;
  await db.doc("appConfig/announcements").set({enabled:true,iosEnabled:true,pushEnabled:true});
  for (const uid of userIDs) await db.collection("users").doc(uid).set({globalRole: uid === "ann-owner" ? "owner" : uid === "ann-admin" ? "admin" : "user", selectedFederalState: uid === "ann-tirol" ? "tirol" : "wien", accountStatus: "active", requiresMultiFactorAuth: uid === "ann-owner"});
  await db.recursiveDelete(db.collection("announcements").doc(draft.id));
});
after(async () => {
  if (!enabled) return;
  for (const uid of userIDs) await db.recursiveDelete(db.collection("users").doc(uid));
  await db.recursiveDelete(db.collection("announcements").doc(draft.id));
});
test("owner authorization, draft lifecycle, audience privacy and receipt idempotency", {skip: !enabled}, async () => {
  for (const uid of [undefined, "ann-admin", "ann-vienna"]) {
    await assert.rejects(manage(request(uid, {operation: "save", draft})));
    await assert.rejects(manage(request(uid, {operation: "users"})));
    await assert.rejects(manage(request(uid, {operation: "translate", source: "uk", title: "a", body: "b"})));
  }
  await assert.rejects(manage(request("ann-owner", {operation: "save", draft}, false)));
  await manage(request("ann-owner", {operation: "save", draft}));
  assert.equal((await feed(request("ann-vienna", {platform: "ios", capability: 1}))).items.some((i) => i.id === draft.id), false);
  await assert.rejects(manage(request("ann-owner", {operation: "publish", id: draft.id, revision: 0})));
  await manage(request("ann-owner", {operation: "publish", id: draft.id, revision: 1}));
  await manage(request("ann-owner", {operation: "publish", id: draft.id, revision: 1}));
  await assert.rejects(manage(request("ann-owner", {operation: "save", draft, revision: 1})));
  const vienna = await feed(request("ann-vienna", {platform: "ios", capability: 1}));
  const item = vienna.items.find((i) => i.id === draft.id)!;
  assert.ok(item); assert.equal("userIds" in item, false); assert.equal("authorId" in item, false);
  assert.equal((await feed(request("ann-tirol", {platform: "ios", capability: 1}))).items.some((i) => i.id === draft.id), false);
  assert.equal((await feed(request(undefined, {platform: "ios", capability: 1}))).items.some((i) => i.id === draft.id), true);
  await assert.rejects(feed(request("ann-vienna", {platform: "android", capability: 1})));
  await assert.rejects(feed(request("ann-vienna", {platform: "ios"})));
  for (const uid of [undefined, "ann-tirol"]) await assert.rejects(acknowledge(request(uid, {id: draft.id, event: "acknowledged", platform: "ios", capability: 1})));
  for (let n = 0; n < 2; n++) await acknowledge(request("ann-vienna", {id: draft.id, event: "acknowledged", platform: "ios", capability: 1}));
  const stats = await manage(request("ann-owner", {operation: "stats", id: draft.id}));
  assert.equal("acknowledged" in stats && stats.acknowledged, 1);
  const receipt = (await feed(request("ann-vienna", {platform: "ios", capability: 1}))).items.find((i) => i.id === draft.id)!;
  assert.ok(receipt.acknowledgedAt);
  await manage(request("ann-owner", {operation: "cancel", id: draft.id}));
  assert.equal((await feed(request("ann-vienna", {platform: "ios", capability: 1}))).items.some((i) => i.id === draft.id && i.status === "published"), false);
  await assert.rejects(acknowledge(request("ann-vienna", {id: draft.id, event: "presented", platform: "ios", capability: 1})));
});
test("unknown guest installation cannot confirm a forged challenge", {skip: !enabled}, async () => {
  await assert.rejects(register(request(undefined, {operation: "confirm", secret: "a".repeat(64), challenge: "forged", platform: "ios", capability: 1})));
});

test("installation challenge is required and bound to its current account", {skip: !enabled}, async () => {
  const secret = "device-proof-fixture-".repeat(4);
  const device = db.collection("announcementDevices").doc(createHash("sha256").update(secret).digest("hex"));
  let challenge = "";
  try {
    await register(request("ann-vienna", {secret, fid:"c123456789012345678901",platform:"ios",capability:1}), async (_docs,message) => {
      challenge = message.data!.announcementChallenge;
      return {targetCount:1,successCount:1,failureCount:0};
    });
    assert.equal((await device.get()).get("verified"),false);
    await assert.rejects(register(request(undefined,{operation:"confirm",secret,challenge,platform:"ios",capability:1})));
    await assert.rejects(register(request("ann-vienna",{operation:"confirm",secret,challenge:"forged",platform:"ios",capability:1})));
    await register(request("ann-vienna",{operation:"confirm",secret,challenge,platform:"ios",capability:1}));
    assert.equal((await device.get()).get("verified"),true);
    await register(request(undefined,{operation:"disable",secret,platform:"ios",capability:1}));
    assert.equal((await device.get()).exists,false);
  } finally { await device.delete(); }
});
