import {after, before, test} from "node:test";
import {readFileSync} from "node:fs";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc, deleteField, serverTimestamp} from "firebase/firestore";
let env;
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Emulator required");
  env = await initializeTestEnvironment({projectId: "demo-uac-admin-search-rules", firestore: {
    rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8"),
  }});
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    await setDoc(doc(db, "legalDocuments/terms"), {activeVersion: "1"});
    await setDoc(doc(db, "legalDocuments/privacy"), {activeVersion: "1"});
    for (const role of ["user", "owner", "admin"]) {
      await setDoc(doc(db, "users", role), {id: role, globalRole: role, accountStatus: "active", blockState: "active",
        fullName: "Member", displayName: "Member", email: `${role}@example.com`, city: "Wien", bio: "", selectedFederalState: "Wien",
        acceptedTermsVersion: "1", acceptedPrivacyVersion: "1", updatedAt: serverTimestamp(), adminSearchGramsV1: ["mem"]});
    }
    await setDoc(doc(db, "internalSearchState/usersV1"), {ready: true, version: 1});
  });
});
after(async () => { await env?.cleanup(); });
test("existing app profile update and read remain allowed with derived index present", async () => {
  const db = env.authenticatedContext("user", {email_verified: true}).firestore();
  await assertSucceeds(updateDoc(doc(db, "users/user"), {fullName: "New Name", displayName: "New Name", city: "Graz",
    bio: "Updated", telegramUsername: null, selectedFederalState: "Steiermark", avatarURL: deleteField(), updatedAt: serverTimestamp()}));
  await assertSucceeds(getDoc(doc(db, "users/user")));
});
test("no client can forge index or enable/disable private search switch", async () => {
  for (const role of [null, "owner", "admin", "user"]) {
    const db = role ? env.authenticatedContext(role, {email_verified: true}).firestore() : env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "internalSearchState/usersV1")));
    await assertFails(setDoc(doc(db, "internalSearchState/usersV1"), {ready: true, version: 1}));
    await assertFails(updateDoc(doc(db, "users", role ?? "user"), {adminSearchGramsV1: ["spoof"]}));
    await assertFails(updateDoc(doc(db, "users", role ?? "user"), {adminSearchGramsV1: deleteField()}));
  }
});
