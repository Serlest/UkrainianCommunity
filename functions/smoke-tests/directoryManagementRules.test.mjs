import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {
  assertFails, assertSucceeds, initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc,
} from "firebase/firestore";

let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: "demo-uac-directory-management",
    firestore: {
      rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8"),
    },
  });
});

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users", "owner"), user("owner", "owner")),
      setDoc(doc(db, "users", "editor"), user("editor", "user")),
      setDoc(doc(db, "users", "reader"), user("reader", "user")),
      setDoc(doc(db, "users", "admin"), user("admin", "admin")),
      setDoc(doc(db, "users", "suspended"), user("suspended", "user", "suspendedUntil")),
    ]);
  });
});

after(async () => { await environment?.cleanup(); });

function user(id, globalRole, accountStatus = "active") {
  return {id, globalRole, accountStatus, blockState: "active"};
}

function db(uid, verified = true) {
  return environment.authenticatedContext(uid, {
    email: `${uid}@example.com`, email_verified: verified,
  }).firestore();
}

function content(id, revision) {
  return {
    id, revision, payload: JSON.stringify({id, title: "Test"}),
    updatedBy: "owner", updatedAt: serverTimestamp(),
  };
}

async function grant(uid = "editor") {
  await assertSucceeds(setDoc(doc(db("owner"), "directoryEditors", uid), {
    enabled: true, grantedBy: "owner", grantedAt: serverTimestamp(),
  }));
}

test("published category is readable without login; clients cannot change it", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "directoryCategories", "housing"),
      {...content("housing", 1), updatedAt: new Date()});
  });
  await assertSucceeds(getDocs(collection(environment.unauthenticatedContext().firestore(),
    "directoryCategories")));
  await assertSucceeds(getDoc(doc(db("reader"), "directoryCategories", "housing")));
  await assertFails(setDoc(doc(db("reader"), "directoryCategories", "housing"),
    {...content("housing", 2), updatedBy: "reader"}));
  await assertFails(setDoc(doc(db("owner"), "directoryCategories", "housing"),
    content("housing", 2)));
});

test("only owner grants editor; client writes remain blocked after grant and revocation", async () => {
  await assertFails(setDoc(doc(db("reader"), "directoryEditors", "editor"), {
    enabled: true, grantedBy: "reader", grantedAt: serverTimestamp(),
  }));
  await grant();
  await assertSucceeds(getDoc(doc(db("editor"), "directoryEditors", "editor")));
  await assertFails(getDoc(doc(db("reader"), "directoryEditors", "editor")));
  await assertFails(setDoc(doc(db("editor"), "directoryCategories", "health"), {
    ...content("health", 1), updatedBy: "editor",
  }));
  await assertSucceeds(deleteDoc(doc(db("owner"), "directoryEditors", "editor")));
  await assertFails(setDoc(doc(db("editor"), "directoryCategories", "health"), {
    ...content("health", 2), updatedBy: "editor",
  }));
});

test("admin is not automatically a directory editor and cannot assign one", async () => {
  await assertFails(setDoc(doc(db("admin"), "directoryEditors", "reader"), {
    enabled: true, grantedBy: "admin", grantedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db("admin"), "directoryCategories", "care"), {
    ...content("care", 1), updatedBy: "admin",
  }));
});

test("suspended or unverified editor cannot publish", async () => {
  await grant("editor");
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "directoryEditors", "suspended"), {
      enabled: true, grantedBy: "owner", grantedAt: new Date(),
    });
  });
  await assertFails(setDoc(doc(db("suspended"), "directoryCategories", "care"), {
    ...content("care", 1), updatedBy: "suspended",
  }));
  await assertFails(setDoc(doc(db("editor", false), "directoryCategories", "care"), {
    ...content("care", 1), updatedBy: "editor",
  }));
});

test("category writes stay server-only even with valid shape", async () => {
  await assertFails(setDoc(doc(db("owner"), "directoryCategories", "care"),
    content("care", 1)));
  await assertFails(setDoc(doc(db("owner"), "directoryCategories", "care"),
    {...content("care", 2), extra: true}));
  await assertFails(setDoc(doc(db("owner"), "directoryCategories", "care"),
    {...content("other", 2)}));
  await assertFails(setDoc(doc(db("owner"), "directoryCategories", "care"),
    content("care", 2)));
});
