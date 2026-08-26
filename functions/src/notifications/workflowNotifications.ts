import {createHash} from "node:crypto";
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {db} from "../firebase/admin";
import {canManageOrganizationRequests, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {resolveNotificationRecipients, writeUserNotification, type NotificationActionType, type NotificationType} from "./notificationPayloads";

type Data = FirebaseFirestore.DocumentData;
const options = {region: "europe-west3", maxInstances: 10, retry: true};
const text = (value: unknown): string | undefined => typeof value === "string" && value.trim() ? value.trim() : undefined;
const strings = (value: unknown): string[] => Array.isArray(value) ? value.filter((v): v is string => typeof v === "string" && !!v) : [];

export function organizationStaff(data: Data): string[] {
  return [...new Set([text(data.ownerId), ...strings(data.adminIds), ...strings(data.moderatorIds)]
    .filter((v): v is string => !!v))];
}

export function isOrganizationSubmission(before: Data | undefined, after: Data | undefined): boolean {
  return after?.moderationStatus === "pendingReview" && before?.moderationStatus !== "pendingReview"
    && !!text(after.submittedByUserId);
}

export async function platformReviewers(): Promise<string[]> {
  const users = await db.collection("users").where("globalRole", "in", ["owner", "admin"]).get();
  return users.docs.filter((doc) => canManageOrganizationRequests(userPermissionSnapshotFromData(doc.id, doc.data())))
    .map((doc) => doc.id);
}

export async function canReceiveScopedNotification(userId: string, metadata: Record<string, unknown>): Promise<boolean> {
  if (metadata.recipientScope === "platformReviewers") {
    const user = await db.collection("users").doc(userId).get();
    if (!canManageOrganizationRequests(userPermissionSnapshotFromData(userId, user.data()))) return false;
    if (text(metadata.organizationRequestId)) {
      const organization = await db.collection("organizations").doc(metadata.organizationRequestId as string).get();
      if (organization.data()?.moderationStatus !== "pendingReview") return false;
    }
  }
  if (metadata.recipientScope === "organizationStaff") {
    const orgId = text(metadata.organizationId);
    if (!orgId) return false;
    const org = await db.collection("organizations").doc(orgId).get();
    if (!org.exists || !organizationStaff(org.data()!).includes(userId)) return false;
  }
  const actor = text(metadata.actorUserId);
  if (actor && metadata.respectPersonalBlock === true) {
    if ((await db.collection("users").doc(userId).collection("blockedUsers").doc(actor).get()).exists) return false;
  }
  return true;
}

interface WorkflowNotice {
  eventId: string;
  type: NotificationType;
  targetId: string;
  action: NotificationActionType;
  sourceType: "organization" | "event" | "system";
  titleKey: string;
  // UK/DE fallback is also stored for older installed builds.
  title: [string, string];
  body: string;
  actor?: string;
  recipients: string[];
  metadata?: Record<string, unknown>;
}

export async function writeWorkflowNotifications(input: WorkflowNotice): Promise<void> {
  if (input.actor && !(await db.collection("users").doc(input.actor).get()).exists) return;
  const recipients = await resolveNotificationRecipients(input.recipients.filter((id) => id !== input.actor));
  for (const userId of recipients.inboxRecipientIds) {
    const metadata = {...input.metadata, actorUserId: input.actor ?? "", titleLocKey: input.titleKey,
      bodyLocKey: "notifications.push.workflow.body", bodyLocArgs: [input.body.slice(0, 160)]};
    if (!await canReceiveScopedNotification(userId, metadata)) continue;
    const user = await db.collection("users").doc(userId).get();
    const language = [user.data()?.appLanguage, user.data()?.language, user.data()?.preferredLanguage]
      .find((v): v is string => typeof v === "string") ?? "uk";
    const notificationId = `${input.type}_${createHash("sha256").update(`${input.eventId}:${userId}`).digest("hex")}`;
    await writeUserNotification({
      notificationId, targetUserId: userId, type: input.type,
      title: input.title[language.startsWith("de") ? 1 : 0], message: input.body.slice(0, 160),
      actionType: input.action, actionTargetId: input.targetId, sourceId: input.targetId,
      sourceType: input.sourceType, actorUserId: input.actor, metadata, dedupeKey: notificationId,
    });
  }
}

export async function notifyOrganizationSubmission(eventId: string, organizationId: string, before: Data | undefined, after: Data | undefined): Promise<void> {
  if (!isOrganizationSubmission(before, after)) return;
  await writeWorkflowNotifications({
    eventId, type: "organizationRequestSubmitted", targetId: organizationId,
    action: "openOrganizationRequest", sourceType: "organization",
    titleKey: "notifications.push.organization_submitted.title",
    title: ["Заявка організації на перевірку", "Organisationsantrag zur Prüfung"],
    body: text(after?.name) ?? "", actor: text(after?.submittedByUserId), recipients: await platformReviewers(),
    metadata: {recipientScope: "platformReviewers", organizationRequestId: organizationId, organizationName: text(after?.name) ?? ""},
  });
}

export const notifyOrganizationRequestSubmitted = onDocumentWritten(
  {...options, document: "organizations/{organizationId}"},
  async (event) => notifyOrganizationSubmission(event.id, event.params.organizationId, event.data?.before.data(), event.data?.after.data())
);

type ContentCollection = "news" | "events" | "organizations";
export async function notifyContentComment(eventId: string, collection: ContentCollection, contentId: string, comment: Data | undefined): Promise<void> {
  const actor = text(comment?.authorId);
  if (!actor || comment?.moderationStatus !== "approved") return;
  const snapshot = await db.collection(collection).doc(contentId).get();
  const content = snapshot.data();
  if (!content || content.moderationStatus !== "approved") return;
  const orgId = collection === "organizations" ? contentId : text(content.organizationId);
  const org = orgId ? await db.collection("organizations").doc(orgId).get() : undefined;
  const staff = org?.exists ? organizationStaff(org.data()!) : [];
  const author = text(content.authorId);
  const candidates = [...staff, ...(author ? [author] : [])];
  for (const recipient of new Set(candidates)) {
    await writeWorkflowNotifications({eventId, type: "commentAdded", targetId: contentId,
      action: collection === "news" ? "openNews" : collection === "events" ? "openEvent" : "openOrganization",
      sourceType: collection === "events" ? "event" : collection === "organizations" ? "organization" : "system",
      titleKey: "notifications.push.comment_added.title", title: ["Новий коментар", "Neuer Kommentar"],
      body: text(content.title) ?? text(content.name) ?? "", actor, recipients: [recipient],
      metadata: {respectPersonalBlock: true, organizationId: orgId ?? "", contentCollection: collection,
        recipientScope: staff.includes(recipient) ? "organizationStaff" : "contentAuthor"},
    });
  }
}
export const notifyNewsCommentCreated = onDocumentCreated({...options, document: "news/{contentId}/comments/{commentId}"}, async (e) => notifyContentComment(e.id, "news", e.params.contentId, e.data?.data()));
export const notifyEventCommentCreated = onDocumentCreated({...options, document: "events/{contentId}/comments/{commentId}"}, async (e) => notifyContentComment(e.id, "events", e.params.contentId, e.data?.data()));
export const notifyOrganizationCommentCreated = onDocumentCreated({...options, document: "organizations/{contentId}/comments/{commentId}"}, async (e) => notifyContentComment(e.id, "organizations", e.params.contentId, e.data?.data()));

export async function notifyContentModeration(eventId: string, collection: "news" | "events", contentId: string, before: Data | undefined, after: Data | undefined): Promise<void> {
  if (!before || !after || before.moderationStatus === after.moderationStatus) return;
  if (!["approved", "rejected", "archived", "pendingReview"].includes(after.moderationStatus)) return;
  if (after.cancellationState === "cancelled") return; // handled by event cancellation notification
  const orgId = text(after.organizationId);
  const org = orgId ? await db.collection("organizations").doc(orgId).get() : undefined;
  const staff = org?.exists ? organizationStaff(org.data()!) : [];
  await writeWorkflowNotifications({eventId, type: "contentModerationChanged", targetId: orgId ?? contentId,
    // Organization management can display unpublished content; public detail cannot.
    action: orgId ? "openOrganization" : "openProfile", sourceType: "system",
    titleKey: "notifications.push.content_moderated.title", title: ["Статус публікації змінено", "Veröffentlichungsstatus geändert"],
    body: text(after.title) ?? "", actor: text(after.updatedByUserId) ?? text(after.updatedBy), recipients: staff,
    metadata: {organizationId: orgId ?? "", recipientScope: "organizationStaff", moderationStatus: after.moderationStatus,
      route: "openOrganization", routeTargetId: orgId ?? contentId},
  });
}
export const notifyNewsModerationChanged = onDocumentWritten({...options, document: "news/{contentId}"}, async (e) => notifyContentModeration(e.id, "news", e.params.contentId, e.data?.before.data(), e.data?.after.data()));
export const notifyEventModerationChanged = onDocumentWritten({...options, document: "events/{contentId}"}, async (e) => notifyContentModeration(e.id, "events", e.params.contentId, e.data?.before.data(), e.data?.after.data()));

export const notifyEventParticipationChanged = onDocumentWritten({...options, document: "registrations/{registrationId}"}, async (event) => {
  const before = event.data?.before.data(); const after = event.data?.after.data();
  if (!!before === !!after) return;
  const registration = after ?? before;
  const eventId = text(registration?.eventId); const actor = text(registration?.userId);
  if (!eventId || !actor) return;
  const content = await db.collection("events").doc(eventId).get();
  if (content.data()?.moderationStatus !== "approved") return;
  const orgId = text(content.data()?.organizationId); if (!orgId) return;
  const org = await db.collection("organizations").doc(orgId).get(); if (!org.exists) return;
  await writeWorkflowNotifications({eventId: event.id, type: "eventParticipationChanged", targetId: eventId,
    action: "openEvent", sourceType: "event",
    titleKey: after ? "notifications.push.participant_registered.title" : "notifications.push.participant_cancelled.title",
    title: after ? ["Нова реєстрація на подію", "Neue Veranstaltungsanmeldung"] : ["Реєстрацію на подію скасовано", "Veranstaltungsanmeldung storniert"],
    body: text(content.data()?.title) ?? "", actor, recipients: organizationStaff(org.data()!),
    metadata: {organizationId: orgId, recipientScope: "organizationStaff", participationState: after ? "registered" : "cancelled"},
  });
});
