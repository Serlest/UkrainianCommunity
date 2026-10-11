import {FieldValue} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {isAppOwner} from "../permissions/userPermissions";
import {validateDirectoryCategoryPayload} from "./directoryValidation";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  enforceAppCheck: false,
};

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

  const reference = db.collection("directoryCategories").doc(input.categoryId);
  const nextRevision = input.expectedRevision + 1;
  await db.runTransaction(async (transaction) => {
    // Keep the grant check in the same transaction as publication, so a
    // concurrent revocation cannot be bypassed with an in-flight save.
    if (!isAppOwner(actor.permissions)) {
      const editor = await transaction.get(db.collection("directoryEditors").doc(actor.uid));
      if (editor.data()?.enabled !== true) {
        throw new HttpsError("permission-denied", "Directory editor access is required.");
      }
    }
    const previous = await transaction.get(reference);
    const currentRevision = previous.data()?.revision ?? 0;
    if (currentRevision !== input.expectedRevision) {
      throw new HttpsError("aborted", "Category changed on another device.");
    }
    const published = {
      id: input.categoryId,
      payload: input.payload,
      revision: nextRevision,
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.set(reference, published);
    transaction.create(
      reference.collection("versions").doc(String(nextRevision)),
      {...published, previousRevision: currentRevision}
    );
  });

  return {categoryId: input.categoryId, revision: nextRevision};
});
