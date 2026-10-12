import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";

import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc, updateDoc} from "firebase/firestore";

import {seedCurrentLegalVersions} from "./legalRuleFixtures.mjs";

const projectId = "demo-ukrainian-community-public-profiles";
const uid = "profile-self";
const ownerId = "profile-owner";
const avatarURL = (userId) =>
  `https://firebasestorage.googleapis.com/v0/b/ukrainiancommunity-dbd5f.firebasestorage.app/o/profileImages%2F${userId}%2Favatar.jpg?alt=media&token=123e4567-e89b-42d3-a456-426614174000`;

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8")},
  });
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [userId, role] of [[uid, "user"], [ownerId, "owner"]]) {
      await setDoc(doc(db, "users", userId), {
        id: userId,
        globalRole: role,
        accountStatus: "active",
        blockState: "active",
        fullName: "Test User",
        displayName: "Test User",
        city: "Wien",
        email: `${userId}@example.org`,
        bio: "",
        selectedFederalState: "wien",
        updatedAt: new Date(),
      });
    }
  });
});

beforeEach(async () => { await seedCurrentLegalVersions(environment); });
after(async () => { await environment?.cleanup(); });

function db(userId) {
  return environment.authenticatedContext(userId, {email_verified: true}).firestore();
}

function publicProfile(displayName = "Test User", extra = {}) {
  return {id: uid, displayName, city: "Wien", updatedAt: new Date(), ...extra};
}

test("public profile allows only bounded fields and the account's own Storage avatar", async () => {
  const reference = doc(db(uid), "publicProfiles", uid);
  await assertSucceeds(setDoc(reference, publicProfile("Test User", {avatarURL: avatarURL(uid)})));
  await assertFails(setDoc(reference, publicProfile("N".repeat(161))));
  await assertFails(setDoc(reference, publicProfile("Test User", {city: "C".repeat(161)})));
  await assertFails(setDoc(reference, publicProfile("Test User", {avatarURL: "https://example.org/avatar.jpg"})));
  await assertFails(setDoc(reference, publicProfile("Test User", {avatarURL: avatarURL(ownerId)})));
  await assertFails(setDoc(reference, publicProfile("Test User", {avatarURL: "javascript:alert(1)"})));
  await assertFails(setDoc(reference, publicProfile("Test User", {avatarURL: "x".repeat(513)})));
  await assertSucceeds(setDoc(reference, publicProfile("Test User")));
});

test("owner cannot bypass public profile validation", async () => {
  const reference = doc(db(ownerId), "publicProfiles", uid);
  await assertFails(setDoc(reference, publicProfile("N".repeat(161))));
  await assertFails(setDoc(reference, publicProfile("Test User", {avatarURL: "https://example.org/avatar.jpg"})));
  await assertSucceeds(setDoc(reference, publicProfile()));
});

test("private profile accepts only its own Storage avatar URL", async () => {
  const reference = doc(db(uid), "users", uid);
  await assertSucceeds(updateDoc(reference, {avatarURL: avatarURL(uid), updatedAt: new Date()}));
  await assertFails(updateDoc(reference, {avatarURL: "https://example.org/avatar.jpg", updatedAt: new Date()}));
  await assertFails(updateDoc(reference, {avatarURL: avatarURL(ownerId), updatedAt: new Date()}));
});
