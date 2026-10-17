import {FieldValue, type Transaction} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {
  assertActiveUser, assertPrivilegedMFA, requireVerifiedActiveUser, type AuthContext,
} from "../auth/context";
import {db} from "../firebase/admin";
import {isAppOwner, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {validateDirectoryCategoryPayload} from "./directoryValidation";
import {publishDirectoryCategoryInTransaction} from "./directoryPublishTransaction";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  enforceAppCheck: false,
};

async function assertDirectoryEditor(transaction: Transaction, actor: AuthContext): Promise<void> {
  // Keep the account and grant reads inside the write transaction so revocations win races.
  const user = await transaction.get(db.collection("users").doc(actor.uid));
  if (!user.exists) {
    throw new HttpsError("permission-denied", "User profile does not exist.");
  }
  const permissions = userPermissionSnapshotFromData(actor.uid, user.data());
  assertActiveUser(permissions);
  assertPrivilegedMFA(actor.token, permissions);
  if (!isAppOwner(permissions)) {
    const editor = await transaction.get(db.collection("directoryEditors").doc(actor.uid));
    if (editor.data()?.enabled !== true) {
      throw new HttpsError("permission-denied", "Directory editor access is required.");
    }
  }
}

export const saveDirectoryCategory = onCall(callableOptions, async (request) => {
  const actor = await requireVerifiedActiveUser(request);
  const input = request.data;
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.categoryId !== "string" ||
      typeof input.payload !== "string" ||
      !Number.isInteger(input.expectedRevision) ||
      input.expectedRevision < 0) {
    throw new HttpsError("invalid-argument", "Invalid category save request.");
  }
  validateDirectoryCategoryPayload(input.payload, input.categoryId);

  const result = await db.runTransaction(async (transaction) => {
    await assertDirectoryEditor(transaction, actor);
    return publishDirectoryCategoryInTransaction(transaction, {
      categoryId: input.categoryId, payload: input.payload,
      expectedRevision: input.expectedRevision, updatedBy: actor.uid,
    });
  });
  return result;
});

export const deleteDirectoryCategory = onCall(callableOptions, async (request) => {
  const actor = await requireVerifiedActiveUser(request);
  const input = request.data;
  if (!input || typeof input !== "object" || Array.isArray(input) ||
      typeof input.categoryId !== "string" ||
      !/^custom-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(
        input.categoryId) ||
      !Number.isInteger(input.expectedRevision) || input.expectedRevision < 1) {
    throw new HttpsError("invalid-argument", "Invalid category deletion request.");
  }

  const reference = db.collection("directoryCategories").doc(input.categoryId);
  const nextRevision = input.expectedRevision + 1;
  await db.runTransaction(async (transaction) => {
    await assertDirectoryEditor(transaction, actor);
    const previous = await transaction.get(reference);
    if (!previous.exists || previous.data()?.isDeleted === true ||
        previous.data()?.revision !== input.expectedRevision) {
      throw new HttpsError("aborted", "Category changed on another device.");
    }
    const deletion = {
      isDeleted: true,
      revision: nextRevision,
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.update(reference, {...deletion, payload: FieldValue.delete()});
    transaction.create(reference.collection("versions").doc(String(nextRevision)),
      {...deletion, previousRevision: input.expectedRevision, action: "deleted"});
  });
  return {categoryId: input.categoryId, revision: nextRevision};
});
