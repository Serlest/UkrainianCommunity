import {strict as assert} from "node:assert";
import {test} from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {accessReason} from "./organizationAccessDiagnostics";
import {commandEnabled, compareOrganizationDecisions, organizationRollout} from "./organizationAccessPolicy";

test("rollout preserves old default and kill switch, selects known actions and test accounts", () => {
  assert.equal(commandEnabled(undefined, "a", "updateOrganizationInfo", "editInfo"), false);
  const config = {mode: "enforced", commandsEnabled: true, enabledUserIds: ["a"],
    actionModes: {editInfo: "enforced", managePhotos: "enforced"}, commandModes: {updateOrganizationInfo: "enforced", saveOrganizationPhoto: "enforced"}};
  assert.equal(commandEnabled(config, "a", "updateOrganizationInfo", "editInfo"), true);
  assert.equal(commandEnabled(config, "b", "updateOrganizationInfo", "editInfo"), false);
  assert.equal(commandEnabled(config, "a", "updateOrganizationInfo", "resubmitRequest"), false);
  assert.equal(commandEnabled({...config, mode: "shadow"}, "a", "saveOrganizationPhoto", "managePhotos"), false);
  assert.equal(commandEnabled({...config, rolloutPercent: 0}, "a", "saveOrganizationPhoto", "managePhotos"), false);
  assert.equal(commandEnabled({...config, rolloutPercent: "100"}, "a", "saveOrganizationPhoto", "managePhotos"), false);
  const old = organizationRollout({mode: "enforced", commandsEnabled: true}, "a");
  assert.equal(old.commands.updateOrganizationInfo, true);
  assert.equal(old.commands.saveOrganizationPhoto, false);
});

test("a partial rollout is deterministic and never treats unknown actions as permissions", () => {
  const config = {mode: "enforced", commandsEnabled: true, rolloutPercent: 30};
  const decisions = Array.from({length: 1000}, (_, i) => organizationRollout(config, `u${i}`).mode);
  assert.deepEqual(decisions, Array.from({length: 1000}, (_, i) => organizationRollout(config, `u${i}`).mode));
  assert.ok(decisions.filter(x => x === "enforced").length > 200 && decisions.filter(x => x === "enforced").length < 400);
  assert.deepEqual(compareOrganizationDecisions({editInfo: true, manageTeam: false, inventedAction: true, createNews: "true"}, ["manageTeam"]), [
    {action: "editInfo", client: true, server: false}, {action: "manageTeam", client: false, server: true},
  ]);
});

test("diagnostics separate actor, session, request, conflict, limit and uncertain result", () => {
  const cases = [
    [new HttpsError("unauthenticated", "Authentication is required."), "sign_in_required"],
    [new HttpsError("permission-denied", "A verified email address is required."), "email_unverified"],
    [new HttpsError("permission-denied", "An active account is required."), "account_inactive"],
    [new HttpsError("failed-precondition", "A TOTP-authenticated session is required."), "session_refresh_required"],
    [new HttpsError("permission-denied", "The account changed before saving."), "account_changed"],
    [new HttpsError("permission-denied", "Not allowed."), "role_missing"],
    [new HttpsError("aborted", "Changed."), "object_changed"],
    [new HttpsError("invalid-argument", "Invalid."), "invalid_request"],
    [new HttpsError("resource-exhausted", "Limit."), "limit_reached"],
    [new Error("private user data"), "outcome_unknown"],
  ] as const;
  for (const [error, expected] of cases) assert.equal(accessReason(error), expected);
});
