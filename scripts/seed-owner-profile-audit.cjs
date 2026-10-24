// Disposable fixtures for ProfileEditingSDKTests; fixed localhost demo only.
const {createRequire} = require("node:module");
const localRequire = createRequire(require("node:path").join(__dirname, "../functions/package.json"));
const expected = {
  GCLOUD_PROJECT: "demo-uac-release-audit",
  FIRESTORE_EMULATOR_HOST: "127.0.0.1:28080",
  FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:19099",
};
for (const [key, value] of Object.entries(expected)) {
  if (process.env[key] && process.env[key] !== value) throw new Error(`Refusing conflicting ${key}`);
  process.env[key] = value;
}
const {initializeApp} = localRequire("firebase-admin/app");
const {getFirestore, Timestamp} = localRequire("firebase-admin/firestore");
const {getAuth} = localRequire("firebase-admin/auth");
initializeApp({projectId: expected.GCLOUD_PROJECT});
(async () => {
  const db = getFirestore(), auth = getAuth();
  for (const type of ["terms", "privacy"]) {
    const legal = {documentType: type, version: "2026.13", activeVersion: "2026.13",
      versionNumber: 202613, status: "published", requiresAcceptance: true, contentHash: "a".repeat(64)};
    await db.doc(`legalDocuments/${type}`).set(legal);
    await db.doc(`legalDocuments/${type}/versions/2026.13`).set(legal);
  }
  for (const role of ["owner", "member"]) {
    const uid = `profile-sdk-${role}`, email = `profile-${role}@uac.test`;
    try { await auth.deleteUser(uid); } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;
    }
    await auth.createUser({uid, email, password: "Emulator-Only-2026!", emailVerified: true});
    await db.doc(`users/${uid}`).set({
      id: uid, fullName: "Profile Fixture", displayName: "Profile Fixture",
      email, city: "Wien", bio: "", selectedFederalState: "wien",
      globalRole: role === "owner" ? "owner" : "user", accountStatus: "active", blockState: "active",
      requiresMultiFactorAuth: false, acceptedTermsVersion: "2026.13", acceptedPrivacyVersion: "2026.13",
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
    });
  }
  const batch = db.batch();
  for (let i = 0; i < 250; i++) {
    batch.set(db.doc(`feedback/profile-count-${i}`), {
      id: `profile-count-${i}`, userId: "profile-sdk-member", message: "Local fixture",
      unreadForOwner: i < 137, unreadForUser: false, status: "open", type: "question",
      createdAt: Timestamp.fromMillis(1000 + i), updatedAt: Timestamp.fromMillis(1000 + i),
    });
  }
  await batch.commit();
  console.log("Local owner profile fixtures and 250 feedback records ready.");
})().catch(error => { console.error(error.message); process.exitCode = 1; });
