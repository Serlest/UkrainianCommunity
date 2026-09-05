import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { checkContentFixtures } from "./content-fixtures.mjs";
const require = createRequire(new URL("../../functions/package.json", import.meta.url));
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, serverTimestamp } = require("firebase/firestore");
const projectId = "demo-uac-android";
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8088") {
  throw new Error("Refusing to run outside the explicit local Firestore emulator.");
}
const env = await initializeTestEnvironment({
  projectId,
  firestore: { host: "127.0.0.1", port: 8088,
    rules: readFileSync(new URL("../../Firebase/firestore.rules", import.meta.url), "utf8") }
});
try {
  // No export/import and no clearFirestore: only these known synthetic IDs are written.
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, "news/synthetic-android-welcome"), {
      id: "synthetic-android-welcome", title: "Lokaler Firebase-Test", summary: "Synthetic fixture",
      body: "Synthetic data only", sourceType: "organization", organizationId: "synthetic-org",
      moderationStatus: "approved", createdAt: new Date("2026-09-02T10:00:00Z"),
      updatedAt: new Date("2026-09-02T10:00:00Z"), publishedAt: new Date("2026-09-02T10:00:00Z"),
      localizations: {
        de: { title: "Lokaler Firebase-Test", subtitle: "Synthetisches Beispiel", body: "Aus dem lokalen Emulator, mit unveränderten UAC-Leseregeln." },
        uk: { title: "Локальна перевірка Firebase", subtitle: "Вигаданий приклад", body: "З локального емулятора, з незміненими правилами читання UAC." }
      }
    });
    await setDoc(doc(db, "news/synthetic-private"), { moderationStatus: "pendingReview" });
    for (const [uid, role, mfa] of [
      ["synthetic-user", "user", false], ["synthetic-owner", "owner", true],
      ["synthetic-legacy", "topAdmin", false]
    ]) await setDoc(doc(db, "users", uid), {
      id: uid, globalRole: role, accountStatus: "active", blockState: "active",
      requiresMultiFactorAuth: mfa
    });
  });
  let passed = 0;
  const guest = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(guest, "news/synthetic-android-welcome"))); passed++;
  await assertFails(getDoc(doc(guest, "news/synthetic-private"))); passed++;
  const auth = (uid, verified = true, totp = false) => env.authenticatedContext(uid, {
    email_verified: verified, ...(totp ? { firebase: { sign_in_second_factor: "totp" } } : {})
  }).firestore();
  const write = (db, uid, platform, overrides = {}) => setDoc(doc(db, "users", uid, "notificationPushTokens", "synthetic-device"), {
    id: "synthetic-device", token: "synthetic-token", registrationType: "token", platform,
    updatedAt: serverTimestamp(), ...overrides
  });
  await assertSucceeds(write(auth("synthetic-user"), "synthetic-user", "ios")); passed++;
  await assertSucceeds(write(auth("synthetic-user"), "synthetic-user", "android")); passed++;
  await assertFails(write(auth("synthetic-user", false), "synthetic-user", "ios")); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-owner", "ios")); passed++;
  await assertFails(write(auth("synthetic-owner"), "synthetic-owner", "ios")); passed++;
  await assertSucceeds(write(auth("synthetic-owner", true, true), "synthetic-owner", "ios")); passed++;
  await assertFails(getDoc(doc(auth("synthetic-legacy"), "news/synthetic-private"))); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-user", "unknown")); passed++;
  await assertFails(write(auth("synthetic-user", false), "synthetic-user", "android")); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-owner", "android")); passed++;
  await assertFails(write(auth("synthetic-owner"), "synthetic-owner", "android")); passed++;
  await assertSucceeds(write(auth("synthetic-owner", true, true), "synthetic-owner", "android")); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-user", "android", {token: "x".repeat(4097)})); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-user", "android", {token: ""})); passed++;
  await assertFails(write(auth("synthetic-user"), "synthetic-user", "android", {registrationType: "unknown"})); passed++;
  console.log("PASS: " + passed + " local Rules contract assertions; iOS/Android registration with unchanged security gates.");
  console.log("Synthetic fixture ready for AVD; cloud and production untouched.");
  await checkContentFixtures(env);
} finally {
  await env.cleanup();
}
