import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  canManageOrganizationPhotos,
  parseCreateOrganizationPhotoRequest,
  parseDeleteOrganizationPhotoRequest,
} from "./organizationPhotoMutations";

const downloadURL = "https://firebasestorage.googleapis.com/v0/b/test.appspot.com/o/"
  + "organizations%2Forg-1%2Fphotos%2Fphoto-1.jpg?alt=media&token=token";

test("photo mutation input accepts only its canonical Storage object", () => {
  assert.deepEqual(parseCreateOrganizationPhotoRequest({
    organizationId: " org-1 ",
    photoId: "photo-1",
    imageURL: downloadURL,
    caption: " Community gathering ",
  }), {
    organizationId: "org-1",
    photoId: "photo-1",
    imageURL: downloadURL,
    caption: "Community gathering",
  });

  assert.throws(
    () => parseCreateOrganizationPhotoRequest({
      organizationId: "org-1",
      photoId: "photo-1",
      imageURL: downloadURL.replace("photo-1.jpg", "other.jpg"),
    }),
    isHttpsError("invalid-argument")
  );
});

test("photo mutation input rejects unsafe identifiers and oversized captions", () => {
  assert.throws(
    () => parseDeleteOrganizationPhotoRequest({organizationId: "org/1", photoId: "photo-1"}),
    isHttpsError("invalid-argument")
  );
  assert.throws(
    () => parseCreateOrganizationPhotoRequest({
      organizationId: "org-1",
      photoId: "photo-1",
      imageURL: downloadURL,
      caption: "x".repeat(501),
    }),
    isHttpsError("invalid-argument")
  );
});

test("organization photo permissions match the production role contract", () => {
  const organization = {
    ownerId: "organization-owner",
    adminIds: ["organization-admin"],
    moderatorIds: ["organization-moderator"],
  };
  const activeUser = {uid: "user", accountStatus: "active" as const};

  assert.equal(canManageOrganizationPhotos(activeUser, organization, "organization-owner"), true);
  assert.equal(canManageOrganizationPhotos(activeUser, organization, "organization-admin"), true);
  assert.equal(canManageOrganizationPhotos(activeUser, organization, "organization-moderator"), true);
  assert.equal(canManageOrganizationPhotos(activeUser, organization, "unrelated-user"), false);
  assert.equal(canManageOrganizationPhotos({
    uid: "app-owner",
    accountStatus: "active",
    globalRole: "owner",
  }, organization, "app-owner"), true);
  assert.equal(canManageOrganizationPhotos({
    uid: "app-admin",
    accountStatus: "active",
    globalRole: "admin",
  }, organization, "app-admin"), false);
});

function isHttpsError(code: string): (error: unknown) => boolean {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}
