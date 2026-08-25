import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";

const callableOptions = {
  region: "europe-west3",
  maxInstances: 4,
  timeoutSeconds: 300,
  invoker: "public" as const,
};

const feedbackBatchSize = 200;
const maximumDeletedFeedback = 10_000;

export const clearMyFeedback = onCall(
  callableOptions,
  async (request): Promise<{deletedCount: number}> => {
    if (!isEmptyRequest(request.data)) {
      throw new HttpsError("invalid-argument", "Request payload must be empty.");
    }

    const actor = await requireVerifiedActiveUser(request);
    const deletedFeedbackIds: string[] = [];

    while (deletedFeedbackIds.length < maximumDeletedFeedback) {
      const feedbackSnapshot = await db.collection("feedback")
        .where("userId", "==", actor.uid)
        .limit(feedbackBatchSize)
        .get();

      if (feedbackSnapshot.empty) break;

      const writer = db.bulkWriter();
      for (const feedbackDocument of feedbackSnapshot.docs) {
        const messagesSnapshot = await feedbackDocument.ref.collection("messages").get();
        for (const messageDocument of messagesSnapshot.docs) {
          writer.delete(messageDocument.ref);
        }
        writer.delete(feedbackDocument.ref);
        deletedFeedbackIds.push(feedbackDocument.id);
      }
      await writer.close();
    }

    if (deletedFeedbackIds.length >= maximumDeletedFeedback) {
      const remaining = await db.collection("feedback")
        .where("userId", "==", actor.uid)
        .limit(1)
        .get();
      if (!remaining.empty) {
        throw new HttpsError(
          "resource-exhausted",
          "Too many feedback records. Run the operation again to continue."
        );
      }
    }

    await deleteFeedbackNotifications(deletedFeedbackIds);
    return {deletedCount: deletedFeedbackIds.length};
  }
);

async function deleteFeedbackNotifications(feedbackIds: string[]): Promise<void> {
  for (let index = 0; index < feedbackIds.length; index += 10) {
    const idBatch = feedbackIds.slice(index, index + 10);
    const notificationSnapshot = await db.collectionGroup("notificationInbox")
      .where("sourceId", "in", idBatch)
      .get();

    if (notificationSnapshot.empty) continue;
    const writer = db.bulkWriter();
    for (const notificationDocument of notificationSnapshot.docs) {
      if (notificationDocument.get("sourceType") === "feedback") {
        writer.delete(notificationDocument.ref);
      }
    }
    await writer.close();
  }
}

function isEmptyRequest(value: unknown): boolean {
  return value === undefined
    || value === null
    || (typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0);
}
