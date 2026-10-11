import {db} from "../firebase/admin";

const version = "2026.13";

/** Give emulator users a current legal state for tests of unrelated callables. */
export async function seedCurrentLegalForIntegration(...userIds: string[]): Promise<void> {
  await Promise.all(["terms", "privacy"].map((type) =>
    db.doc(`legalDocuments/${type}`).set({activeVersion: version}, {merge: true})
  ));
  await Promise.all(userIds.map((uid) => db.doc(`users/${uid}`).set({
    acceptedTermsVersion: version,
    acceptedPrivacyVersion: version,
  }, {merge: true})));
}
