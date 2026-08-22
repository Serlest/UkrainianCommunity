import assert from "node:assert/strict";
import test from "node:test";

import * as permissions from "../lib/permissions/userPermissions.js";

function user({
  uid,
  globalRole = "user",
  canManageGuide = false,
  accountStatus = "active",
  blockState = "active",
}) {
  return {
    uid,
    globalRole,
    canManageGuide,
    accountStatus,
    blockState,
  };
}

function organization({
  ownerId = "org-owner",
  adminIds = [],
  moderatorIds = [],
} = {}) {
  return {
    ownerId,
    adminIds,
    moderatorIds,
  };
}

function organizationRoleFor(org, actor) {
  if (!permissions.isActiveUser(actor)) {
    return undefined;
  }
  if (org.ownerId === actor.uid) {
    return "owner";
  }
  if (org.adminIds.includes(actor.uid)) {
    return "admin";
  }
  if (org.moderatorIds.includes(actor.uid)) {
    return "moderator";
  }
  return undefined;
}

function canManageOrganizationContent(org, actor) {
  if (permissions.canUseOrganizationOverride(actor)) {
    return true;
  }
  return ["owner", "admin", "moderator"].includes(organizationRoleFor(org, actor));
}

function canManageOrganizationTeam(org, actor) {
  if (permissions.canUseOrganizationOverride(actor)) {
    return true;
  }
  return organizationRoleFor(org, actor) === "owner";
}

test("App Owner has full platform access and organization override", () => {
  const owner = user({uid: "owner", globalRole: "owner"});

  assert.equal(permissions.canAssignAppAdmin(owner), true);
  assert.equal(permissions.canAssignAppModerator(owner), true);
  assert.equal(permissions.canAssignGuideEditor(owner), true);
  assert.equal(permissions.canManageUsers(owner), true);
  assert.equal(permissions.canManageGuide(owner), true);
  assert.equal(permissions.canManageOrganizationRequests(owner), true);
  assert.equal(permissions.canAccessModerationTools(owner), true);
  assert.equal(permissions.canManageFeedback(owner), true);
  assert.equal(permissions.canManageReports(owner), true);
  assert.equal(permissions.canManageFeaturedBanners(owner), true);
  assert.equal(permissions.canUseOrganizationOverride(owner), true);
});

test("App Admin can manage limited platform roles without admin assignment or org override", () => {
  const admin = user({uid: "admin", globalRole: "admin"});
  const guideAdmin = user({uid: "guide-admin", globalRole: "admin", canManageGuide: true});
  const org = organization();

  assert.equal(permissions.canManageOrganizationRequests(admin), true);
  assert.equal(permissions.canAccessModerationTools(admin), true);
  assert.equal(permissions.canManageFeedback(admin), true);
  assert.equal(permissions.canManageReports(admin), true);
  assert.equal(permissions.canAssignAppAdmin(admin), false);
  assert.equal(permissions.canAssignAppModerator(admin), true);
  assert.equal(permissions.canAssignGuideEditor(admin), true);
  assert.equal(permissions.canUseOrganizationOverride(admin), false);
  assert.equal(permissions.canManageGuide(admin), false);
  assert.equal(permissions.canManageGuide(guideAdmin), true);
  assert.equal(canManageOrganizationContent(org, admin), false);
});

test("App Moderator is moderation-only and has no organization request access", () => {
  const moderator = user({uid: "moderator", globalRole: "moderator"});
  const org = organization();

  assert.equal(permissions.canAccessModerationTools(moderator), true);
  assert.equal(permissions.canManageFeedback(moderator), true);
  assert.equal(permissions.canManageReports(moderator), true);
  assert.equal(permissions.canManageOrganizationRequests(moderator), false);
  assert.equal(permissions.canAssignAppAdmin(moderator), false);
  assert.equal(permissions.canAssignAppModerator(moderator), false);
  assert.equal(permissions.canAssignGuideEditor(moderator), false);
  assert.equal(permissions.canUseOrganizationOverride(moderator), false);
  assert.equal(canManageOrganizationContent(org, moderator), false);
});

test("Guide Editor has guide-only platform access", () => {
  const guideEditor = user({uid: "guide-editor", canManageGuide: true});
  const org = organization();

  assert.equal(permissions.canManageGuide(guideEditor), true);
  assert.equal(permissions.canManageUsers(guideEditor), false);
  assert.equal(permissions.canManageOrganizationRequests(guideEditor), false);
  assert.equal(permissions.canAccessModerationTools(guideEditor), false);
  assert.equal(permissions.canManageFeedback(guideEditor), false);
  assert.equal(permissions.canManageReports(guideEditor), false);
  assert.equal(permissions.canUseOrganizationOverride(guideEditor), false);
  assert.equal(canManageOrganizationContent(org, guideEditor), false);
});

test("Organization roles stay scoped to organization membership arrays", () => {
  const platformAdmin = user({uid: "platform-admin", globalRole: "admin"});
  const orgOwner = user({uid: "org-owner"});
  const orgAdmin = user({uid: "org-admin"});
  const orgModerator = user({uid: "org-moderator"});
  const normalUser = user({uid: "normal-user"});
  const org = organization({
    ownerId: orgOwner.uid,
    adminIds: [orgAdmin.uid],
    moderatorIds: [orgModerator.uid],
  });

  assert.equal(canManageOrganizationTeam(org, orgOwner), true);
  assert.equal(canManageOrganizationContent(org, orgOwner), true);
  assert.equal(canManageOrganizationTeam(org, orgAdmin), false);
  assert.equal(canManageOrganizationContent(org, orgAdmin), true);
  assert.equal(canManageOrganizationTeam(org, orgModerator), false);
  assert.equal(canManageOrganizationContent(org, orgModerator), true);
  assert.equal(canManageOrganizationContent(org, normalUser), false);
  assert.equal(canManageOrganizationContent(org, platformAdmin), false);
});

test("restricted accounts and legacy roles do not receive elevated access", () => {
  const suspendedOwner = user({
    uid: "suspended-owner",
    globalRole: "owner",
    blockState: "suspendedUntil",
  });
  const legacyTopAdmin = user({uid: "legacy-top-admin", globalRole: "topAdmin"});
  const legacyModerator = user({uid: "legacy-moderator", globalRole: "appModerator"});

  assert.equal(permissions.isActiveUser(suspendedOwner), false);
  assert.equal(permissions.canManageUsers(suspendedOwner), false);
  assert.equal(permissions.canUseOrganizationOverride(suspendedOwner), false);
  assert.equal(permissions.canAccessModerationTools(legacyTopAdmin), false);
  assert.equal(permissions.canAccessModerationTools(legacyModerator), false);
  assert.equal(permissions.canManageGuide(legacyTopAdmin), false);
});
