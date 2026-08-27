import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";
import {type UserPermissionSnapshot} from "../permissions/userPermissions";

import {
  canManageOrganizationContent,
  firebaseDownloadURL,
  parseContentCoverUploadRequest,
} from "./contentCoverUpload";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const activeUser: UserPermissionSnapshot = {
  uid: "user",
  globalRole: "user",
  accountStatus: "active",
  blockState: "active",
};

test("content cover request accepts canonical news and event JPEG payloads", () => {
  for (const kind of ["news", "event"]) {
    const parsed = parseContentCoverUploadRequest({
      kind,
      contentId: `${kind}-1`,
      imageBase64: jpeg.toString("base64"),
    });
    assert.equal(parsed.kind, kind);
    assert.equal(parsed.image.compare(jpeg), 0);
  }
});

test("content cover request rejects malformed, oversized, and unsupported payloads", () => {
  const invalidRequests = [
    null,
    {kind: "article", contentId: "news-1", imageBase64: jpeg.toString("base64")},
    {kind: "news", contentId: "bad/id", imageBase64: jpeg.toString("base64")},
    {kind: "news", contentId: "news-1", imageBase64: "not base64"},
    {kind: "news", contentId: "news-1", imageBase64: Buffer.from("png").toString("base64")},
    {kind: "news", contentId: "news-1", imageBase64: jpeg.toString("base64"), extra: true},
  ];

  for (const request of invalidRequests) {
    assert.throws(
      () => parseContentCoverUploadRequest(request),
      (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
    );
  }
});

test("organization cover authorization supports owner, admin, moderator, and app owner only", () => {
  const organization = {
    ownerId: "org-owner",
    adminIds: ["org-admin"],
    moderatorIds: ["org-moderator"],
  };
  assert.equal(canManageOrganizationContent(activeUser, organization, "org-owner"), true);
  assert.equal(canManageOrganizationContent(activeUser, organization, "org-admin"), true);
  assert.equal(canManageOrganizationContent(activeUser, organization, "org-moderator"), true);
  assert.equal(canManageOrganizationContent(activeUser, organization, "outsider"), false);
  assert.equal(canManageOrganizationContent(
    {...activeUser, globalRole: "owner"},
    organization,
    "app-owner"
  ), true);
});

test("content cover URL preserves the canonical object path", () => {
  assert.equal(
    firebaseDownloadURL("bucket.example", "news/news-1/cover.jpg", "token value"),
    "https://firebasestorage.googleapis.com/v0/b/bucket.example/o/news%2Fnews-1%2Fcover.jpg?alt=media&token=token%20value"
  );
});
