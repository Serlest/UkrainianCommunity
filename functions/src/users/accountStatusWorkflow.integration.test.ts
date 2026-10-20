import {strict as assert} from "node:assert";
import {getMessaging} from "firebase-admin/messaging";
import {randomUUID} from "node:crypto";
import {test} from "node:test";
import {adminAuth, db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {warnUser, suspendUser, banUser, deactivateUser, restoreUser} from "./accountStatusManagement";
import {resolveNotificationRecipients} from "../notifications/notificationPayloads";
import {deliverInboxNotificationPushOnCreate, localizedAlertKeys, shouldDeliverInboxNotificationPush} from "../notifications/inboxPushDelivery";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST && process.env.FIREBASE_AUTH_EMULATOR_HOST);
test("owner restrictions target only the selected account, preserve restrictions and deduplicate retries", {skip: !enabled}, async (t) => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const prefix = `status-${randomUUID()}`;
  const owner = `${prefix}-owner`, target = `${prefix}-target`, other = `${prefix}-other`;
  const request = (actor: string, data: object) => ({data, auth: {uid: actor, token: {
    email_verified: true, firebase: {sign_in_second_factor: "totp"},
  }}} as any);
  const payload = {targetUserId: target, reason: "Test policy violation"};
  const delivered: string[][] = [];
  t.mock.method(getMessaging(), "sendEachForMulticast", async (message: {tokens: string[]}) => {
    delivered.push(message.tokens);
    return {successCount: message.tokens.length, failureCount: 0,
      responses: message.tokens.map(() => ({success: true, messageId: "local-test"}))};
  });
  const inbox = db.collection(`users/${target}/notificationInbox`);
  const invoke = (callable: typeof warnUser, data: object = payload, actor = owner) => callable.run(request(actor, data));
  const verifyNotice = async (status: string, count: number) => {
    const messages = await inbox.get();
    assert.equal(messages.size, count);
    const latest = messages.docs.find(d => d.get("metadata.newAccountStatus") === status);
    assert.ok(latest, `Missing ${status} notice`);
    assert.equal(latest.get("recipientUserId"), target);
    assert.equal(latest.get("actorUserId"), owner);
    assert.equal(latest.get("metadata.reason"), payload.reason);
    assert.equal(shouldDeliverInboxNotificationPush("accountStatusChanged", latest.get("metadata")), true);
    assert.ok(localizedAlertKeys("accountStatusChanged", latest.get("metadata")).titleLocKey.startsWith("account_status_alert."));
    for (const uid of [owner, other]) assert.equal((await db.collection(`users/${uid}/notificationInbox`).get()).size, 0);
  };
  try {
    for (const uid of [owner, target, other]) {
      await adminAuth.createUser({uid, email: `${uid}@example.test`, emailVerified: true});
      await db.doc(`users/${uid}`).set({globalRole: uid === owner ? "owner" : "user",
        accountStatus: "active", blockState: "active", warningCount: 0, requiresMultiFactorAuth: uid === owner});
      await db.doc(`users/${uid}/notificationPreferences/settings`).set({notificationsEnabled: true});
      await db.doc(`users/${uid}/notificationPushTokens/device`).set({token: `fake-token-${uid}`, registrationType: "token", platform: "ios"});
    }
    await seedCurrentLegalForIntegration(owner, target, other);
    await assert.rejects(invoke(warnUser, payload, other), {code: "permission-denied"});
    await assert.rejects(invoke(warnUser, {targetUserId: owner}), {code: "failed-precondition"});
    await assert.rejects(invoke(suspendUser, {...payload, until: "2000-01-01"}), {code: "invalid-argument"});
    const warnings = await Promise.all([invoke(warnUser), invoke(warnUser)]);
    assert.deepEqual(warnings.map(w => w.warningCount), [1, 1]);
    await verifyNotice("warned", 1);
    const until = new Date(Date.now() + 86400000).toISOString();
    await invoke(suspendUser, {...payload, until});
    await verifyNotice("suspendedUntil", 2);
    const suspendedNotice = (await inbox.get()).docs.find(d => d.get("metadata.newAccountStatus") === "suspendedUntil")!;
    const event = {data: suspendedNotice, params: {userId: target, notificationId: suspendedNotice.id}} as any;
    await deliverInboxNotificationPushOnCreate.run(event);
    await deliverInboxNotificationPushOnCreate.run(event);
    assert.deepEqual(delivered, [[`fake-token-${target}`]], "Only the selected user's device, once");
    assert.equal((await db.doc(`users/${target}`).get()).get("banExpiresAt").toDate().toISOString(), until);
    await invoke(suspendUser, {...payload, until});
    assert.equal((await inbox.get()).size, 2);
    await assert.rejects(invoke(warnUser), {code: "failed-precondition"});
    assert.equal((await db.doc(`users/${target}`).get()).get("isBlocked"), true);
    assert.ok((await adminAuth.getUser(target)).tokensValidAfterTime);
    assert.deepEqual((await resolveNotificationRecipients([target], {allowRestrictedPush: true})).pushRecipientIds, [target]);
    assert.deepEqual((await resolveNotificationRecipients([target])).pushRecipientIds, []);
    await db.doc(`users/${target}/notificationPreferences/settings`).update({notificationsEnabled: false});
    assert.deepEqual((await resolveNotificationRecipients([target], {allowRestrictedPush: true})).pushRecipientIds, []);
    await invoke(banUser);
    await verifyNotice("bannedPermanent", 3);
    await assert.rejects(invoke(suspendUser, {...payload, until}), {code: "failed-precondition"});
    await assert.rejects(invoke(warnUser), {code: "failed-precondition"});
    await invoke(restoreUser);
    await verifyNotice("active", 4);
    await invoke(restoreUser);
    assert.equal((await inbox.get()).size, 4);
    await invoke(deactivateUser);
    await verifyNotice("deactivated", 5);
    await assert.rejects(invoke(warnUser), {code: "failed-precondition"});
    await invoke(restoreUser);
    assert.equal((await db.doc(`users/${target}`).get()).get("accountStatus"), "active");
    assert.equal((await inbox.get()).size, 6);
    assert.equal((await db.collection("auditLogs").where("targetUserId", "==", target).get()).size, 6);
    const revokeFailure = t.mock.method(adminAuth, "revokeRefreshTokens", async () => { throw new Error("Emulated auth outage"); });
    await assert.rejects(invoke(banUser), (error: any) => error.code === "internal"
      && error.details.accountStatusCommitted === true && error.details.reason === "session-revocation-failed");
    assert.equal((await db.doc(`users/${target}`).get()).get("accountStatus"), "bannedPermanent");
    assert.equal((await inbox.get()).size, 7);
    revokeFailure.mock.restore();
    await invoke(banUser);
    assert.equal((await inbox.get()).size, 7);
    assert.equal((await db.collection("auditLogs").where("targetUserId", "==", target).get()).size, 7);
  } finally {
    for (const uid of [owner, target, other]) {
      await db.recursiveDelete(db.doc(`users/${uid}`));
      await adminAuth.deleteUser(uid).catch(() => undefined);
    }
    const audits = await db.collection("auditLogs").where("targetUserId", "==", target).get();
    await Promise.all(audits.docs.map(d => d.ref.delete()));
  }
});
