import {FieldValue, type DocumentData, type Query} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuth} from "../auth/context";
import {adminAuth, adminStorage, db} from "../firebase/admin";
import {
  accountDeletionReferencePolicies,
  deletedUserDisplayName,
  deletedUserID,
  personalReferenceValues,
  redactPersonalReferences,
  type AccountDeletionPatch,
  type AccountDeletionReferencePolicy,
} from "./accountDeletionPolicy";

interface AccountDeletionResponse {
  status: "deleted";
  completedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  timeoutSeconds: 300,
  memory: "512MiB" as const,
  maxInstances: 10,
};

const recentAuthenticationWindowSeconds = 5 * 60;
const deletionBatchSize = 400;
const feedbackDeletionBatchSize = 100;

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

async function deleteQuery(query: Query<DocumentData>): Promise<void> {
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

async function deleteFeedback(uid: string): Promise<void> {
  while (true) {
    const snapshot = await db.collection("feedback")
      .where("userId", "==", uid)
      .limit(feedbackDeletionBatchSize)
      .get();
    if (snapshot.empty) {
      return;
    }

    await Promise.all(snapshot.docs.map(async (document) => {
      if (document.get("dsaCase")) {
        await document.ref.update({
          userId: deletedUserID,
          userDisplayName: deletedUserDisplayName,
          unreadForUser: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else {
        await db.recursiveDelete(document.ref);
      }
    }));

    if (snapshot.size < feedbackDeletionBatchSize) {
      return;
    }
  }
}

async function markDeletionInProgress(uid: string): Promise<void> {
  await db.collection("users").doc(uid).set({
    accountStatus: "deactivated",
    blockState: "deactivated",
    isBlocked: true,
    globalRole: "user",
    communityMemberships: [],
    deletionState: "inProgress",
    deletionStartedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function applyReferencePolicy(
  policy: AccountDeletionReferencePolicy,
  uid: string,
  personalReferences: readonly string[]
): Promise<void> {
  const rootQuery = policy.scope === "collection" ?
    db.collection(policy.collection) :
    db.collectionGroup(policy.collection);
  let query: Query<DocumentData> = rootQuery.where(policy.field, policy.operator, uid);

  for (const filter of policy.filters ?? []) {
    query = query.where(filter.field, filter.operator, filter.value);
  }

  while (true) {
    const snapshot = await query.limit(deletionBatchSize).get();
    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    for (const document of snapshot.docs) {
      switch (policy.action) {
        case "delete":
          batch.delete(document.ref);
          break;
        case "removeArrayValue":
          batch.update(document.ref, {
            [policy.field]: FieldValue.arrayRemove(uid),
            updatedAt: FieldValue.serverTimestamp(),
          });
          break;
        case "anonymize":
          if (policy.patch === undefined) {
            throw new Error(`Missing anonymization patch for ${policy.name}.`);
          }
          batch.update(
            document.ref,
            referenceAnonymizationUpdate(
              policy.patch,
              document.data(),
              personalReferences
            )
          );
          break;
      }
    }
    await batch.commit();

    if (snapshot.size < deletionBatchSize) {
      return;
    }
  }
}

function referenceAnonymizationUpdate(
  patch: AccountDeletionPatch,
  data: DocumentData,
  personalReferences: readonly string[]
): DocumentData {
  const updatedAt = FieldValue.serverTimestamp();

  switch (patch) {
    case "contentAuthor":
      return {
        authorId: deletedUserID,
        authorName: deletedUserDisplayName,
        updatedAt,
      };
    case "commentAuthor":
      return {
        authorId: deletedUserID,
        authorName: deletedUserDisplayName,
        authorPhotoURL: FieldValue.delete(),
        updatedAt,
      };
    case "organizationSubmitter":
      return {
        submittedByUserId: deletedUserID,
        submittedByDisplayName: deletedUserDisplayName,
        updatedAt,
      };
    case "organizationReviewer":
      return {
        reviewedByUserId: deletedUserID,
        updatedAt,
      };
    case "organizationPhotoUploader":
      return {
        uploadedBy: deletedUserID,
        updatedAt,
      };
    case "feedbackMessageAuthor":
      return {
        senderId: deletedUserID,
        senderDisplayName: deletedUserDisplayName,
      };
    case "dsaReporter":
      return retainedLogUpdate(data, personalReferences, {
        reporterUserId: deletedUserID,
        reporterName: deletedUserDisplayName,
        reporterEmail: FieldValue.delete(),
      });
    case "dsaTargetAuthor":
      return retainedLogUpdate(data, personalReferences, {
        targetAuthorId: deletedUserID,
      });
    case "legalAcceptance":
      return {
        userId: deletedUserID,
      };
    case "auditTarget":
      return retainedLogUpdate(data, personalReferences, {
        targetUserId: deletedUserID,
      });
    case "auditActor":
      return retainedLogUpdate(data, personalReferences, {
        performedBy: deletedUserID,
      });
    case "systemLogActor":
      return retainedLogUpdate(data, personalReferences, {
        actorUserId: deletedUserID,
        actorDisplayName: deletedUserDisplayName,
      });
    case "systemLogReviewer":
      return retainedLogUpdate(data, personalReferences, {
        reviewedByUserId: deletedUserID,
      });
    case "systemLogTarget":
      return retainedLogUpdate(data, personalReferences, {
        targetId: deletedUserID,
        targetTitle: deletedUserDisplayName,
      });
  }
}

function retainedLogUpdate(
  data: DocumentData,
  personalReferences: readonly string[],
  directUpdate: DocumentData
): DocumentData {
  const update = {...directUpdate};
  const redactableFields = [
    "metadata",
    "newValue",
    "note",
    "previousValue",
    "reason",
    "summary",
    "technicalMessage",
  ];

  for (const field of redactableFields) {
    if (data[field] !== undefined) {
      update[field] = redactPersonalReferences(data[field], personalReferences);
    }
  }

  return update;
}

async function deleteProfileImages(uid: string): Promise<void> {
  await adminStorage.bucket().deleteFiles({
    prefix: `profileImages/${uid}/`,
    force: true,
  });
}

async function deleteOwnedPrivateData(uid: string): Promise<void> {
  await Promise.all([
    deleteQuery(db.collection("likes").where("userId", "==", uid)),
    deleteQuery(db.collection("registrations").where("userId", "==", uid)),
    deleteFeedback(uid),
  ]);
}

async function deleteUserRoot(uid: string): Promise<void> {
  await db.recursiveDelete(db.collection("users").doc(uid));
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

    const personalReferences = personalReferenceValues(auth.uid, userSnapshot.data());
    await markDeletionInProgress(auth.uid);
    // Remove feedback owned by this user before scanning feedback messages.
    // Otherwise a recursive delete can race an anonymizing update in the same batch.
    await deleteOwnedPrivateData(auth.uid);

    await Promise.all([
      deleteProfileImages(auth.uid),
      db.collection("publicProfiles").doc(auth.uid).delete(),
      ...accountDeletionReferencePolicies.map((policy) =>
        applyReferencePolicy(policy, auth.uid, personalReferences)
      ),
    ]);

    await deleteUserRoot(auth.uid);
    await adminAuth.deleteUser(auth.uid);

    return {
      status: "deleted",
      completedAt: new Date().toISOString(),
    };
  }
);
