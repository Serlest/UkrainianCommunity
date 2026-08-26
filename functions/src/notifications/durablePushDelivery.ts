import {createHash, randomUUID} from "node:crypto";
import {FieldValue, Timestamp, type DocumentReference} from "firebase-admin/firestore";
import type {BaseMessage, SendResponse} from "firebase-admin/messaging";
import {db} from "../firebase/admin";
import {isRetryablePushFailure, sendPushToRegistrationDocuments, type PushRegistrationDocument, type PushMulticastSender} from "./pushRegistrations";

const maxAgeMs = 24 * 60 * 60 * 1000;
const leaseMs = 120_000;

export function notificationPushIsExpired(createdAtMs: number, nowMs: number): boolean {
  return nowMs - createdAtMs > maxAgeMs;
}

export function terminalTargetIds(targets: Record<string, string>): Set<string> {
  return new Set(Object.entries(targets).filter(([, status]) =>
    status === "accepted" || status === "permanentFailure"
  ).map(([id]) => id));
}

/** FCM acceptance is not proof of display. A crash between provider acceptance and
 * persisting its receipt can still repeat a send; collapse IDs limit that window.
 * Receipts live below the inbox record, denied to clients by default and removed
 * with recursive account deletion. No tokens or message bodies are copied here. */
export async function deliverPushDurably(
  notificationRef: DocumentReference,
  message: BaseMessage,
  registrations: readonly PushRegistrationDocument[],
  sender?: PushMulticastSender
): Promise<void> {
  const ref = notificationRef.collection("privateDelivery").doc("push");
  const attemptId = randomUUID();
  const claim = await db.runTransaction(async (tx) => {
    const [source, receipt] = await Promise.all([tx.get(notificationRef), tx.get(ref)]);
    const data = source.data();
    if (!source.exists || data?.deletedAt || data?.archivedAt || data?.isRead === true) return undefined;
    const createdAt = data?.createdAt instanceof Timestamp ? data.createdAt.toMillis() : 0;
    if (notificationPushIsExpired(createdAt, Date.now())) return undefined;
    const state = receipt.data();
    if (state?.status === "complete" || state?.status === "failedConfiguration") return undefined;
    if (state?.leaseUntil instanceof Timestamp && state.leaseUntil.toMillis() > Date.now()) {
      throw new Error("Push delivery lease is still active; retry later.");
    }
    tx.set(ref, {
      status: "sending", attemptId, leaseUntil: Timestamp.fromMillis(Date.now() + leaseMs),
      attempts: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return terminalTargetIds(state?.targets ?? {});
  });
  if (!claim) return;
  const pending = registrations.filter((doc) => !claim.has(doc.id));
  let retry = false;
  let configurationFailure = false;
  const collapseId = createHash("sha256").update(notificationRef.path).digest("hex");
  try {
    await sendPushToRegistrationDocuments(pending, {
      ...message,
      apns: {
        ...message.apns,
        headers: {
          ...message.apns?.headers,
          "apns-push-type": "alert", "apns-priority": "10",
          "apns-collapse-id": collapseId,
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
        },
      },
    }, sender, async (ids: string[], response: SendResponse) => {
      const retryable = isRetryablePushFailure(response);
      retry ||= retryable;
      const code = response.error?.code;
      configurationFailure ||= !response.success && !retryable
        && !["messaging/invalid-registration-token", "messaging/registration-token-not-registered"].includes(code ?? "");
      await db.runTransaction(async (tx) => {
        const [source, receipt] = await Promise.all([tx.get(notificationRef), tx.get(ref)]);
        if (!source.exists || receipt.data()?.attemptId !== attemptId) return;
        const patch: Record<string, unknown> = {updatedAt: FieldValue.serverTimestamp()};
        for (const id of ids) patch[`targets.${id}`] = response.success ? "accepted" : retryable ? "retry" : "permanentFailure";
        if (code) patch.lastErrorCode = code;
        tx.update(ref, patch);
      });
    });
    await finish(retry ? "retry" : configurationFailure ? "failedConfiguration" : "complete");
  } catch (error) {
    await finish("retry");
    throw error;
  }
  if (retry) throw new Error("Transient push delivery failure; retry pending targets.");

  async function finish(status: string): Promise<void> {
    await db.runTransaction(async (tx) => {
      const [source, receipt] = await Promise.all([tx.get(notificationRef), tx.get(ref)]);
      if (!source.exists || !receipt.exists || receipt.data()?.attemptId !== attemptId) return;
      tx.update(ref, {status, leaseUntil: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp()});
    });
  }
}
