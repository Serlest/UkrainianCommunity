import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  buildContentPlanningRetentionWrite,
  decodeFirestoreDocument,
  verifyContentPlanningRetentionReadBack,
} from "./contentPlanningRetentionRest.mjs";

const draft = {
  name: "projects/example/databases/(default)/documents/users/owner/contentPlanningDrafts/draft",
  path: "users/owner/contentPlanningDrafts/draft",
  updateTime: "2026-09-01T10:00:00.000Z",
  data: {},
};
const result = {
  status: "update",
  retentionExpiresAtMilliseconds: Date.parse("2027-02-28T10:00:00.000Z"),
  mediaCleanupStatus: "pending",
  requestsMediaCleanup: true,
};

test("builds an update-time guarded retention write", () => {
  assert.deepEqual(buildContentPlanningRetentionWrite({draft, result}), {
    update: {
      name: draft.name,
      fields: {
        retentionExpiresAt: {timestampValue: "2027-02-28T10:00:00.000Z"},
        retentionPolicy: {stringValue: "contentPlanningReceipt6Months"},
        draftMediaCleanupStatus: {stringValue: "pending"},
      },
    },
    updateMask: {
      fieldPaths: [
        "retentionExpiresAt",
        "retentionPolicy",
        "draftMediaCleanupStatus",
      ],
    },
    currentDocument: {updateTime: draft.updateTime},
    updateTransforms: [{
      fieldPath: "draftMediaCleanupRequestedAt",
      setToServerValue: "REQUEST_TIME",
    }],
  });
});

test("does not reset an existing cleanup outcome", () => {
  const write = buildContentPlanningRetentionWrite({
    draft: {...draft, data: {draftMediaCleanupStatus: "deletedRedundantCopy"}},
    result: {...result, requestsMediaCleanup: false},
  });
  assert.deepEqual(write.updateMask.fieldPaths, ["retentionExpiresAt", "retentionPolicy"]);
  assert.equal(write.update.fields.draftMediaCleanupStatus, undefined);
  assert.equal(write.updateTransforms, undefined);
});

test("decodes REST timestamps and nested media metadata", () => {
  const decoded = decodeFirestoreDocument({
    name: draft.name,
    updateTime: draft.updateTime,
    fields: {
      updatedAt: {timestampValue: "2026-08-31T10:00:00.000Z"},
      generatedImage: {mapValue: {fields: {
        storagePath: {stringValue: "users/owner/contentPlanningDraftImages/draft/cover.jpg"},
      }}},
    },
  });
  assert.equal(decoded.data.updatedAt, "2026-08-31T10:00:00.000Z");
  assert.equal(
    decoded.data.generatedImage.storagePath,
    "users/owner/contentPlanningDraftImages/draft/cover.jpg"
  );
});

test("requires exact retention read-back fields", () => {
  const document = {
    name: draft.name,
    updateTime: "2026-09-01T10:05:00.000Z",
    fields: {
      retentionExpiresAt: {timestampValue: "2027-02-28T10:00:00.000Z"},
      retentionPolicy: {stringValue: "contentPlanningReceipt6Months"},
      draftMediaCleanupStatus: {stringValue: "pending"},
    },
  };
  assert.equal(verifyContentPlanningRetentionReadBack(document, result), true);
  assert.equal(verifyContentPlanningRetentionReadBack({
    ...document,
    fields: {...document.fields, retentionPolicy: {stringValue: "wrong"}},
  }, result), false);
});
