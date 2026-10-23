import {FieldPath, FieldValue} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "../firebase/admin";
import {resolveNotificationRecipients, writeUserNotification} from "../notifications/notificationPayloads";

export async function queueLegalPublication(type: string, data: Record<string, unknown>): Promise<void> {
  const version = data.activeVersion;
  if (!["terms", "privacy", "organizationRules"].includes(type) || typeof version !== "string" || !/^[0-9]{4}\.[1-9][0-9]?$/.test(version)) return;
  const ref = db.doc(`legalPublicationDelivery/${type}_${version}`);
  await db.runTransaction(async tx => {
    if ((await tx.get(ref)).exists) return;
    tx.create(ref, {type, version, cursor: null, sequence: 0, complete: false,
      changeSummary: typeof data.changeSummary === "string" ? data.changeSummary : "",
      actor: typeof data.publishedBy === "string" ? data.publishedBy : null,
      requiresAcceptance: data.requiresAcceptance === true, createdAt: FieldValue.serverTimestamp()});
  });
}

/** At most 100 accounts per event. Stable inbox IDs make page retries safe;
 * cursor CAS prevents an older event advancing or rewinding another page. */
export async function deliverLegalPublicationPage(id: string, expectedSequence: number): Promise<void> {
  const ref = db.doc(`legalPublicationDelivery/${id}`), snapshot = await ref.get(), job = snapshot.data();
  if (!job || job.complete || job.sequence !== expectedSequence) return;
  if (!["terms", "privacy", "organizationRules"].includes(job.type) || typeof job.version !== "string") return;
  const pointer = await db.doc(`legalDocuments/${job.type}`).get();
  const superseded = pointer.get("activeVersion") !== job.version;
  let cursor = job.cursor, complete = superseded;
  if (!superseded) {
    let query = db.collection("users").orderBy(FieldPath.documentId()).limit(100);
    if (typeof cursor === "string") query = query.startAfter(cursor);
    const page = await query.get();
    const recipients = await resolveNotificationRecipients(page.docs.map(d => d.id));
    await Promise.all(recipients.inboxRecipientIds.map(userId => writeUserNotification({
      notificationId: `legalDocumentsUpdated_${job.type}_${job.version}_${userId}`,
      targetUserId: userId, type: "legalDocumentsUpdated", title: "Legal documents updated",
      message: job.changeSummary || "Please review the updated legal documents.",
      severity: job.requiresAcceptance ? "warning" : "info", actionType: "openLegalDocuments", actionTargetId: job.type,
      requiresPopup: false, actorUserId: job.actor, sourceType: "legal", sourceId: job.type,
      metadata: {documentType: job.type, activeVersion: job.version, route: "openLegalDocuments", routeTargetId: job.type},
      dedupeKey: `legalDocumentsUpdated:${job.type}:${job.version}:${userId}`,
    })));
    cursor = page.docs.at(-1)?.id ?? cursor; complete = page.size < 100;
  }
  await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    if (current.get("sequence") !== expectedSequence || current.get("complete")) return;
    tx.update(ref, {cursor, complete, sequence: expectedSequence + 1,
      ...(superseded ? {superseded: true} : {}), updatedAt: FieldValue.serverTimestamp()});
  });
}

export const deliverLegalPublicationBatch = onDocumentWritten({region: "europe-west3",
  document: "legalPublicationDelivery/{jobId}", maxInstances: 5, timeoutSeconds: 120, retry: true}, async event => {
  const after = event.data?.after.data(), before = event.data?.before.data();
  if (!after || after.complete || before?.sequence === after.sequence) return;
  await deliverLegalPublicationPage(event.params.jobId, after.sequence);
});
