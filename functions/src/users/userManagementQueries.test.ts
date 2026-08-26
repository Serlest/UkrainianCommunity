import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  normalizeUserSearchQuery,
  userDocumentMatchesSearch,
} from "./userManagementQueries";

test("normalizes management search input", () => {
  assert.equal(normalizeUserSearchQuery("  ІВАН  "), "іван");
  assert.equal(normalizeUserSearchQuery("  Müller-Wien  "), "muller wien");
});

test("matches user fields and document id using substring search", () => {
  const user = {
    fullName: "Іван Петренко",
    displayName: "Ivan",
    email: "ivan@example.com",
    telegramUsername: "community_ivan",
    city: "Wien",
  };

  assert.equal(userDocumentMatchesSearch("uid-123", user, "петр"), true);
  assert.equal(userDocumentMatchesSearch("uid-123", user, "example"), true);
  assert.equal(userDocumentMatchesSearch("uid-123", user, "123"), true);
  assert.equal(userDocumentMatchesSearch("uid-123", user, "ivan wien"), true);
  assert.equal(userDocumentMatchesSearch("uid-123", user, "salzburg"), false);
});

test("rejects too-short search input", () => {
  assert.throws(() => normalizeUserSearchQuery("a"));
});

import {applyPresenceUpdate, parsePresenceUpdate, presenceResponse, presenceState, presenceLeaseMs} from "./userPresence";

const sessionA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const sessionB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const now = 1_800_000_000_000;
function update(sessionId = sessionA, sequence = 1, active = true) {
  return parsePresenceUpdate({userId: "member", sessionId, sequence, active}, "member");
}

test("presence expires without an offline callback and never invents a historical visit", () => {
  const empty = presenceState(undefined);
  assert.equal(presenceResponse("member", empty, now).lastSeenAt, null);
  assert.equal(presenceResponse("member", empty, now).onlineUntil, null);
  const active = applyPresenceUpdate(empty, update(), now);
  assert.equal(presenceResponse("member", active, now).onlineUntil, now + presenceLeaseMs);
  assert.equal(presenceResponse("member", active, now + presenceLeaseMs).onlineUntil, null);
  assert.equal(presenceResponse("member", active, now + presenceLeaseMs).lastSeenAt, now);
});

test("presence ignores reordered/duplicate heartbeats after background and supports another device", () => {
  let state = applyPresenceUpdate(presenceState(undefined), update(), now);
  state = applyPresenceUpdate(state, update(sessionA, 3, false), now + 1_000);
  assert.equal(applyPresenceUpdate(state, update(sessionA, 2, true), now + 2_000), state);
  assert.equal(applyPresenceUpdate(state, update(sessionA, 3, false), now + 3_000), state);
  assert.equal(presenceResponse("member", state, now + 3_000).onlineUntil, null);
  state = applyPresenceUpdate(state, update(sessionB), now + 4_000);
  state = applyPresenceUpdate(state, update(sessionA, 4, false), now + 5_000);
  assert.equal(presenceResponse("member", state, now + 5_000).onlineUntil, now + 4_000 + presenceLeaseMs);
  assert.equal(presenceResponse("member", state, now + 5_000, false).onlineUntil, null);
});

test("presence rejects spoofed accounts and malformed session updates", () => {
  assert.throws(() => parsePresenceUpdate({...update(), userId: "other"}, "member"));
  for (const changes of [{sessionId: "../other"}, {sequence: 0}, {sequence: 1.5}, {active: "yes"}]) {
    assert.throws(() => parsePresenceUpdate({...update(), ...changes}, "member"));
  }
});

test("presence prunes old session markers while retaining last activity", () => {
  const old = applyPresenceUpdate(presenceState(undefined), update(), now);
  const fresh = applyPresenceUpdate(old, update(sessionB), now + 11 * 60_000);
  assert.equal(Object.keys(fresh.sessions).length, 1);
  assert.equal(fresh.sessions[sessionA], undefined);
  assert.equal(fresh.lastSeenAt, now + 11 * 60_000);
});
