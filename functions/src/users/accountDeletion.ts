import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type DocumentData, type Query} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuth} from "../auth/context";
import {adminAuth, adminStorage, db} from "../firebase/admin";
import {
  accountDeletionReferencePolicies,
  deletedUserDisplayName,
  deletedUserID,
  personalReferenceValues,
  isPlainRecord,
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
  enforceAppCheck: false,
};

const recentAuthenticationWindowSeconds = 5 * 60;
const deletionBatchSize = 400;
const feedbackDeletionBatchSize = 100;
export const accountDeletionOperationCollection = "accountDeletionOperations";
export const accountDeletionOperationRetentionDays = 7;

type AccountDeletionOperationStage =
  | "started"
  | "privateData"
  | "references"
  | "userRoot"
  | "authIdentity"
  | "completed";

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
      const canonicalDsaCase = await db.collection("dsaCases").doc(document.id).get();
      if (document.get("dsaCase") || canonicalDsaCase.exists) {
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
  await db.collection("users").doc(uid).update({
    accountStatus: "deactivated",
    blockState: "deactivated",
    isBlocked: true,
    globalRole: "user",
    communityMemberships: [],
    deletionState: "inProgress",
    deletionStartedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
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
    case "feedbackReplyActor":
      return retainedLogUpdate(data, personalReferences, {
        repliedByUserId: deletedUserID,
      });
    case "feedbackLastMessageActor":
      return retainedLogUpdate(data, personalReferences, {
        lastMessageByUserId: deletedUserID,
      });
    case "dsaReporter":
      return retainedLogUpdate(data, personalReferences, {
        reporterUserId: deletedUserID,
        reporterName: deletedUserDisplayName,
        reporterEmail: FieldValue.delete(),
      });
    case "dsaDecisionActor": {
      const decision = redactPersonalReferences(data.decision, personalReferences);
      return {
        decision: isPlainRecord(decision) ? {
          ...decision,
          decidedByUserId: deletedUserID,
        } : decision,
        updatedAt,
      };
    }
    case "dsaAppealDecisionActor":
      return nestedDecisionActorUpdate("appeal", data, personalReferences, updatedAt);
    case "dsaPreviousDecisionActor":
      return nestedDecisionActorUpdate("previousDecision", data, personalReferences, updatedAt);
    case "dsaPreviousAppealDecisionActor":
      return nestedDecisionActorUpdate("previousAppeal", data, personalReferences, updatedAt);
    case "feedbackDsaDecisionActor": {
      const dsaCase = redactPersonalReferences(data.dsaCase, personalReferences);
      if (!isPlainRecord(dsaCase)) return {updatedAt};
      const decision = dsaCase.decision;
      return {
        dsaCase: {
          ...dsaCase,
          ...(isPlainRecord(decision) ? {
            decision: {...decision, decidedByUserId: deletedUserID},
          } : {}),
        },
        updatedAt,
      };
    }
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
    case "cancellationActor":
      return {actorUserId: deletedUserID};
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
    case "userStatusUpdater":
      return {
        statusUpdatedBy: deletedUserID,
        updatedAt,
      };
  }
}

function nestedDecisionActorUpdate(
  field: "appeal" | "previousAppeal" | "previousDecision",
  data: DocumentData,
  personalReferences: readonly string[],
  updatedAt: FirebaseFirestore.FieldValue
): DocumentData {
  const value = redactPersonalReferences(data[field], personalReferences);
  return {
    [field]: isPlainRecord(value) ? {
      ...value,
      decidedByUserId: deletedUserID,
    } : value,
    updatedAt,
  };
}

function retainedLogUpdate(
  data: DocumentData,
  personalReferences: readonly string[],
  directUpdate: DocumentData
): DocumentData {
  const update = {...directUpdate};
  const redactableFields = [
    "lastMessageText",
    "metadata",
    "newValue",
    "note",
    "ownerReply",
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

function deletionOperationReference(uid: string): FirebaseFirestore.DocumentReference {
  const operationID = createHash("sha256")
    .update(`account-deletion:${uid}`, "utf8")
    .digest("hex");
  return db.collection(accountDeletionOperationCollection).doc(operationID);
}

function operationExpiry(): Timestamp {
  return Timestamp.fromMillis(
    Date.now() + accountDeletionOperationRetentionDays * 24 * 60 * 60 * 1_000
  );
}

async function recordDeletionStage(
  operation: FirebaseFirestore.DocumentReference,
  stage: AccountDeletionOperationStage,
  status: "inProgress" | "partial" | "completed",
  extra: DocumentData = {}
): Promise<void> {
  await operation.set({
    stage,
    status,
    updatedAt: FieldValue.serverTimestamp(),
    expiresAt: operationExpiry(),
    ...extra,
  }, {merge: true});
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
    db.collection("analyticsConsentStates").doc(uid).delete(),
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
    const operationReference = deletionOperationReference(auth.uid);
    const [userSnapshot, ownedOrganizationSnapshot, operationSnapshot] = await Promise.all([
      userReference.get(),
      db.collection("organizations")
        .where("ownerId", "==", auth.uid)
        .limit(1)
        .get(),
      operationReference.get(),
    ]);

    // Keep the deployed v1 authentication contract: recent sign-in is
    // required above. MFA activation is a separate rollout, not a side effect
    // of extending receipt cleanup (verified against deployed source 2e7ae13).


    if (operationSnapshot.get("status") === "completed") {
      const completedAt = operationSnapshot.get("completedAt");
      return {
        status: "deleted",
        completedAt: completedAt instanceof Timestamp ?
          completedAt.toDate().toISOString() : new Date().toISOString(),
      };
    }

    const isResuming = operationSnapshot.exists;
    if (!userSnapshot.exists && !isResuming) {
      throw new HttpsError("failed-precondition", "Account deletion was not started for this identity.");
    }

    if (!isResuming && stringField(userSnapshot.data(), "globalRole") === "owner") {
      throw new HttpsError(
        "permission-denied",
        "Platform owner account cannot be deleted from the app."
      );
    }
    if (!isResuming && !ownedOrganizationSnapshot.empty) {
      throw new HttpsError(
        "failed-precondition",
        "Organization ownership must be transferred before account deletion."
      );
    }

    const personalReferences = personalReferenceValues(auth.uid, userSnapshot.data());

    if (!operationSnapshot.exists) {
      await operationReference.set({
        status: "inProgress",
        stage: "started",
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        expiresAt: operationExpiry(),
      }, {merge: true});
    } else {
      await recordDeletionStage(operationReference, "started", "inProgress");
    }

    const runStage = async (
      stage: AccountDeletionOperationStage,
      work: () => Promise<void>
    ): Promise<void> => {
      await recordDeletionStage(operationReference, stage, "inProgress", {
        lastError: FieldValue.delete(),
      });
      try {
        await work();
      } catch (error) {
        const errorCode = (error as {code?: unknown})?.code;
        try {
          await recordDeletionStage(operationReference, stage, "partial", {
            lastError: typeof errorCode === "string" ? errorCode : "unknown",
          });
        } catch (journalError) {
          console.error("Failed to record partial account deletion state.", journalError);
        }
        throw error;
      }
    };

    await runStage("privateData", async () => {
      if (userSnapshot.exists) await markDeletionInProgress(auth.uid);
      // Remove feedback owned by this user before scanning feedback messages.
      // Otherwise a recursive delete can race an anonymizing update in the same batch.
      await deleteOwnedPrivateData(auth.uid);
    });

    await runStage("references", async () => {
      await Promise.all([
        deleteProfileImages(auth.uid),
        db.collection("publicProfiles").doc(auth.uid).delete(),
        ...accountDeletionReferencePolicies.map((policy) =>
          applyReferencePolicy(policy, auth.uid, personalReferences)
        ),
      ]);
    });

    await runStage("userRoot", () => deleteUserRoot(auth.uid));
    await runStage("authIdentity", async () => {
      try {
        await adminAuth.deleteUser(auth.uid);
      } catch (error) {
        if ((error as {code?: unknown})?.code !== "auth/user-not-found") throw error;
      }
    });

    const completedAt = new Date();
    try {
      await recordDeletionStage(operationReference, "completed", "completed", {
        completedAt: Timestamp.fromDate(completedAt),
        lastError: FieldValue.delete(),
      });
    } catch (error) {
      // Auth is already gone. Do not turn a completed destructive operation
      // into a client-visible failure that invites an impossible retry.
      console.error("Failed to finalize the account deletion operation receipt.", error);
    }

    return {
      status: "deleted",
      completedAt: completedAt.toISOString(),
    };
  }
);
