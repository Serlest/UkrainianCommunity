import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {db} from "../firebase/admin";
import {buildUserNotificationDocument, resolveNotificationRecipients} from "../notifications/notificationPayloads";
const hash = (value: string) => createHash("sha256").update(value).digest("hex");
const interval = 15 * 60 * 1000;

export function journalAlertEligible(data: FirebaseFirestore.DocumentData, now: Date): boolean {
  const received = data.receivedAt instanceof Timestamp ? data.receivedAt : data.createdAt;
  return data.isReviewed !== true && ["warning", "error", "critical"].includes(data.severity)
    && (data.category === "diagnostics" || data.outcome === "failed")
    && received instanceof Timestamp && now.getTime() - received.toMillis() < 24 * 3600000
    && received.toMillis() <= now.getTime() + 300000;
}

/** One owner inbox item and central durable push per equivalent issue / 15 minutes.
 * Only fixed summaries go onto the lock screen; personal data stays in the gated journal.
 * An event retry or a derived-index update cannot duplicate the notification. */
export async function notifyJournalIssue(logId: string, now = new Date()): Promise<void> {
  const sourceRef = db.collection("systemLogs").doc(logId);
  const source = await sourceRef.get(), data = source.data();
  if (!data || !journalAlertEligible(data, now)) return;
  const received = data.receivedAt instanceof Timestamp ? data.receivedAt : data.createdAt as Timestamp;
  const bucket = Math.floor(received.toMillis() / interval);
  const fingerprint = hash(JSON.stringify([data.moduleName ?? "", data.operationName ?? "", data.errorCode ?? "", data.metadata?.diagnosticReason ?? "", data.metadata?.invalidField ?? "", data.severity]));
  const owners = await db.collection("users").where("globalRole", "==", "owner").get();
  const recipients = await resolveNotificationRecipients(owners.docs.map(d => d.id));
  for (const uid of recipients.inboxRecipientIds) {
    const notificationId = `systemLog_${hash(`${uid}:${fingerprint}:${bucket}`)}`;
    const ref = db.doc(`users/${uid}/notificationInbox/${notificationId}`);
    await db.runTransaction(async tx => {
      const [existing, currentOwner, log] = await Promise.all([tx.get(ref), tx.get(db.doc(`users/${uid}`)), tx.get(sourceRef)]);
      if (existing.exists || !log.exists || !journalAlertEligible(log.data()!, now) || currentOwner.get("globalRole") !== "owner" || (currentOwner.get("accountStatus") ?? "active") !== "active") return;
      const language = [currentOwner.get("appLanguage"), currentOwner.get("language"), currentOwner.get("preferredLanguage")].find(v => typeof v === "string") ?? "uk";
      const de = language.startsWith("de"), warning = data.severity === "warning";
      const title = de ? (warning ? "Systemwarnung" : "Systemfehler") : (warning ? "Системне попередження" : "Системна помилка");
      // Diagnostic warnings can report a condition without a failed user action.
      const message = de ? "Öffnen Sie den Protokolleintrag, um Ursache und Auswirkungen zu prüfen." : "Відкрийте запис журналу, щоб перевірити причину та наслідки.";
      tx.set(ref, buildUserNotificationDocument({notificationId, targetUserId: uid, type: "systemAnnouncement",
        title, message, severity: warning ? "warning" : "critical", actionType: "openProfile", actionTargetId: logId,
        sourceType: "system", sourceId: logId, dedupeKey: notificationId,
        metadata: {scope: "systemLogAlert", recipientScope: "appOwnerJournal", pushDelivery: "central", route: "openSystemLog", routeTargetId: logId},
      }));
    });
  }
}
export const notifySystemLogIssue = onDocumentCreated({document: "systemLogs/{logId}", region: "europe-west3", maxInstances: 5, retry: true}, async event => {
  await notifyJournalIssue(event.params.logId);
});
