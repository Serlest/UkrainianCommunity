import {Timestamp, type DocumentData, type Firestore, type QueryDocumentSnapshot} from "firebase-admin/firestore";

const disposableChildCollection = "notificationInbox";

async function initialRegistrationLogs(
  db: Firestore, uid: string, profile: DocumentData | undefined
): Promise<QueryDocumentSnapshot[] | null> {
  const snapshot = await db.collection("legalAcceptanceLogs")
    .where("userId", "==", uid).limit(3).get();
  if (snapshot.empty) return [];
  if (!profile || snapshot.size !== 2 || !(profile.createdAt instanceof Timestamp)) return null;

  const versions = [
    {type: "terms", version: profile.acceptedTermsVersion},
    {type: "privacy", version: profile.acceptedPrivacyVersion},
  ];
  if (versions.some(({version}) => typeof version !== "string" || !version)) return null;
  for (const {type, version} of versions) {
    const log = snapshot.docs.find((document) => document.id === `${uid}_${type}_${version}`);
    const acceptedAt = log?.get("acceptedAt");
    if (!log || log.get("userId") !== uid || log.get("documentType") !== type
        || log.get("version") !== version || !(acceptedAt instanceof Timestamp)
        || Math.abs(acceptedAt.toMillis() - profile.createdAt.toMillis()) > 60_000) return null;
  }
  return snapshot.docs;
}

/** An inbox can be produced by server broadcasts before email verification. */
export async function hasDisqualifyingPrivateData(
  db: Firestore, uid: string, profile: DocumentData | undefined
): Promise<boolean> {
  const children = await db.collection("users").doc(uid).listCollections();
  if (children.some((collection) => collection.id !== disposableChildCollection)) return true;
  return (await initialRegistrationLogs(db, uid, profile)) === null;
}

export async function deleteInitialRegistrationLogs(
  db: Firestore, uid: string, profile: DocumentData | undefined
): Promise<void> {
  const logs = await initialRegistrationLogs(db, uid, profile);
  if (logs === null) throw new Error("Registration legal logs changed during account cleanup");
  if (logs.length === 0) return;
  const batch = db.batch();
  for (const log of logs) batch.delete(log.ref);
  await batch.commit();
}

/** Called only after the unchanged root was deleted transactionally. */
export async function deleteDisposablePrivateData(db: Firestore, uid: string): Promise<boolean> {
  const root = db.collection("users").doc(uid);
  if ((await root.get()).exists) return false;
  const children = await root.listCollections();
  if (children.some((collection) => collection.id !== disposableChildCollection)) return false;
  if (children.length > 0) await db.recursiveDelete(root.collection(disposableChildCollection));
  return !(await root.get()).exists && (await root.listCollections()).length === 0;
}
