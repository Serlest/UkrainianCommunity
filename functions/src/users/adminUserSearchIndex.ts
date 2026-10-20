import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "../firebase/admin";
import {adminSearchControlPath, adminSearchFields, adminSearchIndexField, buildAdminSearchGrams} from "./adminUserSearch";

/** Avoid a second transaction for our own write and for unrelated status/presence changes. */
export function searchSourceChanged(before?: DocumentData, after?: DocumentData): boolean {
  if (!before || !after) return true;
  return adminSearchFields.some(field => before[field] !== after[field])
    || JSON.stringify(before[adminSearchIndexField]) !== JSON.stringify(after[adminSearchIndexField]);
}

/** Read the current document, never the event's possibly delayed/out-of-order snapshot.
 * Updating only the derived field preserves legacy app writes, moderation and timestamps.
 * A concurrent rename/delete conflicts and retries; a deleted user is never recreated.
 */
export async function reconcileAdminSearchUser(firestore: Firestore, userId: string): Promise<boolean> {
  const reference = firestore.collection("users").doc(userId);
  return firestore.runTransaction(async transaction => {
    const current = await transaction.get(reference);
    if (!current.exists) return false;
    const grams = buildAdminSearchGrams(userId, current.data()!);
    if (JSON.stringify(current.get(adminSearchIndexField)) === JSON.stringify(grams)) return false;
    transaction.update(reference, {[adminSearchIndexField]: grams});
    return true;
  });
}

export const maintainAdminUserSearchIndex = onDocumentWritten({
  document: "users/{userId}", region: "europe-west3", maxInstances: 10,
  retry: true,
}, async event => {
  if (!event.data || !searchSourceChanged(event.data.before.data(), event.data.after.data())) return;
  // Own index-only event: validate its after image without another database read.
  const after = event.data.after.data();
  const before = event.data.before.data();
  if (after && before && adminSearchFields.every(field => before[field] === after[field])
    && JSON.stringify(after[adminSearchIndexField]) === JSON.stringify(buildAdminSearchGrams(event.params.userId, after))) return;
  try {
    await reconcileAdminSearchUser(db, event.params.userId);
  } catch (error) {
    // A persistent writer failure must not silently leave production search incomplete.
    // Recovery is explicit: repair/verify/backfill before enabling indexed reads again.
    await db.doc(adminSearchControlPath).set({ready: false, version: 1,
      disabledReason: "index-maintenance-failed", disabledAt: FieldValue.serverTimestamp()}, {merge: true});
    throw error; // Eventarc retries; never acknowledge a failed update.
  }
});
