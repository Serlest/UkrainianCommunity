import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  normalizeUserSearchQuery,
  userDocumentMatchesSearch,
} from "./userManagementQueries";

test("normalizes management search input", () => {
  assert.equal(normalizeUserSearchQuery("  ІВАН  "), "іван");
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
  assert.equal(userDocumentMatchesSearch("uid-123", user, "salzburg"), false);
});

test("rejects too-short search input", () => {
  assert.throws(() => normalizeUserSearchQuery("a"));
});
