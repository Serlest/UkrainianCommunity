import {strict as assert} from "node:assert";
import {before, after, test} from "node:test";
import type {CallableRequest} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {manage, feed, acknowledge, register} from "./service";
import {createHash} from "node:crypto";
import {parseDraft} from "./contract";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
if (enabled && (!/^(127\.0\.0\.1|localhost|\[::1\]):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST!) ||
    !process.env.GCLOUD_PROJECT?.startsWith("demo-"))) throw new Error("Refusing non-isolated notification mutation test");
const owner = "n13-owner", member = "n13-member";
const ids = ["n13-save-retry", "n13-save-conflict", "n13-cancel", "n13-get"];
const req = (uid: string, data: unknown) => ({data, auth: {uid, token: {email_verified: true, firebase: {sign_in_second_factor: "totp"}}}}) as CallableRequest;
function draft(id: string) {
  const now = Date.now();
  return parseDraft({id, title: {uk: "Перевірка", de: "Prüfung"}, body: {uk: "Перевірка доставки", de: "Zustellung prüfen"}, groups: ["registered"], userIds: [], regions: [], targetPlatforms: ["ios"], mode: "once", feedback: false, push: false, startsAt: now - 1000, expiresAt: now + 3600000}, owner, now);
}
before(async () => {
  if (!enabled) return;
  await db.doc(`users/${owner}`).set({globalRole: "owner", accountStatus: "active", requiresMultiFactorAuth: true});
  await db.doc(`users/${member}`).set({globalRole: "user", accountStatus: "active"});
  await seedCurrentLegalForIntegration(owner, member);
  await db.doc("appConfig/announcements").set({enabled: true, iosEnabled: true, pushEnabled: false});
});
after(async () => {
  if (!enabled) return;
  for (const id of ids) await db.recursiveDelete(db.doc(`announcements/${id}`));
  for (const id of [owner, member]) await db.recursiveDelete(db.doc(`users/${id}`));
});
test("lost save response replays the same reviewed command without advancing revision", {skip: !enabled}, async () => {
  const value = draft(ids[0]), command = {operation: "save", draft: value, revision: 0, operationId: "n13-save-one", principalId: owner};
  const first = await manage(req(owner, command)), replay = await manage(req(owner, command));
  assert.ok("item" in first && first.item && "item" in replay && replay.item);
  assert.equal(first.item.revision, 1); assert.equal(replay.item.revision, 1); assert.deepEqual(replay.item.title, value.title);
});
test("same save identity never overwrites a different reviewed payload", {skip: !enabled}, async () => {
  const value = draft(ids[1]), command = {operation: "save", draft: value, revision: 0, operationId: "n13-save-conflict", principalId: owner};
  await manage(req(owner, command));
  await assert.rejects(manage(req(owner, {...command, draft: {...value, title: {uk: "Інший текст", de: "Anderer Text"}}})), {code: "aborted"});
  assert.deepEqual((await db.doc(`announcements/${value.id}`).get()).get("title"), value.title);
});
test("targeted authoritative owner read rejects foreign role and changed principal", {skip: !enabled}, async () => {
  const value = draft(ids[3]); await manage(req(owner, {operation: "save", draft: value, revision: 0}));
  const result = await manage(req(owner, {operation: "get", id: value.id, principalId: owner}));
  assert.ok("item" in result && result.item); assert.equal(result.item.id, value.id);
  await assert.rejects(manage(req(member, {operation: "get", id: value.id})), {code: "permission-denied"});
  await assert.rejects(manage(req(owner, {operation: "get", id: value.id, principalId: member})), {code: "permission-denied"});
  await assert.rejects(manage(req(owner, {operation: "get", id: "n13-absent"})), {code: "not-found"});
});
test("cancellation uses the reviewed revision and replay is harmless", {skip: !enabled}, async () => {
  const value = draft(ids[2]); await manage(req(owner, {operation: "save", draft: value, revision: 0}));
  await manage(req(owner, {operation: "publish", id: value.id, revision: 1}));
  await assert.rejects(manage(req(owner, {operation: "cancel", id: value.id, revision: 9})), {code: "aborted"});
  assert.equal((await db.doc(`announcements/${value.id}`).get()).get("status"), "published");
  await manage(req(owner, {operation: "cancel", id: value.id, revision: 1}));
  await manage(req(owner, {operation: "cancel", id: value.id, revision: 1}));
  assert.equal((await db.doc(`announcements/${value.id}`).get()).get("status"), "cancelled");
});
test("recipient reads receipts and installation mutations remain bound to their captured principal", {skip: !enabled}, async () => {
  const value = draft("n13-principal"), secret = "n13-local-installation-".repeat(3);
  const device = db.doc(`announcementDevices/${createHash("sha256").update(secret).digest("hex")}`);
  try {
    await manage(req(owner, {operation: "save", draft: value, revision: 0}));
    await manage(req(owner, {operation: "publish", id: value.id, revision: 1}));
    await device.set({uid: member, verified: true});
    const data = {platform: "ios", capability: 1, principalId: owner};
    await assert.rejects(feed(req(member, data)), {code: "permission-denied"});
    await assert.rejects(acknowledge(req(member, {...data, id: value.id, event: "presented"})), {code: "permission-denied"});
    await assert.rejects(register(req(member, {...data, operation: "disable", secret})), {code: "permission-denied"});
    assert.equal((await device.get()).exists, true);
    assert.equal((await db.doc(`users/${member}/announcementReceipts/${value.id}`).get()).exists, false);
    await acknowledge(req(member, {...data, principalId: member, id: value.id, event: "presented"}));
    assert.ok((await db.doc(`users/${member}/announcementReceipts/${value.id}`).get()).get("presentedAt"));
  } finally { await db.recursiveDelete(db.doc(`announcements/${value.id}`)); await device.delete(); }
});
