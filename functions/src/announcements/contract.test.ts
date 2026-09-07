import {strict as assert} from "node:assert";
import {test} from "node:test";
import {parseDraft, matchesAudience, supports, isActive, publicAnnouncement, assertPublishable} from "./contract";
const now = 1800000000000;
const draft = (change = {}) => parseDraft({id: "test", title: {uk: "Заголовок", de: "Titel"}, body: {uk: "Текст", de: "Text"}, groups: ["registered", "guests"], userIds: [], regions: ["wien"], targetPlatforms: ["ios"], mode: "once", feedback: true, push: true, startsAt: now, expiresAt: now + 10000, ...change}, "owner", now);
test("account region filters members but never guests", () => {
  assert.equal(matchesAudience(draft()), true);
  assert.equal(matchesAudience(draft(), {uid: "u", region: "wien", organizationRoles: []}), true);
  assert.equal(matchesAudience(draft(), {uid: "u", region: "tirol", organizationRoles: []}), false);
  assert.equal(matchesAudience(draft(), {uid: "u", organizationRoles: []}), false);
});
test("roles and personal recipients are unioned; region still applies", () => {
  const a = draft({groups: ["appAdmins", "organizationOwners"], userIds: ["u", "u"]});
  assert.deepEqual(a.userIds, ["u"]);
  assert.equal(matchesAudience(a, {uid: "x", region: "wien", globalRole: "admin", organizationRoles: []}), true);
  assert.equal(matchesAudience(a, {uid: "x", region: "tirol", organizationRoles: ["communityOwner"]}), false);
  assert.equal(matchesAudience(a), false);
});
test("old and Android clients are excluded independently of audience", () => {
  assert.equal(supports(draft(), "ios", 1), true);
  for (const [p, c] of [["ios", undefined], ["android", 1], ["ios", 2]]) assert.equal(supports(draft(), p, c), false);
});
test("expiration, scheduling and cancellation use exact server boundaries", () => {
  const a = {...draft(), status: "published" as const};
  assert.equal(isActive(a, now - 1), false); assert.equal(isActive(a, now), true);
  assert.equal(isActive(a, a.expiresAt), false); assert.equal(isActive({...a, status: "cancelled"}, now), false);
});
test("public projection never exposes recipient IDs or author", () => {
  const projection = publicAnnouncement(draft());
  for (const key of ["userIds", "groups", "regions", "authorId", "push"]) assert.equal(key in projection, false);
});
test("malformed and unsupported drafts fail closed", () => {
  for (const change of [{id: "../u"}, {groups: ["owner"]}, {regions: ["Vienna"]}, {mode: "critical"}, {push: "true"}, {expiresAt: NaN}, {targetPlatforms: []}, {body: {uk: "a".repeat(6001), de: "a"}}]) assert.throws(() => draft(change));
  assert.throws(() => assertPublishable(draft({targetPlatforms: ["android"]}), now));
  assert.throws(() => assertPublishable(draft({title: {uk: "", de: "Title"}}), now));
  assert.doesNotThrow(() => assertPublishable(draft(), now));
});
