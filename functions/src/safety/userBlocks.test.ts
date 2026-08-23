import {strict as assert} from "node:assert";
import {test} from "node:test";

import {parseUserBlockRequest, userBlockDocumentPath} from "./userBlocks";

test("parses strict block and unblock requests", () => {
  assert.deepEqual(parseUserBlockRequest({
    targetUserId: " user-2 ",
    isBlocked: true,
  }), {
    targetUserId: "user-2",
    isBlocked: true,
  });
  assert.equal(parseUserBlockRequest({
    targetUserId: "user-2",
    isBlocked: false,
  }).isBlocked, false);
});

test("rejects malformed identifiers, non-booleans, and extra fields", () => {
  assert.throws(() => parseUserBlockRequest({targetUserId: "user/2", isBlocked: true}));
  assert.throws(() => parseUserBlockRequest({targetUserId: "user-2", isBlocked: "true"}));
  assert.throws(() => parseUserBlockRequest({
    targetUserId: "user-2",
    isBlocked: true,
    actorUserId: "forged-user",
  }));
});

test("uses a private deterministic per-user document path", () => {
  assert.equal(
    userBlockDocumentPath("user-1", "user-2"),
    "users/user-1/blockedUsers/user-2"
  );
});
