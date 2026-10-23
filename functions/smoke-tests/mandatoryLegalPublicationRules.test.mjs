import {after, before, beforeEach, test} from "node:test";
import {readFileSync} from "node:fs";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, serverTimestamp, setDoc} from "firebase/firestore";

const projectId = "demo-uac-mandatory-legal-publication";
const hash = "a".repeat(64);
const publishedAt = new Date("2026-10-12T11:00:00Z");
let environment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8")},
  });
});

after(async () => { await environment?.cleanup(); });

beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await Promise.all([
      setDoc(doc(database, "users/owner"), {
        id: "owner", globalRole: "owner", accountStatus: "active", blockState: "active",
        acceptedTermsVersion: "2026.13", acceptedPrivacyVersion: "2026.18",
      }),
      setDoc(doc(database, "legalDocuments/terms"), {
        documentType: "terms", activeVersion: "2026.13", versionNumber: 202613,
        status: "published", requiresAcceptance: true,
      }),
      setDoc(doc(database, "legalDocuments/privacy"), {
        documentType: "privacy", activeVersion: "2026.18", versionNumber: 202618,
        status: "published", requiresAcceptance: false,
      }),
    ]);
  });
});

function ownerDatabase() {
  return environment.authenticatedContext("owner", {
    email: "owner@example.com", email_verified: true,
  }).firestore();
}

async function publish(requiresAcceptance) {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "legalDocuments/privacy/versions/2026.19"), {
      documentType: "privacy", version: "2026.19", versionNumber: 202619,
      status: "published", requiresAcceptance,
      defaultLocale: "de", canonicalLocale: "de", contentHash: hash,
      locales: Object.fromEntries(["de", "uk"].map(locale => [locale, {
        title: "Privacy", contentMarkdown: "Updated privacy policy", contentHash: hash,
      }])),
      supersedesVersion: "2026.18",
      createdAt: publishedAt, createdBy: "owner", updatedAt: publishedAt, updatedBy: "owner",
      publishedAt, publishedBy: "owner", changeSummary: "Read and accept the update.",
    });
  });
  const database = ownerDatabase();
  return setDoc(doc(database, "legalDocuments/privacy"), {
    documentType: "privacy", activeVersion: "2026.19", versionNumber: 202619,
    status: "published", requiresAcceptance, defaultLocale: "de",
    updatedAt: serverTimestamp(), updatedBy: "owner",
    publishedAt, publishedBy: "owner",
    changeSummary: "Read and accept the update.",
  });
}

test("publishing updated privacy policy without mandatory acceptance is denied", async () => {
  await assertFails(publish(false));
  let pointer;
  await environment.withSecurityRulesDisabled(async context => {
    pointer = await getDoc(doc(context.firestore(), "legalDocuments/privacy"));
  });
  if (pointer.get("activeVersion") !== "2026.18") throw new Error("Pointer changed after rejected publication");
});

test("publishing updated privacy policy with mandatory acceptance succeeds", async () => {
  await assertSucceeds(publish(true));
  let pointer;
  await environment.withSecurityRulesDisabled(async context => {
    pointer = await getDoc(doc(context.firestore(), "legalDocuments/privacy"));
  });
  if (pointer.get("activeVersion") !== "2026.19") throw new Error("Pointer did not advance");
});

test("owner can discard an incomplete private draft but cannot delete published versions", async () => {
  const database = ownerDatabase();
  const draft = doc(database, "legalDocuments/privacy/versions/2026.19");
  const {deleteDoc} = await import("firebase/firestore");
  await assertSucceeds(setDoc(draft, {
    documentType: "privacy", version: "2026.19", versionNumber: 202619,
    status: "draft", requiresAcceptance: true, defaultLocale: "de", canonicalLocale: "de",
    contentHash: hash, baseContentHash: null, supersedesVersion: "2026.18",
    locales: Object.fromEntries(["de", "uk"].map(locale => [locale, {title: "", contentMarkdown: "", contentHash: hash}])),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: "owner", updatedBy: "owner",
    publishedAt: null, publishedBy: null, changeSummary: null,
  }));
  const other = environment.authenticatedContext("outsider", {email_verified: true}).firestore();
  await assertFails(deleteDoc(doc(other, "legalDocuments/privacy/versions/2026.19")));
  await assertSucceeds(deleteDoc(draft));
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "legalDocuments/privacy/versions/2026.18"), {status: "published"});
  });
  await assertFails(deleteDoc(doc(database, "legalDocuments/privacy/versions/2026.18")));
});
