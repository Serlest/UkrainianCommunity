import {strict as assert} from "node:assert";
import {test, before, after} from "node:test";
import {db} from "../firebase/admin";
import {parseOrganizationBlockRequest, organizationBlockPath, changeOrganizationBlock,
  readOrganizationBlocks, getBlockedOrganizations, setOrganizationBlocked} from "./organizationBlocks";

const live = !!process.env.FIRESTORE_EMULATOR_HOST;
const actor = "organization-block-test-viewer", other = "organization-block-test-other";
const first = "organization-block-test-first", second = "organization-block-test-second";

test("organization block inputs cannot forge an actor or a user block target", () => {
  assert.deepEqual(parseOrganizationBlockRequest({organizationId: " org-a ", isBlocked: true}),
    {organizationId: "org-a", isBlocked: true});
  for (const data of [null, [], {organizationId: "org/a", isBlocked: true},
    {organizationId: "org-a", isBlocked: "true"}, {organizationId: "org-a", isBlocked: true, actorId: "forged"},
    {targetUserId: "owner", isBlocked: true}]) assert.throws(() => parseOrganizationBlockRequest(data));
  assert.equal(organizationBlockPath(actor, first), `users/${actor}/blockedOrganizations/${first}`);
});

test("both callables reject unauthenticated requests", async () => {
  await assert.rejects(getBlockedOrganizations.run({data: {}} as never), {code: "unauthenticated"});
  await assert.rejects(setOrganizationBlocked.run({data: {organizationId: first, isBlocked: true}} as never),
    {code: "unauthenticated"});
});

before(async () => {
  if (!live) return;
  if (!process.env.GCLOUD_PROJECT?.startsWith("demo-")) throw new Error("Tests require a demo emulator project.");
  await cleanup();
  await db.doc(`users/${actor}`).set({globalRole: "user", accountStatus: "active", blockState: "active"});
  for (const id of [first, second]) await db.doc(`organizations/${id}`).set({
    name: id, ownerId: other, adminIds: [actor], moderatorIds: [], moderationStatus: "approved",
  });
});
after(async () => { if (live) await cleanup(); });
async function cleanup() {
  for (const path of [`users/${actor}`, `users/${other}`, `organizations/${first}`, `organizations/${second}`]) {
    await db.recursiveDelete(db.doc(path));
  }
}

test("personal organization block is idempotent and never mutates roles, owner or sibling organization", {skip: !live}, async () => {
  const paths = [`users/${actor}`, `organizations/${first}`, `organizations/${second}`];
  const before = await Promise.all(paths.map(async (path) => (await db.doc(path).get()).data()));
  const input = {organizationId: first, isBlocked: true};
  await Promise.all([changeOrganizationBlock(actor, input), changeOrganizationBlock(actor, input)]);
  const result = await readOrganizationBlocks(actor);
  assert.equal(result.blocks.length, 1);
  assert.equal(result.blocks[0].organizationId, first);
  assert.match(result.blocks[0].blockedAt, /\.\d{3}Z$/);
  assert.equal((await readOrganizationBlocks(other)).blocks.length, 0);
  assert.equal((await db.collection(`users/${actor}/blockedUsers`).get()).size, 0);
  assert.deepEqual(await Promise.all(paths.map(async (path) => (await db.doc(path).get()).data())), before);
});

test("unblock succeeds even after the organization was deleted", {skip: !live}, async () => {
  await changeOrganizationBlock(actor, {organizationId: second, isBlocked: true});
  await db.doc(`organizations/${second}`).delete();
  const result = await changeOrganizationBlock(actor, {organizationId: second, isBlocked: false});
  assert.equal(result.block, null);
  assert.equal((await db.doc(organizationBlockPath(actor, second)).get()).exists, false);
});

test("authenticated list is scoped to the caller; account restrictions still apply", {skip: !live}, async () => {
  const request = {auth: {uid: actor, token: {email_verified: true}}, data: {}};
  const response = await getBlockedOrganizations.run(request as never);
  assert.equal(response.blocks[0].organizationId, first);
  await assert.rejects(getBlockedOrganizations.run({...request, data: {uid: other}} as never), {code: "invalid-argument"});
  await assert.rejects(setOrganizationBlocked.run({...request,
    auth: {uid: actor, token: {email_verified: false}}, data: {organizationId: first, isBlocked: false}} as never),
  {code: "permission-denied"});
  await db.doc(`users/${actor}`).update({accountStatus: "blocked"});
  await assert.rejects(getBlockedOrganizations.run(request as never), {code: "permission-denied"});
});
