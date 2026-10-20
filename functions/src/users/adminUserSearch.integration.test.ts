import {strict as assert} from "node:assert";
import {after, test} from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {adminSearchDocuments, adminSearchFields, adminSearchIndexField, buildAdminSearchGrams,
  collectAdminSearch, type AdminSearchReadiness} from "./adminUserSearch";
import {userDocumentMatchesSearch} from "./userManagementQueries";

const projectId = "demo-uac-admin-search";
const enabled = process.env.GCLOUD_PROJECT === projectId
  && /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const database = new Firestore({projectId});
const ids = ["search-fixture-a", "search-fixture-b", "search-fixture-c"];
const refs = ids.map(id => database.collection("users").doc(id));
after(async () => {
  if (enabled) await Promise.all(refs.map(ref => ref.delete()));
  await database.terminate();
});
async function search(query: string, readiness: AdminSearchReadiness = "incomplete") {
  return collectAdminSearch(adminSearchDocuments(database, query, adminSearchFields, readiness),
    doc => userDocumentMatchesSearch(doc.id, doc.data(), query), 100);
}

test("incomplete gate includes absent/stale indexes and immediate rename/delete", {skip: !enabled}, async () => {
  await refs[0].set({displayName: "alpha"});
  await refs[1].set({displayName: "alpha", [adminSearchIndexField]: ["stale"]});
  assert.equal((await search("alpha")).totalMatches, 2);
  await refs[0].update({displayName: "renamed"});
  assert.deepEqual((await search("renamed")).items.map(doc => doc.id), [ids[0]]);
  await refs[0].delete();
  assert.equal((await search("renamed")).totalMatches, 0);
});

test("ready candidates match fallback when complete and atomically maintained", {skip: !enabled}, async () => {
  const profiles = [{displayName: "Müller", city: "Wien"}, {fullName: "Petrenko", city: "Wien"},
    {email: "muller@example.com"}];
  for (let index = 0; index < refs.length; index++) {
    await refs[index].set({...profiles[index], [adminSearchIndexField]: buildAdminSearchGrams(ids[index], profiles[index])});
  }
  for (const query of ["mull", "wien", "mull wien", "a b", "fixture", "zzz"]) {
    const fallback = await search(query);
    const indexed = await search(query, "ready");
    assert.equal(indexed.totalMatches, fallback.totalMatches);
    assert.deepEqual(indexed.items.map(doc => doc.id), fallback.items.map(doc => doc.id));
  }
  const renamed = {displayName: "renamed", city: "Wien"};
  await refs[0].set({...renamed, [adminSearchIndexField]: buildAdminSearchGrams(ids[0], renamed)});
  assert.equal((await search("renamed", "ready")).totalMatches, 1);
  await refs[0].delete();
  assert.equal((await search("renamed", "ready")).totalMatches, 0);
});

import {reconcileAdminSearchUser, searchSourceChanged} from "./adminUserSearchIndex";
import {adminSearchControlPath} from "./adminUserSearch";

test("event maintenance is idempotent, preserves source fields and reads the latest state", {skip: !enabled}, async () => {
  const original = {displayName: "Original", fullName: "Іван", email: "test@example.com", globalRole: "user",
    updatedAt: new Date("2026-01-01"), accountStatus: "warned", warningCount: 2};
  await refs[0].set(original);
  assert.equal(await reconcileAdminSearchUser(database, ids[0]), true);
  const first = await refs[0].get();
  assert.equal(await reconcileAdminSearchUser(database, ids[0]), false);
  assert.ok((await refs[0].get()).updateTime!.isEqual(first.updateTime!));
  await refs[0].update({displayName: "Newest", city: "München"});
  // A retried OLD event supplies only the ID. It cannot overwrite the newest profile.
  await Promise.all([reconcileAdminSearchUser(database, ids[0]), reconcileAdminSearchUser(database, ids[0])]);
  const current = (await refs[0].get()).data()!;
  assert.equal(current.displayName, "Newest");
  assert.equal(current.accountStatus, "warned");
  assert.equal(current.warningCount, 2);
  assert.equal(current.updatedAt.toDate().toISOString(), original.updatedAt.toISOString());
  assert.equal((await search("newest munchen", "ready")).totalMatches, 1);
  assert.equal((await search("original", "ready")).totalMatches, 0);
  await refs[0].delete();
  assert.equal(await reconcileAdminSearchUser(database, ids[0]), false);
  assert.equal((await refs[0].get()).exists, false);
});

test("private switch defaults to complete fallback and supports immediate rollback", {skip: !enabled}, async () => {
  const control = database.doc(adminSearchControlPath);
  await control.delete();
  await refs[0].set({displayName: "switchfixture"});
  assert.equal((await search("switchfixture", "automatic")).totalMatches, 1);
  await reconcileAdminSearchUser(database, ids[0]);
  await control.set({ready: true, version: 1});
  assert.equal((await search("switchfixture", "automatic")).totalMatches, 1);
  await control.update({ready: false});
  await refs[0].update({displayName: "rollbackfixture"});
  assert.equal((await search("rollbackfixture", "automatic")).totalMatches, 1);
  await control.delete();
});

test("indexed search matches full search across 1500 accounts with bounded response and selective reads", {skip: !enabled}, async () => {
  const writer = database.bulkWriter();
  const count = 1500;
  const loadRefs = Array.from({length: count}, (_, index) => database.collection("users").doc(`load-${String(index).padStart(4, "0")}`));
  for (let index = 0; index < count; index++) {
    const profile = {displayName: index === 1499 ? "Zebraspecial Müller" : `Member ${index}`,
      email: `member${index}@example.test`, city: index % 2 ? "Wien" : "Linz"};
    writer.set(loadRefs[index], {...profile, [adminSearchIndexField]: buildAdminSearchGrams(loadRefs[index].id, profile)});
  }
  await writer.close();
  try {
    for (const query of ["zebraspecial", "member", "member14 wien", "load 1499", "muller", "noresults"]) {
      const full = await search(query);
      const indexed = await search(query, "ready");
      assert.equal(indexed.totalMatches, full.totalMatches, query);
      assert.deepEqual(indexed.items.map(doc => doc.id), full.items.map(doc => doc.id), query);
      assert.ok(indexed.items.length <= 100);
    }
    assert.equal((await search("member", "ready")).totalMatches, 1500);
    const candidates = [];
    for await (const doc of adminSearchDocuments(database, "zebraspecial", adminSearchFields, "ready")) candidates.push(doc.id);
    assert.deepEqual(candidates, ["load-1499"]); // One candidate read, not all 1500 profiles.
  } finally {
    const cleanup = database.bulkWriter();
    for (const reference of loadRefs) cleanup.delete(reference);
    await cleanup.close();
  }
});

test("unrelated status changes do not schedule index writes", () => {
  assert.equal(searchSourceChanged({displayName: "a", accountStatus: "active"}, {displayName: "a", accountStatus: "warned"}), false);
  assert.equal(searchSourceChanged({displayName: "a"}, {displayName: "b"}), true);
  assert.equal(searchSourceChanged(undefined, {displayName: "a"}), true);
});

import {searchManagedUsers} from "./userManagementQueries";
import {listLegalEvidenceAccounts} from "../legal/legalEvidence";
import {maintainAdminUserSearchIndex} from "./adminUserSearchIndex";
import {db as callableDatabase} from "../firebase/admin";

test("legacy callable contract, authorization and actual event handler survive indexed cutover", {skip: !enabled}, async () => {
  // Same demo database as callable imports; no Auth tokens or real accounts are used.
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  const actor = database.doc("users/search-test-actor");
  const control = database.doc(adminSearchControlPath);
  const request = () => ({auth: {uid: actor.id, token: {email_verified: true}}, data: {query: "eventfixture", limit: 100}} as never);
  try {
    await database.doc("legalDocuments/terms").set({activeVersion: "1"});
    await database.doc("legalDocuments/privacy").set({activeVersion: "1"});
    await actor.set({globalRole: "owner", accountStatus: "active", blockState: "active",
      acceptedTermsVersion: "1", acceptedPrivacyVersion: "1"});
    const before = await refs[0].get();
    await refs[0].set({displayName: "Eventfixture", createdAt: new Date()});
    const after = await refs[0].get();
    const event = {params: {userId: ids[0]}, data: {before, after}} as never;
    await maintainAdminUserSearchIndex.run(event);
    await maintainAdminUserSearchIndex.run(event); // Redelivery must be harmless.
    await control.set({ready: true, version: 1});
    assert.deepEqual(await searchManagedUsers.run(request()), {userIds: [ids[0]], totalMatches: 1});
    const legal = await listLegalEvidenceAccounts.run(request());
    assert.equal(legal.totalMatches, 1);
    assert.equal(legal.nextCursor, null);
    await assert.rejects(searchManagedUsers.run({data: {query: "eventfixture"}} as never), {code: "unauthenticated"});
    await actor.update({globalRole: "user"});
    await assert.rejects(searchManagedUsers.run(request()), {code: "permission-denied"});
    await actor.update({globalRole: "admin"});
    assert.equal((await searchManagedUsers.run(request())).totalMatches, 1);
    await assert.rejects(listLegalEvidenceAccounts.run(request()), {code: "permission-denied"});
    await actor.update({accountStatus: "bannedPermanent"});
    await assert.rejects(searchManagedUsers.run(request()), {code: "permission-denied"});
    await actor.update({accountStatus: "active", acceptedTermsVersion: "old"});
    await assert.rejects(searchManagedUsers.run(request()), {code: "failed-precondition"});
    // Delayed duplicate event after deletion cannot recreate the document.
    await refs[0].delete();
    await maintainAdminUserSearchIndex.run(event);
    assert.equal((await refs[0].get()).exists, false);
  } finally {
    await actor.delete();
    await control.delete();
    await callableDatabase.terminate();
  }
});
