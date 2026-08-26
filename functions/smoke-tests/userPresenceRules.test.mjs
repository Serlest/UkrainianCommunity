import {after, before, test} from "node:test";
import {readFileSync} from "node:fs";
import {assertFails, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, deleteDoc, collection, getDocs} from "firebase/firestore";

let env;
before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Firestore emulator required");
  env = await initializeTestEnvironment({projectId: "demo-ukrainian-community-presence-rules", firestore: {
    rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8"),
  }});
  await env.withSecurityRulesDisabled(async (context) => {
    const database = context.firestore();
    for (const role of ["owner", "admin", "user"]) {
      await setDoc(doc(database, "users", role), {globalRole: role, accountStatus: "active", blockState: "active"});
    }
    await setDoc(doc(database, "users/user/privatePresence/current"), {lastSeenAt: 123, sessions: {}});
  });
});
after(async () => { await env?.cleanup(); });

test("all clients including self, administrator and owner must use authorized presence callables", async () => {
  for (const role of [null, "owner", "admin", "user"]) {
    const database = role ? env.authenticatedContext(role, {email_verified: true}).firestore() : env.unauthenticatedContext().firestore();
    const reference = doc(database, "users/user/privatePresence/current");
    await assertFails(getDoc(reference));
    await assertFails(getDocs(collection(database, "users/user/privatePresence")));
    await assertFails(setDoc(reference, {lastSeenAt: Date.now(), sessions: {}}));
    await assertFails(deleteDoc(reference));
  }
});
