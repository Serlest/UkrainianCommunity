export function buildContentDraftNotificationDocument({
  ownerUserId,
  draftId,
  kind,
  state,
  title,
  now,
}) {
  const notificationId = `contentDraftReady_${draftId}`;
  const notificationTitle = kind === "news" ? "Нова чернетка новини" : "Нова чернетка події";
  const metadata = {
    pushDelivery: "central",
    kind,
    state,
    title: notificationTitle,
    message: title,
  };

  return {
    id: notificationId,
    userId: ownerUserId,
    recipientUserId: ownerUserId,
    type: "contentDraftReady",
    title: notificationTitle,
    message: title,
    severity: state === "needsAttention" ? "warning" : "info",
    actionType: "openContentPlanning",
    actionTargetId: draftId,
    requiresPopup: false,
    popupPresentedAt: null,
    expiresAt: null,
    archivedAt: null,
    deletedAt: null,
    readAt: null,
    sourceType: "contentDraft",
    sourceId: draftId,
    dedupeKey: `contentDraftReady:${draftId}`,
    isRead: false,
    createdAt: now,
    updatedAt: now,
    metadata,
    payload: metadata,
  };
}
