import {strict as assert} from "node:assert";
import {randomUUID} from "node:crypto";
import {test, type TestContext} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {File} from "@google-cloud/storage";
import {adminStorage, db} from "../firebase/admin";
import {saveOrganizationPhoto, parsePhotoSave} from "./organizationPhotoSave";
import {accessPolicyConfiguration, getOrganizationAccess, updateOrganizationInfo, organizationRevision} from "./organizationAccess";
import {createOrganizationPhotoMetadata, deleteOrganizationPhotoMetadata} from "./organizationPhotoMutations";
import {cleanupPhotoGarbage, expirePhotoOperations, photoGraceMs, photoRetirement, claimPhotoGarbage, queuePhotoGarbage, scanLegacyPhotoOrphans} from "./organizationPhotoGarbage";
import {firebaseStorageDownloadURL, storageObjectPathFromDownloadURL} from "../content/contentDeletionPolicy";

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_STORAGE_EMULATOR_HOST;
const request = (uid: string, data: unknown, token = {email_verified: true}) => ({data, auth: {uid, token}}) as any;
const image = Buffer.from([0xff, 0xd8, 0x00, 0xff, 0xd9]).toString("base64");

async function fixture(t: TestContext) {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const id = "photo-" + randomUUID(), uid = "user-" + id;
  const org = db.doc(`organizations/${id}`), profile = db.doc(`users/${uid}`);
  const config = db.doc(accessPolicyConfiguration), previous = await config.get();
  await profile.set({globalRole: "user", accountStatus: "active"});
  await org.set({id, ownerId: uid, name: "Fixture", city: "Wien", description: "Fixture", moderationStatus: "approved", photoCount: 0, updatedAt: Timestamp.now()});
  await config.set({mode: "enforced", commandsEnabled: true, commandModes: {updateOrganizationInfo: "enforced", saveOrganizationPhoto: "enforced"}});
  t.after(async () => {
    await db.recursiveDelete(org); await profile.delete();
    for (const name of ["organizationPhotoOperations", "organizationPhotoGarbage", "organizationPhotoRetirements", "organizationMutationReceipts"]) {
      const rows = await db.collection(name).where("organizationId", "==", id).get();
      for (const row of rows.docs) await row.ref.delete();
    }
    await adminStorage.bucket().deleteFiles({prefix: `organizations/${id}/`});
    if (previous.exists) await config.set(previous.data()!); else await config.delete();
  });
  const input = {principalId: uid, organizationId: id, photoId: randomUUID(), operationId: randomUUID(), expectedImageURL: null as string | null, imageBase64: image, caption: "Fixture", clientVersion: "1.0.3"};
  return {id, uid, org, profile, config, input, photo: org.collection("photos").doc(input.photoId), run: (data = input) => saveOrganizationPhoto.run(request(uid, data))};
}

test("photo command rejects malformed, oversized and non-JPEG requests", () => {
  const base = {organizationId: "org", photoId: "photo", operationId: "op", expectedImageURL: null, imageBase64: image};
  assert.equal(parsePhotoSave(base).bytes.length, 5);
  for (const changed of [{imageBase64: "YQ=="}, {imageBase64: "A".repeat(4_000_001)}, {photoId: "a/b"}, {expectedImageURL: 3}, {caption: "x".repeat(501)}]) {
    assert.throws(() => parsePhotoSave({...base, ...changed}));
  }
});

test("lost photo response replays once and replacement atomically preserves count", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await f.run();
  const firstURL = (await f.photo.get()).get("imageURL");
  assert.equal((await f.run()).didChange, false);
  assert.equal((await f.org.get()).get("photoCount"), 1);
  const replacement = {...f.input, operationId: randomUUID(), expectedImageURL: firstURL, caption: "Replaced"};
  await f.run(replacement);
  const newURL = (await f.photo.get()).get("imageURL");
  assert.notEqual(newURL, firstURL);
  assert.equal((await f.org.get()).get("photoCount"), 1);
  assert.equal((await f.run(replacement)).didChange, false);
  const [files] = await adminStorage.bucket().getFiles({prefix: `organizations/${f.id}/photoVersions/`});
  assert.equal(files.length, 2);
  await assert.rejects(f.run({...replacement, operationId: randomUUID()}), (e: any) => e.details?.reasonCode === "object_changed");
  await cleanupPhotoGarbage(Timestamp.fromMillis(Date.now() + 2 * photoGraceMs));
  assert.equal((await adminStorage.bucket().file(storageObjectPathFromDownloadURL(firstURL)!).exists())[0], false);
  assert.equal((await adminStorage.bucket().file(storageObjectPathFromDownloadURL(newURL)!).exists())[0], true);
});

test("role revoked after object upload prevents commit; delayed cleanup retains no broken metadata", {skip: !enabled}, async t => {
  const f = await fixture(t);
  const original = File.prototype.save;
  t.mock.method(File.prototype, "save", async function(this: File, ...args: any[]) {
    await (original as any).apply(this, args);
    await f.org.update({ownerId: "someone-else"});
  });
  await assert.rejects(f.run(), (e: any) => e.details?.reasonCode === "role_missing" && typeof e.details.correlationId === "string");
  assert.equal((await f.photo.get()).exists, false);
  assert.equal((await f.org.get()).get("photoCount"), 0);
  const later = Timestamp.fromMillis(Date.now() + 2 * photoGraceMs);
  await expirePhotoOperations(later);
  await cleanupPhotoGarbage(Timestamp.fromMillis(later.toMillis() + 2 * photoGraceMs));
  const [files] = await adminStorage.bucket().getFiles({prefix: `organizations/${f.id}/photoVersions/`});
  assert.equal(files.length, 0);
});

test("account switch, reused operation and replay after deletion cannot create another photo", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await assert.rejects(f.run({...f.input, principalId: "other"}), (e: any) => e.details?.reasonCode === "account_changed");
  await f.run();
  await assert.rejects(f.run({...f.input, caption: "different"}), (e: any) => e.code === "already-exists");
  await deleteOrganizationPhotoMetadata.run(request(f.uid, f.input));
  assert.equal((await f.run()).didChange, false);
  assert.equal((await f.photo.get()).exists, false);
  await cleanupPhotoGarbage(Timestamp.fromMillis(Date.now() + 2 * photoGraceMs));
  assert.equal((await f.org.get()).get("photoCount"), 0);
});

test("expired reservation rejects late retries and preserves the existing Storage MFA condition", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await f.profile.update({globalRole: "owner", requiresMultiFactorAuth: true});
  await assert.rejects(f.run(), (e: any) => e.details?.reasonCode === "session_refresh_required");
  await f.profile.update({globalRole: "user", requiresMultiFactorAuth: false});
  const mocked = t.mock.method(File.prototype, "save", async () => { throw new Error("Injected upload failure"); });
  await assert.rejects(f.run());
  mocked.mock.restore();
  await expirePhotoOperations(Timestamp.fromMillis(Date.now() + 2 * photoGraceMs));
  await assert.rejects(f.run(), (e: any) => e.details?.reasonCode === "operation_expired");
  assert.equal((await f.photo.get()).exists, false);
});

test("rollout configuration never gives an unrelated account photo permissions", {skip: !enabled}, async t => {
  const f = await fixture(t);
  const outsider = db.doc(`users/outsider-${f.id}`);
  await outsider.set({globalRole: "admin", accountStatus: "active"});
  t.after(() => outsider.delete());
  await assert.rejects(saveOrganizationPhoto.run(request(outsider.id, {...f.input, principalId: outsider.id})),
    (e: any) => e.details?.reasonCode === "role_missing");
  assert.equal((await f.photo.get()).exists, false);
});

test("legacy orphan scan retires abandoned uploads but keeps published files and current retries", {skip: !enabled}, async t => {
  const f = await fixture(t);
  const path = `organizations/${f.id}/photos/${f.input.photoId}.jpg`;
  await adminStorage.bucket().file(path).save(Buffer.from(image, "base64"), {metadata: {contentType: "image/jpeg"}});
  const url = firebaseStorageDownloadURL(adminStorage.bucket().name, path, "fixture-token");
  await f.org.update({logoURL: url});
  assert.equal(await claimPhotoGarbage(f.id, f.input.photoId, path), false);
  await f.org.update({logoURL: null});
  const payload = {organizationId: f.id, photoId: f.input.photoId, imageURL: url};
  await createOrganizationPhotoMetadata.run(request(f.uid, payload));
  assert.equal(await claimPhotoGarbage(f.id, f.input.photoId, path), false);
  await f.photo.delete();
  await scanLegacyPhotoOrphans(Timestamp.fromMillis(Date.now() + 8 * photoGraceMs));
  assert.equal((await photoRetirement(path).get()).exists, true);
  await assert.rejects(createOrganizationPhotoMetadata.run(request(f.uid, payload)), (e: any) => e.details?.reasonCode === "operation_expired");
  await cleanupPhotoGarbage(Timestamp.fromMillis(Date.now() + 10 * photoGraceMs));
  assert.equal((await adminStorage.bucket().file(path).exists())[0], false);
});

test("a cleanup candidate is preserved if it becomes the current photo again", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await f.run();
  const current = (await f.photo.get()).get("imageURL"), path = storageObjectPathFromDownloadURL(current)!;
  await db.runTransaction(async tx => { queuePhotoGarbage(tx, f.id, f.input.photoId, path); });
  await cleanupPhotoGarbage(Timestamp.fromMillis(Date.now() + 2 * photoGraceMs));
  assert.equal((await adminStorage.bucket().file(path).exists())[0], true);
  assert.equal((await photoRetirement(path).get()).exists, false);
});

test("simultaneous replacements choose one version and cleanup removes only the losing upload", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await f.run();
  const initial = (await f.photo.get()).get("imageURL");
  const results = await Promise.allSettled(["First", "Second"].map(caption => f.run({...f.input, operationId: randomUUID(), expectedImageURL: initial, caption})));
  assert.equal(results.filter(r => r.status === "fulfilled").length, 1);
  assert.equal(results.filter(r => r.status === "rejected").length, 1);
  assert.equal((await f.org.get()).get("photoCount"), 1);
  const currentPath = storageObjectPathFromDownloadURL((await f.photo.get()).get("imageURL"))!;
  const later = Timestamp.fromMillis(Date.now() + 2 * photoGraceMs);
  await expirePhotoOperations(later);
  await cleanupPhotoGarbage(Timestamp.fromMillis(later.toMillis() + 2 * photoGraceMs));
  const [remaining] = await adminStorage.bucket().getFiles({prefix: `organizations/${f.id}/photoVersions/`});
  assert.deepEqual(remaining.map(f => f.name), [currentPath]);
});

test("failed generation-guarded cleanup remains retryable and does not damage the active image", {skip: !enabled}, async t => {
  const f = await fixture(t);
  await f.run();
  const initial = (await f.photo.get()).get("imageURL");
  await f.run({...f.input, operationId: randomUUID(), expectedImageURL: initial});
  const current = (await f.photo.get()).get("imageURL");
  const mocked = t.mock.method(File.prototype, "delete", async () => { throw Object.assign(new Error("Generation changed"), {code: 412}); });
  const later = Timestamp.fromMillis(Date.now() + 2 * photoGraceMs);
  assert.equal(await cleanupPhotoGarbage(later), 0);
  mocked.mock.restore();
  assert.equal((await adminStorage.bucket().file(storageObjectPathFromDownloadURL(current)!).exists())[0], true);
  await cleanupPhotoGarbage(Timestamp.fromMillis(later.toMillis() + 2 * photoGraceMs));
  assert.equal((await adminStorage.bucket().file(storageObjectPathFromDownloadURL(initial)!).exists())[0], false);
});

test("staged action enablement and rollback are enforced on the server, without granting outsiders", {skip: !enabled}, async t => {
  const f = await fixture(t);
  const profile = await f.org.get();
  const update = {principalId: f.uid, organizationId: f.id, operationId: randomUUID(), expectedRevision: organizationRevision(profile.data()!), targetStatus: "approved", fields: {name: "Changed"}};
  await f.config.set({mode: "enforced", commandsEnabled: true, enabledUserIds: [f.uid], actionModes: {editInfo: "enforced"}, commandModes: {updateOrganizationInfo: "enforced"}});
  const caps = await getOrganizationAccess.run(request(f.uid, {organizationIds: [f.id], legacyDecisions: {[f.id]: {editInfo: false}}}));
  assert.equal(caps.actionModes.editInfo, "enforced");
  assert.equal(caps.commands.saveOrganizationPhoto, false);
  await updateOrganizationInfo.run(request(f.uid, update));
  await f.config.update({mode: "shadow"});
  assert.equal((await getOrganizationAccess.run(request(f.uid, {organizationIds: [f.id]}))).actionModes.editInfo, "shadow");
  await assert.rejects(updateOrganizationInfo.run(request(f.uid, {...update, operationId: randomUUID()})), (e: any) => e.details?.reasonCode === "route_disabled");
  assert.equal((await f.org.get()).get("name"), "Changed");
});
