import {strict as assert} from "node:assert";
import {test} from "node:test";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {accessPolicyConfiguration, getOrganizationAccess, organizationActions, organizationRevision, parseOrganizationFields, updateOrganizationInfo} from "./organizationAccess";
import {cancelEvent, finishEventCancellation} from "../notifications/backendWriters";
import {mutateEventRegistration} from "../events/eventRegistration";
import {createOrganizationPhotoMetadata} from "./organizationPhotoMutations";

const enabled = !!process.env.FIRESTORE_EMULATOR_HOST;
const request = (uid: string, data: unknown) => ({data, auth: {uid, token: {email_verified: true}}}) as any;

test("action matrix preserves platform and organization role distinctions", () => {
  const org = {id: "org", ownerId: "owner", adminIds: ["admin"], moderatorIds: ["moderator"], moderationStatus: "approved"};
  const actions = (uid: string, globalRole: "owner" | "admin" | "user" = "user") => organizationActions({uid, globalRole}, org);
  assert.equal(actions("owner").includes("editInfo"), true);
  assert.equal(actions("admin").includes("editInfo"), true);
  assert.equal(actions("moderator").includes("editInfo"), false);
  assert.equal(actions("moderator").includes("managePhotos"), true);
  assert.equal(actions("outsider", "admin").includes("editInfo"), false);
  assert.equal(actions("platform", "owner").includes("editInfo"), true);
  assert.deepEqual(organizationActions({uid: "owner", blockState: "bannedPermanent"}, org), []);
  assert.throws(() => parseOrganizationFields({ownerId: "outsider"}));
  assert.throws(() => parseOrganizationFields({photoCount: 0}));
  assert.throws(() => parseOrganizationFields({name: ""}));
  for (const invalid of [null, "2026-09-04", 123, {}, {__timestamp: {seconds: 123, nanoseconds: -1}}]) {
    assert.throws(() => parseOrganizationFields({directoryProfile: {profileKind: "business", currentOfferValidUntil: invalid}}));
  }
  const parsed = parseOrganizationFields({directoryProfile: {profileKind: "business", currentOfferValidUntil: {__timestamp: {seconds: 1788440797, nanoseconds: 184433000}}}});
  assert.ok(parsed.directoryProfile.currentOfferValidUntil.isEqual(new Timestamp(1788440797, 184433000)));
});

test("commands preserve protected fields, reject stale edits and revoked roles, and replay once", {skip: !enabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const prefix = "access-" + randomUUID();
  const uid = prefix + "-user";
  const outsider = prefix + "-outside";
  const org = db.doc(`organizations/${prefix}`);
  const profile = db.doc(`users/${uid}`);
  const other = db.doc(`users/${outsider}`);
  const config = db.doc(accessPolicyConfiguration);
  const now = new Timestamp(1788440797, 184433000);
  const base = {id: org.id, name: "Organization", description: "Description", city: "Wien", ownerId: uid,
    adminIds: [], moderatorIds: [], moderationStatus: "approved", createdAt: now, updatedAt: now, submittedAt: now, photoCount: 5};
  try {
    await profile.set({globalRole: "user", accountStatus: "active"});
    await other.set({globalRole: "admin", accountStatus: "active"});
    await org.set(base);
    await config.set({mode: "enforced", commandsEnabled: true});
    const capabilities = await getOrganizationAccess.run(request(uid, {organizationIds: [org.id]}));
    assert.equal(capabilities.records[0].actions.includes("editInfo"), true);
    const input = {principalId: uid, organizationId: org.id, operationId: randomUUID(), fields: {website: "https://example.org"},
      expectedRevision: organizationRevision(base), targetStatus: "approved"};
    await assert.rejects(updateOrganizationInfo.run(request(outsider, input)), {code: "permission-denied"});
    const first = await updateOrganizationInfo.run(request(uid, input));
    const repeated = await updateOrganizationInfo.run(request(uid, input));
    assert.equal(first.didChange, true); assert.equal(repeated.didChange, false);
    assert.equal(first.revision, repeated.revision);
    const saved = (await org.get()).data()!;
    assert.equal(saved.submittedAt.isEqual(now), true); assert.equal(saved.photoCount, 5); assert.equal(saved.ownerId, uid);
    await assert.rejects(updateOrganizationInfo.run(request(uid, {...input, operationId: randomUUID(), fields: {name: "Stale"}})), {code: "aborted"});
    const revision = organizationRevision(saved);
    const concurrent = await Promise.allSettled(["One", "Two"].map(name => updateOrganizationInfo.run(request(uid, {
      ...input, operationId: randomUUID(), fields: {name}, expectedRevision: revision,
    }))));
    assert.equal(concurrent.filter(x => x.status === "fulfilled").length, 1);
    await org.update({ownerId: outsider});
    await assert.rejects(updateOrganizationInfo.run(request(uid, {...input, operationId: randomUUID()})), {code: "permission-denied"});
    await org.update({ownerId: null, submittedByUserId: uid, moderationStatus: "rejected", reviewMessage: "Fix details", rejectionReason: "Incomplete"});
    const resubmit = {...input, operationId: randomUUID(), targetStatus: "pendingReview",
      expectedRevision: organizationRevision((await org.get()).data()!)};
    await updateOrganizationInfo.run(request(uid, resubmit));
    assert.equal((await org.get()).get("moderationStatus"), "pendingReview");
    assert.equal((await org.get()).get("reviewMessage"), undefined);
    await profile.update({globalRole: "owner", requiresMultiFactorAuth: true});
    const protectedUpdate = {...input, operationId: randomUUID(), targetStatus: "pendingReview",
      expectedRevision: organizationRevision((await org.get()).data()!)};
    await assert.rejects(updateOrganizationInfo.run(request(uid, protectedUpdate)), {code: "failed-precondition"});
    const totp = request(uid, protectedUpdate);
    totp.auth.token.firebase = {sign_in_second_factor: "totp"};
    await updateOrganizationInfo.run(totp);
  } finally {
    const receipts = await db.collection("organizationMutationReceipts").where("organizationId", "==", org.id).get();
    await Promise.all([...receipts.docs.map(x => x.ref), org, profile, other, config].map(ref => ref.delete()));
  }
});

test("cancellation is repeatable and photo metadata remains atomic under revoked access", {skip: !enabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  const prefix = "cancel-" + randomUUID();
  const uid = prefix + "-owner", attendee = prefix + "-attendee";
  const org = db.doc(`organizations/${prefix}`), event = db.doc(`events/${prefix}`);
  const owner = db.doc(`users/${uid}`), user = db.doc(`users/${attendee}`);
  const registration = db.doc(`registrations/${prefix}`);
  const op = db.doc(`eventCancellationOperations/${prefix}`);
  try {
    await owner.set({globalRole: "user", accountStatus: "active"});
    await user.set({globalRole: "user", accountStatus: "active", language: "de"});
    await org.set({id: org.id, ownerId: uid, adminIds: [], moderatorIds: [], photoCount: 0});
    await event.set({id: event.id, sourceType: "organization", organizationId: org.id, title: "Event", moderationStatus: "approved", registeredCount: 1, startDate: Timestamp.fromMillis(Date.now() + 3600000)});
    await registration.set({eventId: event.id, userId: attendee});
    await assert.rejects(cancelEvent.run(request(attendee, {eventId: event.id})), {code: "permission-denied"});
    const first = await cancelEvent.run(request(uid, {eventId: event.id}));
    const second = await cancelEvent.run(request(uid, {eventId: event.id}));
    assert.deepEqual(first, second); assert.equal(first.status, "cancelled");
    assert.equal((await event.get()).get("moderationStatus"), "archived");
    const inbox = await user.collection("notificationInbox").get();
    assert.equal(inbox.size, 1);
    const photo = {organizationId: org.id, photoId: "fixture", imageURL: `https://firebasestorage.googleapis.com/v0/b/demo/o/${encodeURIComponent(`organizations/${org.id}/photos/fixture.jpg`)}?alt=media`};
    await assert.rejects(createOrganizationPhotoMetadata.run(request(uid, {...photo, principalId: attendee})), {code: "permission-denied"});
    await createOrganizationPhotoMetadata.run(request(uid, {...photo, principalId: uid}));
    await createOrganizationPhotoMetadata.run(request(uid, photo));
    assert.equal((await org.get()).get("photoCount"), 1);
    await owner.update({blockState: "bannedPermanent"});
    await assert.rejects(createOrganizationPhotoMetadata.run(request(uid, {...photo, photoId: "denied"})), {code: "permission-denied"});
  } finally {
    for (const ref of [org, event, owner, user, registration, op]) await db.recursiveDelete(ref);
  }
});


test("empty cancellation recovers lost cleanup response and blocks later registration", {skip: !enabled}, async () => {
  assert.match(process.env.GCLOUD_PROJECT ?? "", /^demo-/);
  assert.ok(process.env.FIREBASE_STORAGE_EMULATOR_HOST);
  const id = "empty-" + randomUUID(), uid = id + "-owner";
  const owner = db.doc(`users/${uid}`), event = db.doc(`events/${id}`), op = db.doc(`eventCancellationOperations/${id}`);
  try {
    await owner.set({globalRole: "owner"});
    await event.set({title: "Empty event", sourceType: "community", moderationStatus: "approved", registeredCount: 0,
      startDate: Timestamp.fromMillis(Date.now() + 86400000), endDate: Timestamp.fromMillis(Date.now() + 90000000)});
    const first = await cancelEvent.run(request(uid, {eventId: id}));
    assert.equal(first.status, "deleted");
    assert.equal((await event.get()).exists, false);
    assert.deepEqual(await cancelEvent.run(request(uid, {eventId: id})), first);
    assert.equal((await op.get()).get("eventData"), undefined);
    assert.equal((await op.get()).get("recipients"), undefined);
    await assert.rejects(mutateEventRegistration("register", id, uid));
    // A pending operation can finish when document cleanup committed before the response was lost.
    await op.update({status: "pending", eventData: {sourceType: "community"}, recipients: []});
    assert.deepEqual(await finishEventCancellation(id), first);
    // Reusing the content ID cannot falsely acknowledge the previous cancellation.
    await event.set({sourceType: "community", moderationStatus: "approved"});
    await assert.rejects(cancelEvent.run(request(uid, {eventId: id})), {code: "failed-precondition"});
  } finally {
    for (const ref of [owner, event, op]) await db.recursiveDelete(ref);
  }
});


test("server capability contract matches all 1080 released-client decisions", () => {
  const contract = JSON.parse(readFileSync(resolve(__dirname, "../../../Contracts/organization-access-v1.json"), "utf8"));
  for (const fixture of contract.fixtures) {
    const user: any = {uid: fixture.actor, globalRole: "user"};
    if (fixture.actor === "owner") user.globalRole = "owner";
    if (fixture.actor === "app-admin") user.globalRole = "admin";
    if (fixture.actor === "legacy-top-admin") { user.globalRole = "topAdmin"; user.uid = "legacy"; }
    if (fixture.actor === "blocked-org-owner") { user.uid = "org-owner"; user.blockState = "bannedPermanent"; }
    if (fixture.actor === "warned-org-owner") { user.uid = "org-owner"; user.accountStatus = "warned"; }
    const org = {id: fixture.system ? "ukrainian-community" : "fixture", ownerId: "org-owner", adminIds: ["org-admin"],
      moderatorIds: ["org-moderator"], submittedByUserId: "outsider", moderationStatus: fixture.state};
    const allowed = fixture.actor === "guest" ? [] : organizationActions(user, org);
    for (const [action, expected] of Object.entries(fixture.expected)) {
      assert.equal(allowed.includes(action), expected, `${fixture.actor}/${fixture.state}/system=${fixture.system}/${action}`);
    }
  }
});
