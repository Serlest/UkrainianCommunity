import assert from "node:assert/strict";
import test from "node:test";

import {notificationDefaults} from "../lib/notifications/notificationPayloads.js";
import * as permissions from "../lib/permissions/userPermissions.js";
import * as platformRoles from "../lib/users/platformRoleManagement.js";

function user({
  uid,
  globalRole = "user",
  accountStatus = "active",
  blockState = "active",
}) {
  return {
    uid,
    globalRole,
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
  assert.equal(permissions.canManageUsers(owner), true);
  assert.equal(permissions.canManageOrganizationRequests(owner), true);
  assert.equal(permissions.canAccessModerationTools(owner), true);
  assert.equal(permissions.canManageFeedback(owner), true);
  assert.equal(permissions.canManageReports(owner), true);
  assert.equal(permissions.canManageFeaturedBanners(owner), true);
  assert.equal(permissions.canUseOrganizationOverride(owner), true);
});

test("App Admin has limited platform access without admin assignment or org override", () => {
  const admin = user({uid: "admin", globalRole: "admin"});
  const org = organization();

  assert.equal(permissions.canManageOrganizationRequests(admin), true);
  assert.equal(permissions.canAccessModerationTools(admin), true);
  assert.equal(permissions.canManageFeedback(admin), true);
  assert.equal(permissions.canManageReports(admin), true);
  assert.equal(permissions.canAssignAppAdmin(admin), false);
  assert.equal(permissions.canUseOrganizationOverride(admin), false);
  assert.equal(canManageOrganizationContent(org, admin), false);
});

test("retired platform permission exports stay unavailable", () => {
  assert.equal("canAssignGuideEditor" in permissions, false);
  assert.equal("canManageGuide" in permissions, false);
  assert.equal("assertCanManageGuide" in permissions, false);
});

test("platform role callables only expose App Admin mutations", () => {
  assert.equal(typeof platformRoles.assignAppAdmin, "function");
  assert.equal(typeof platformRoles.removeAppAdmin, "function");
  assert.equal("assignGuideEditor" in platformRoles, false);
  assert.equal("removeGuideEditor" in platformRoles, false);
});

test("reviewed reports use a neutral notification route", () => {
  assert.deepEqual(notificationDefaults("reportReviewed"), {
    severity: "info",
    actionType: "none",
    sourceType: "system",
  });
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
  const removedModerator = user({uid: "removed-moderator", globalRole: "moderator"});

  assert.equal(permissions.isActiveUser(suspendedOwner), false);
  assert.equal(permissions.canManageUsers(suspendedOwner), false);
  assert.equal(permissions.canUseOrganizationOverride(suspendedOwner), false);
  assert.equal(permissions.canAccessModerationTools(legacyTopAdmin), false);
  assert.equal(permissions.canAccessModerationTools(legacyModerator), false);
  assert.equal(permissions.canAccessModerationTools(removedModerator), false);
  assert.equal(permissions.canManageFeedback(removedModerator), false);
  assert.equal(permissions.canManageReports(removedModerator), false);
});

test("feedback notifications target only active platform management roles", () => {
  assert.deepEqual(permissions.feedbackManagerGlobalRoles, ["owner", "admin"]);
  assert.equal(permissions.feedbackManagerGlobalRoles.includes("moderator"), false);
  assert.equal(permissions.feedbackManagerGlobalRoles.includes("appModerator"), false);
});
