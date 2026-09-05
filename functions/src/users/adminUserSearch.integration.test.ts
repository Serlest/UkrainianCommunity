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
