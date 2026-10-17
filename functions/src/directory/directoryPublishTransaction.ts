import {FieldValue, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {recordDirectoryAdditions} from "./directoryRecent";
import {validateDirectoryCategoryPayload} from "./directoryValidation";

export interface DirectoryPublishInput {
  categoryId: string;
  payload: string;
  expectedRevision: number;
  updatedBy: string;
  validatePrevious?: (previousPayload: string, currentRevision: number) => void;
}

/** Shared atomic publication path for editor and restricted automation. */
export async function publishDirectoryCategoryInTransaction(
  transaction: Transaction, input: DirectoryPublishInput
): Promise<{categoryId: string; revision: number}> {
  validateDirectoryCategoryPayload(input.payload, input.categoryId);
  const reference = db.collection("directoryCategories").doc(input.categoryId);
  const previous = await transaction.get(reference);
  if (previous.data()?.isDeleted === true) {
    throw new HttpsError("failed-precondition", "Deleted category cannot be republished.");
  }
  const currentRevision = previous.data()?.revision ?? 0;
  if (currentRevision !== input.expectedRevision) {
    throw new HttpsError("aborted", "Category changed on another device.");
  }
  if (input.validatePrevious) {
    if (typeof previous.data()?.payload !== "string") {
      throw new HttpsError("failed-precondition", "Published category is missing.");
    }
    input.validatePrevious(previous.data()!.payload, currentRevision);
  }
  const nextRevision = currentRevision + 1;
  await recordDirectoryAdditions(transaction, input.categoryId,
    previous.data()?.payload, input.payload, nextRevision);
  const published = {
    id: input.categoryId,
    payload: input.payload,
    revision: nextRevision,
    updatedBy: input.updatedBy,
    updatedAt: FieldValue.serverTimestamp(),
  };
  transaction.set(reference, published);
  transaction.create(reference.collection("versions").doc(String(nextRevision)),
    {...published, previousRevision: currentRevision});
  return {categoryId: input.categoryId, revision: nextRevision};
}
