import assert from "node:assert/strict";
import test from "node:test";

import {buildContentDraftNotificationDocument} from "./contentPlanningNotificationDocument.mjs";

test("content planning bridge creates a canonical centrally delivered inbox record", () => {
  const document = buildContentDraftNotificationDocument({
    ownerUserId: "owner",
    draftId: "draft-1",
    kind: "event",
    state: "readyForReview",
    title: "Подія",
    now: "2026-08-29T10:00:00.000Z",
  });

  assert.equal(document.id, "contentDraftReady_draft-1");
  assert.equal(document.userId, "owner");
  assert.equal(document.recipientUserId, "owner");
  assert.equal(document.isRead, false);
  assert.equal(document.archivedAt, null);
  assert.equal(document.deletedAt, null);
  assert.equal(document.readAt, null);
  assert.equal(document.requiresPopup, false);
  assert.equal(document.metadata.pushDelivery, "central");
  assert.deepEqual(document.payload, document.metadata);
});
