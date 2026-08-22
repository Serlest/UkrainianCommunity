import {FieldValue, type DocumentData, type Query} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuth} from "../auth/context";
import {adminAuth, adminStorage, db} from "../firebase/admin";

interface AccountDeletionResponse {
  status: "deleted";
  completedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  timeoutSeconds: 120,
  maxInstances: 10,
};

const recentAuthenticationWindowSeconds = 5 * 60;
const deletionBatchSize = 400;
const deletedUserDisplayName = "Видалений користувач";

function stringField(data: DocumentData | undefined, field: string): string | undefined {
  const value = data?.[field];
  return typeof value === "string" ? value : undefined;
}

function assertRecentlyAuthenticated(token: Record<string, unknown>): void {
  const authTime = token.auth_time;
  if (typeof authTime !== "number") {
    throw new HttpsError("unauthenticated", "Recent authentication is required.");
  }

  const authenticationAge = Math.floor(Date.now() / 1000) - authTime;
  if (authenticationAge < 0 || authenticationAge > recentAuthenticationWindowSeconds) {
    throw new HttpsError("unauthenticated", "Recent authentication is required.");
  }
}

async function deleteQuery(query: Query): Promise<void> {
  while (true) {
    const snapshot = await query.limit(deletionBatchSize).get();
    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((document) => batch.delete(document.ref));
    await batch.commit();

    if (snapshot.size < deletionBatchSize) {
      return;
    }
  }
}

async function deleteUserSubcollections(uid: string): Promise<void> {
  const collections = await db.collection("users").doc(uid).listCollections();
  for (const collection of collections) {
    await db.recursiveDelete(collection);
  }
}

async function deleteFeedback(uid: string): Promise<void> {
  while (true) {
    const snapshot = await db.collection("feedback")
      .where("userId", "==", uid)
      .limit(100)
      .get();
    if (snapshot.empty) {
      return;
    }

    for (const document of snapshot.docs) {
      await db.recursiveDelete(document.ref);
    }

    if (snapshot.size < 100) {
      return;
    }
  }
}

async function anonymizeComments(uid: string): Promise<void> {
  while (true) {
    const snapshot = await db.collectionGroup("comments")
      .where("authorId", "==", uid)
      .limit(deletionBatchSize)
      .get();
    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((document) => batch.update(document.ref, {
      authorId: "deleted",
      authorName: deletedUserDisplayName,
      updatedAt: FieldValue.serverTimestamp(),
    }));
    await batch.commit();

    if (snapshot.size < deletionBatchSize) {
      return;
    }
  }
}

async function deleteAvatar(uid: string): Promise<void> {
  const avatar = adminStorage.bucket().file(`profileImages/${uid}/avatar.jpg`);
  await avatar.delete({ignoreNotFound: true});
}

async function anonymizeUserDocument(uid: string): Promise<void> {
  await db.collection("users").doc(uid).set({
    id: uid,
    accountStatus: "deactivated",
    blockState: "deactivated",
    isBlocked: true,
    globalRole: "user",
    canManageGuide: false,
    communityMemberships: [],
    displayName: deletedUserDisplayName,
    fullName: "",
    bio: "",
    city: "",
    email: "",
    telegramUsername: FieldValue.delete(),
    avatarURL: FieldValue.delete(),
    selectedFederalState: FieldValue.delete(),
    acceptedTermsAt: FieldValue.delete(),
    acceptedPrivacyAt: FieldValue.delete(),
    acceptedTermsVersion: FieldValue.delete(),
    acceptedPrivacyVersion: FieldValue.delete(),
    termsVersion: FieldValue.delete(),
    privacyVersion: FieldValue.delete(),
    deletionCompletedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

export const deleteOwnAccount = onCall(
  callableOptions,
  async (request): Promise<AccountDeletionResponse> => {
    const auth = requireAuth(request);
    assertRecentlyAuthenticated(auth.token as Record<string, unknown>);

    const userReference = db.collection("users").doc(auth.uid);
    const [userSnapshot, ownedOrganizationSnapshot] = await Promise.all([
      userReference.get(),
      db.collection("organizations")
        .where("ownerId", "==", auth.uid)
        .limit(1)
        .get(),
    ]);

    if (stringField(userSnapshot.data(), "globalRole") === "owner") {
      throw new HttpsError(
        "permission-denied",
        "Platform owner account cannot be deleted from the app."
      );
    }
    if (!ownedOrganizationSnapshot.empty) {
      throw new HttpsError(
        "failed-precondition",
        "Organization ownership must be transferred before account deletion."
      );
    }

    await deleteUserSubcollections(auth.uid);
    await deleteQuery(db.collection("likes").where("userId", "==", auth.uid));
    await deleteQuery(db.collection("registrations").where("userId", "==", auth.uid));
    await deleteFeedback(auth.uid);
    await anonymizeComments(auth.uid);
    await deleteAvatar(auth.uid);
    await db.collection("publicProfiles").doc(auth.uid).delete();
    await anonymizeUserDocument(auth.uid);
    await adminAuth.deleteUser(auth.uid);

    return {
      status: "deleted",
      completedAt: new Date().toISOString(),
    };
  }
);
