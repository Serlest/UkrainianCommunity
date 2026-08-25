import assert from "node:assert/strict";
import {describe, test} from "node:test";

import {isSystemLogAppAdminReadable} from "./systemLogVisibilityCore.mjs";

describe("system log app-admin visibility", () => {
  test("allows safe diagnostics and moderation", () => {
    assert.equal(isSystemLogAppAdminReadable({category: "diagnostics", actorRole: "user"}), true);
    assert.equal(isSystemLogAppAdminReadable({category: "moderation", actorRole: "admin"}), true);
  });

  test("denies security, owner actors, and owner targets", () => {
    assert.equal(isSystemLogAppAdminReadable({category: "userAccount", retentionPolicy: "security"}), false);
    assert.equal(isSystemLogAppAdminReadable({category: "diagnostics", actorRole: "owner"}), false);
    assert.equal(isSystemLogAppAdminReadable({category: "organization", targetRole: "owner"}), false);
  });
});
