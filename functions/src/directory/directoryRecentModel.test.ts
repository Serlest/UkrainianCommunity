import {strict as assert} from "node:assert";
import {test} from "node:test";
import {directoryMaterials, planDirectoryAdditions} from "./directoryRecentModel";

const text = (s: string) => ({ukrainian: s, german: s});
const section = (id: string, hidden = false) => ({id, title: text(id), isHidden: hidden});
function category(id = "new-category") {
  return {id, title: text(id), isHidden: false, groups: [section("general")],
    topics: [{...section("topic"), groupID: "general", sections: [section("one")], regionalSections: {} as Record<string, ReturnType<typeof section>[]>}]};
}

test("new topic produces one event and initial sections never become duplicate additions", () => {
  const value = category();
  value.topics[0].regionalSections.tirol = [section("regional")];
  const plan = planDirectoryAdditions(value.id, undefined, JSON.stringify(value), undefined);
  assert.deepEqual(plan.additions.map((m) => m.kind), ["topic"]);
  assert.equal(plan.knownIDs.length, 3);
  const edit = structuredClone(value); edit.topics[0].title = text("Changed");
  assert.equal(planDirectoryAdditions(value.id, JSON.stringify(value), JSON.stringify(edit), plan.knownIDs).additions.length, 0);
});

test("initial deployment suppresses existing snapshots; new sections retain destination and region", () => {
  const before = category();
  const after = structuredClone(before);
  after.topics[0].sections.push(section("two"));
  after.topics[0].regionalSections.tirol = [section("two")];
  const plan = planDirectoryAdditions(before.id, JSON.stringify(before), JSON.stringify(after), undefined);
  assert.deepEqual(plan.additions.map((m) => [m.kind, m.sectionID, m.federalState]),
    [["section", "two", null], ["section", "two", "tirol"]]);
  assert.notEqual(plan.additions[0].id, plan.additions[1].id);
});

test("hidden new content appears once on first publication, never again after remove/reinsert", () => {
  const before = category();
  let known = planDirectoryAdditions(before.id, JSON.stringify(before), JSON.stringify(before), undefined).knownIDs;
  const hidden = structuredClone(before); hidden.topics[0].sections.push(section("later", true));
  const a = planDirectoryAdditions(before.id, JSON.stringify(before), JSON.stringify(hidden), known);
  assert.equal(a.additions.length, 0);
  hidden.topics[0].sections[1].isHidden = false;
  const b = planDirectoryAdditions(before.id, JSON.stringify(before), JSON.stringify(hidden), a.knownIDs);
  assert.equal(b.additions.length, 1); known = b.knownIDs;
  assert.equal(planDirectoryAdditions(before.id, JSON.stringify(before), JSON.stringify(hidden), known).additions.length, 0);
  hidden.isHidden = true;
  assert.equal(directoryMaterials(JSON.stringify(hidden)).some((m) => m.visible), false);
});

test("bundled IDs cannot become recent merely by first server publication", () => {
  const existing = category("first-steps");
  // Actual bundled topic ID, independent of the number of bundled topics/categories.
  const {directoryRecentBaseline} = require("./directoryRecentBaseline") as typeof import("./directoryRecentBaseline");
  const base = directoryRecentBaseline[existing.id];
  assert.ok(base.length > 0);
  const plan = planDirectoryAdditions(existing.id, undefined, JSON.stringify(existing), undefined);
  assert.ok(base.every((id) => plan.knownIDs.includes(id)));
});
