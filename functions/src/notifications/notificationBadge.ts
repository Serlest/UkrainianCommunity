import {db} from "../firebase/admin";

/** Keep aligned with AppNotification.countsAsUnread. Archived/deleted inbox
 * records are retained for history but must not contribute to the app badge. */
export function countsAsUnread(data: Record<string, unknown>): boolean {
  return data.isRead === false && data.archivedAt == null && data.deletedAt == null;
}

export async function unreadNotificationCount(userId: string): Promise<number> {
  const snapshot = await db.collection("users").doc(userId)
    .collection("notificationInbox").where("isRead", "==", false).get();
  return snapshot.docs.filter((document) => countsAsUnread(document.data())).length;
}
