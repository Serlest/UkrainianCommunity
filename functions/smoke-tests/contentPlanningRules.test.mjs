import {after, before, test} from "node:test";
import {readFileSync} from "node:fs";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, Timestamp, updateDoc} from "firebase/firestore";

let env;
const draftPath = "users/owner/contentPlanningDrafts/draft-1";

before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Firestore emulator required");
  env = await initializeTestEnvironment({
    projectId: "demo-ukrainian-community-content-planning-rules",
    firestore: {
      rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8"),
    },
  });
  await env.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    await setDoc(doc(database, "users", "owner"), {
      globalRole: "owner", accountStatus: "active", blockState: "active",
    });
    await setDoc(doc(database, "users", "admin"), {
      globalRole: "admin", accountStatus: "active", blockState: "active",
    });
    await setDoc(doc(database, "users", "user"), {
      globalRole: "user", accountStatus: "active", blockState: "active",
    });
    await setDoc(doc(database, draftPath), {
      id: "draft-1",
      ownerUserId: "owner",
      schemaVersion: 1,
      kind: "news",
      state: "readyForReview",
      title: "Private draft",
      payload: {title: "Private draft"},
      sources: [{url: "https://example.org", isPrimary: true}],
      verificationNotes: [],
      missingFields: [],
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      completedAt: null,
    });
  });
});

after(async () => { await env?.cleanup(); });

test("only the verified app owner can read private planning drafts", async () => {
  const owner = env.authenticatedContext("owner", {email_verified: true}).firestore();
  const admin = env.authenticatedContext("admin", {email_verified: true}).firestore();
  const user = env.authenticatedContext("user", {email_verified: true}).firestore();

  await assertSucceeds(getDoc(doc(owner, draftPath)));
  await assertFails(getDoc(doc(admin, draftPath)));
  await assertFails(getDoc(doc(user, draftPath)));
});

test("even the owner cannot mutate planning records directly", async () => {
  const owner = env.authenticatedContext("owner", {email_verified: true}).firestore();
  const reference = doc(owner, draftPath);

  await assertFails(updateDoc(reference, {
    state: "completed",
    updatedAt: Timestamp.now(),
    completedAt: Timestamp.now(),
  }));
  await assertFails(updateDoc(reference, {title: "Changed by client"}));
  await assertFails(updateDoc(reference, {state: "archived", updatedAt: Timestamp.now()}));
});

test("clients cannot create or delete planning drafts", async () => {
  const owner = env.authenticatedContext("owner", {email_verified: true}).firestore();
  await assertFails(setDoc(doc(owner, "users/owner/contentPlanningDrafts/client-created"), {
    state: "readyForReview",
  }));
  await assertFails(deleteDoc(doc(owner, draftPath)));
});
