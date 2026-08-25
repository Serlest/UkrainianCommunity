import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  accountDeletionReferencePolicies,
  deletedUserID,
  personalReferenceValues,
  redactPersonalReferences,
} from "./accountDeletionPolicy";

test("account deletion policy covers every cross-document user reference", () => {
  assert.deepEqual(
    accountDeletionReferencePolicies.map((policy) => policy.name),
    [
      "event authors",
      "legacy news authors",
      "comments",
      "organization administrators",
      "organization moderators",
      "organization submitters",
      "organization reviewers",
      "organization photo uploaders",
      "DSA case reporters",
      "DSA case affected authors",
      "feedback messages written as a manager",
      "notifications in other users' inboxes",
      "legal acceptance records",
      "audit targets",
      "audit actors",
      "system log actors",
      "system log reviewers",
      "system log account targets",
    ]
  );

  const notifications = accountDeletionReferencePolicies.find(
    (policy) => policy.collection === "notificationInbox"
  );
  assert.equal(notifications?.action, "delete");

  const roles = accountDeletionReferencePolicies.filter(
    (policy) => policy.field === "adminIds" || policy.field === "moderatorIds"
  );
  assert.ok(roles.every((policy) => policy.action === "removeArrayValue"));
});

test("personal references are normalized and deduplicated", () => {
  assert.deepEqual(personalReferenceValues("uid-123", {
    email: " owner@example.com ",
    displayName: "Philipp",
    fullName: "Philipp",
    telegramUsername: "ph_user",
    avatarURL: "https://example.com/avatar.jpg",
  }), [
    "uid-123",
    "owner@example.com",
    "Philipp",
    "ph_user",
    "https://example.com/avatar.jpg",
  ]);
});

test("redaction removes identifiers from nested retained log data", () => {
  const timestampLikeValue = new Date("2026-08-23T12:00:00.000Z");
  const result = redactPersonalReferences({
    actor: "uid-123",
    message: "User Philipp (owner@example.com) changed a role",
    nested: ["uid-123", {avatar: "https://example.com/avatar.jpg"}],
    createdAt: timestampLikeValue,
  }, [
    "uid-123",
    "Philipp",
    "owner@example.com",
    "https://example.com/avatar.jpg",
  ]) as Record<string, unknown>;

  assert.deepEqual(result, {
    actor: deletedUserID,
    message: "User deleted (deleted) changed a role",
    nested: [deletedUserID, {avatar: deletedUserID}],
    createdAt: timestampLikeValue,
  });
  assert.equal(result.createdAt, timestampLikeValue);
});
