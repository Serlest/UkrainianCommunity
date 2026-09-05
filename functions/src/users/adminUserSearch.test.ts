import {strict as assert} from "node:assert";
import {test} from "node:test";
import {adminSearchAnchor, adminSearchOverflow, buildAdminSearchGrams, collectAdminSearch,
  normalizeAdminSearch} from "./adminUserSearch";
import {userDocumentMatchesSearch} from "./userManagementQueries";
import {accountMatchesSearch} from "../legal/legalEvidence";

async function* sequence<T>(values: T[]) { yield* values; }

test("search finds late matches beyond 1000 documents and counts beyond response limit", async () => {
  const values = Array.from({length: 1205}, (_, id) => id);
  const result = await collectAdminSearch(sequence(values), id => id >= 1100, 2);
  assert.deepEqual(result, {items: [1100, 1101], totalMatches: 105});
});

test("legal top set considers later newer accounts, retaining tie order and complete count", async () => {
  const rows = [{id: "a", time: 1}, {id: "b", time: 9}, {id: "c", time: 9}, {id: "d", time: 10}];
  const result = await collectAdminSearch(sequence(rows), () => true, 2, (a, b) => b.time - a.time);
  assert.deepEqual(result, {items: [rows[3], rows[1]], totalMatches: 4});
});

test("a failed stream rejects rather than returning an incomplete count", async () => {
  async function* broken() { yield 1; yield 2; throw new Error("stream interrupted"); }
  await assert.rejects(collectAdminSearch(broken(), () => true, 1), /stream interrupted/);
});

test("candidate index is a superset of both exact predicates for Unicode and split tokens", () => {
  const data = {displayName: "Müller ІВАН", fullName: "Petrenko", email: "a+b@example.com",
    telegramUsername: "community_ivan", city: "Wien", selectedFederalState: "Wien"};
  const grams = buildAdminSearchGrams("uid-123-𐐀𐐁", data);
  for (const input of ["ÜLL", "ІВАН", "петр", "123", "van wien", "a b", "EXAMPLE", "𐐀𐐁", "!!", "x y"]) {
    const query = normalizeAdminSearch(input);
    const anchor = adminSearchAnchor(query);
    const candidate = anchor === null || grams.includes(anchor) || grams.includes(adminSearchOverflow);
    if (userDocumentMatchesSearch("uid-123-𐐀𐐁", data, query)
      || accountMatchesSearch("uid-123-𐐀𐐁", data, query)) assert.equal(candidate, true, input);
  }
  // Management-only fields never broaden legal evidence results.
  assert.equal(userDocumentMatchesSearch("uid", data, "wien"), true);
  assert.equal(accountMatchesSearch("uid", data, "wien"), false);
});

test("punctuation-only legal search retains match-all semantics and single-letter tokens work", () => {
  assert.equal(adminSearchAnchor(normalizeAdminSearch("!!")), null);
  assert.equal(accountMatchesSearch("uid", {}, ""), true);
  assert.equal(adminSearchAnchor("a b"), "a");
  assert.ok(buildAdminSearchGrams("uid", {email: "a@b.com"}).includes("a"));
});

test("large profiles use an overflow candidate instead of losing substrings", () => {
  const text = Array.from({length: 4100}, (_, index) => String.fromCodePoint(0x4e00 + index)).join("");
  assert.deepEqual(buildAdminSearchGrams("uid", {fullName: text}), [adminSearchOverflow]);
});

test("renaming replaces grams and index ignores client supplied derived values", () => {
  const old = buildAdminSearchGrams("uid", {displayName: "alpha"});
  const fresh = buildAdminSearchGrams("uid", {displayName: "zulu", adminSearchGramsV1: old});
  assert.ok(old.includes("alp"));
  assert.ok(!fresh.includes("alp"));
  assert.ok(fresh.includes("zul"));
});
