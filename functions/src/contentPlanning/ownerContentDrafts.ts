import {createHash, randomUUID} from "node:crypto";

import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {adminStorage, db} from "../firebase/admin";
import {assertOwner} from "../permissions/userPermissions";
import {writeUserNotification} from "../notifications/notificationPayloads";

type DraftKind = "news" | "event";
type DraftState = "readyForReview" | "needsAttention";
type PublicationDraftKind = "news" | "event";
type StoredDraftState = DraftState | "scheduled" | "publishing" | "failed" | "completed" | "archived";

const publicationLeaseDurationMilliseconds = 10 * 60 * 1000;

const newsCategories = new Set([
  "news", "event", "lawAndDocuments", "benefitsAndSupport",
  "financeTaxesAndConsumerRights", "health", "safetyAndEmergencies",
  "work", "education", "housing", "transport",
  "communityAndIntegration", "culture", "other",
]);

const eventCategories = new Set([
  "meetups", "training", "culture", "education", "childrenAndFamily",
  "sportsAndWellness", "excursionsAndNature", "music", "nightlifeAndParties",
  "foodAndMarket", "festivalsAndFairs", "businessAndNetworking",
  "volunteering", "supportAndIntegration", "celebration", "saleAndPromotion", "other",
]);

interface SourceInput {
  url: string;
  title?: string;
  isPrimary: boolean;
  checkedAt?: string;
}

interface ParsedDraftInput {
  idempotencyKey: string;
  kind: DraftKind;
  state: DraftState;
  title: string;
  payload: Record<string, unknown>;
  sources: Array<Record<string, unknown>>;
  verificationNotes: string[];
  missingFields: string[];
  generatedImage?: {
    url: string;
    storagePath: string;
    alternativeText?: string;
    credit?: string;
  };
}

const newsFields = new Set([
  "title", "summary", "body", "sourceInput", "category", "additionalCategories", "tags", "federalState",
  "germanTitle", "germanSummary", "germanBody", "imageCaption",
  "imageAlternativeText", "imageCredit", "externalActionTitle", "externalActionURL",
  "regionScope", "publicationMode", "scheduledAt",
]);

const eventFields = new Set([
  "title", "summary", "details", "city", "venue", "address", "locationNote",
  "latitude", "longitude", "eventOrganizerName", "organizerURL", "contactPhone",
  "contactEmail", "contactURL", "federalState", "startDate", "endDate", "hasExplicitEndDate", "isAllDay",
  "category", "additionalCategories", "audience", "minimumAge", "maximumAge", "tags", "capacity",
  "germanTitle", "germanSummary", "germanDetails", "additionalOccurrences",
  "participationMode", "externalActionTitle", "externalActionURL", "priceKind",
  "price", "maximumPrice", "priceNote",
  "publicationMode", "scheduledAt",
]);

export function parseOwnerContentDraftInput(value: unknown): ParsedDraftInput {
  const input = record(value, "request");
  const idempotencyKey = requiredString(input.idempotencyKey, "idempotencyKey", 120);
  const kind = enumValue(input.kind, "kind", new Set<DraftKind>(["news", "event"]));
  const rawPayload = record(input.payload, "payload");
  const allowedFields = kind === "news" ? newsFields : eventFields;
  const payload: Record<string, unknown> = {};
  for (const [key, fieldValue] of Object.entries(rawPayload)) {
    if (!allowedFields.has(key)) {
      throw new HttpsError("invalid-argument", `Unsupported payload field: ${key}.`);
    }
    payload[key] = normalizedPayloadValue(key, fieldValue);
  }

  validatePayload(kind, payload);
  const missingFields = stringArray(input.missingFields, "missingFields", 30, 100);
  const verificationNotes = stringArray(input.verificationNotes, "verificationNotes", 30, 500);
  const requestedState = input.state === undefined
    ? undefined
    : enumValue(input.state, "state", new Set<DraftState>(["readyForReview", "needsAttention"]));
  if (requestedState === "needsAttention" && missingFields.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "needsAttention requires at least one concrete missingFields entry."
    );
  }
  const sources = sourceArray(input.sources);
  const generatedImage = optionalGeneratedImage(input.generatedImage);
  if (generatedImage) {
    payload.generatedImageURL = generatedImage.url;
    if (kind === "news") {
      payload.imageAlternativeText ??= generatedImage.alternativeText ?? null;
      payload.imageCredit ??= generatedImage.credit ?? null;
    }
  }

  return {
    idempotencyKey,
    kind,
    state: requestedState ?? (missingFields.length > 0 ? "needsAttention" : "readyForReview"),
    title: requiredString(payload.title, "payload.title", 120),
    payload,
    sources,
    verificationNotes,
    missingFields,
    generatedImage,
  };
}

export async function saveOwnerContentDraftForUser(
  ownerUserId: string,
  parsed: ParsedDraftInput
): Promise<{draftId: string; created: boolean}> {
  const draftId = createHash("sha256")
    .update(`${ownerUserId}:${parsed.idempotencyKey}`)
    .digest("hex")
    .slice(0, 40);
  const reference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(draftId);
  let created = false;

  if (parsed.generatedImage && !parsed.generatedImage.storagePath.startsWith(
    `users/${ownerUserId}/contentPlanningDraftImages/`
  )) {
    throw new HttpsError("invalid-argument", "Generated image must belong to the owner draft area.");
  }

  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) return;
    created = true;
    transaction.create(reference, {
      id: draftId,
      schemaVersion: 3,
      ownerUserId,
      kind: parsed.kind,
      state: parsed.state,
      title: parsed.title,
      payload: parsed.payload,
      sources: parsed.sources,
      verificationNotes: parsed.verificationNotes,
      missingFields: parsed.missingFields,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      scheduledAt: parsed.payload.publicationMode === "scheduled"
        ? parsed.payload.scheduledAt ?? null
        : null,
      completedAt: null,
      archivedAt: null,
      failureMessage: null,
      generatedImage: parsed.generatedImage ?? null,
      publishedContentId: null,
      publishedContentKind: null,
      publishedOrganizationId: null,
      publishedOrganizationName: null,
      publicationOutcome: null,
    });
  });

  if (created) {
    await writeUserNotification({
      notificationId: `contentDraftReady_${draftId}`,
      targetUserId: ownerUserId,
      type: "contentDraftReady",
      title: parsed.kind === "news" ? "Нова чернетка новини" : "Нова чернетка події",
      message: parsed.title,
      severity: parsed.state === "needsAttention" ? "warning" : "info",
      actionType: "openContentPlanning",
      actionTargetId: draftId,
      sourceType: "contentDraft",
      sourceId: draftId,
      dedupeKey: `contentDraftReady:${draftId}`,
      metadata: {kind: parsed.kind, state: parsed.state},
    });
  }

  return {draftId, created};
}

export const saveOwnerContentDraft = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    const parsed = parseOwnerContentDraftInput(request.data);
    return saveOwnerContentDraftForUser(actor.uid, parsed);
  }
);

export function parseOwnerContentDraftID(value: unknown): string {
  const input = record(value, "request");
  const draftId = requiredString(input.draftId, "draftId", 40);
  if (!/^[a-f0-9]{40}$/.test(draftId)) {
    throw new HttpsError("invalid-argument", "draftId is invalid.");
  }
  return draftId;
}

export async function deleteOwnerContentDraftForUser(
  ownerUserId: string,
  draftId: string
): Promise<{deleted: boolean}> {
  const draftReference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(draftId);
  const deletion = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(draftReference);
    if (!snapshot.exists) return undefined;
    const state = snapshot.get("state") as StoredDraftState | undefined;
    if (!["readyForReview", "needsAttention", "failed", "archived"].includes(state ?? "")) {
      throw new HttpsError(
        "failed-precondition",
        "A publishing, scheduled, or completed planning record cannot be deleted."
      );
    }
    const linkedContentId = optionalString(snapshot.get("publishedContentId"), 160);
    if (linkedContentId) {
      const kind = enumValue(
        snapshot.get("kind"),
        "draft.kind",
        new Set<PublicationDraftKind>(["news", "event"])
      );
      const linkedContent = await transaction.get(
        db.collection(kind === "news" ? "news" : "events").doc(linkedContentId)
      );
      if (linkedContent.exists) {
        throw new HttpsError("failed-precondition", "A planning record linked to content cannot be deleted.");
      }
    }
    const generatedImage = snapshot.get("generatedImage") as Record<string, unknown> | undefined;
    const storagePath = typeof generatedImage?.storagePath === "string"
      ? generatedImage.storagePath
      : undefined;
    transaction.update(draftReference, {
      state: "archived",
      publicationOutcome: "archived",
      deletionInProgress: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {storagePath};
  });
  if (!deletion) return {deleted: false};

  const storagePath = deletion.storagePath;
  const expectedPrefix = `users/${ownerUserId}/contentPlanningDraftImages/`;
  if (storagePath?.startsWith(expectedPrefix)) {
    await adminStorage.bucket().file(storagePath).delete({ignoreNotFound: true});
  }

  const notificationReference = db.collection("users").doc(ownerUserId)
    .collection("notificationInbox").doc(`contentDraftReady_${draftId}`);
  const batch = db.batch();
  batch.delete(draftReference);
  batch.delete(notificationReference);
  await batch.commit();
  return {deleted: true};
}

export const deleteOwnerContentDraft = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return deleteOwnerContentDraftForUser(actor.uid, parseOwnerContentDraftID(request.data));
  }
);

interface ScheduledPublicationInput {
  draftId: string;
  contentId: string;
  kind: PublicationDraftKind;
  scheduledAt: Date;
}

export function parseScheduledPublicationInput(value: unknown): ScheduledPublicationInput {
  const input = record(value, "request");
  const draftId = parseOwnerContentDraftID({draftId: input.draftId});
  const contentId = requiredString(input.contentId, "contentId", 160);
  const kind = enumValue(
    input.kind,
    "kind",
    new Set<PublicationDraftKind>(["news", "event"])
  );
  return {
    draftId,
    contentId,
    kind,
    scheduledAt: requiredDate(input.scheduledAt, "scheduledAt"),
  };
}

export async function scheduleOwnerContentDraftForUser(
  ownerUserId: string,
  input: ScheduledPublicationInput
): Promise<{scheduled: boolean}> {
  const draftReference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(input.draftId);
  const collection = input.kind === "news" ? "news" : "events";
  const contentReference = db.collection(collection).doc(input.contentId);

  await db.runTransaction(async (transaction) => {
    const [draftSnapshot, contentSnapshot] = await Promise.all([
      transaction.get(draftReference),
      transaction.get(contentReference),
    ]);
    if (!draftSnapshot.exists) {
      throw new HttpsError("not-found", "Content planning draft was not found.");
    }
    if (!contentSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Scheduled content was not created.");
    }
    if (draftSnapshot.get("kind") !== input.kind) {
      throw new HttpsError("failed-precondition", "Draft and published content kinds do not match.");
    }
    if (!["readyForReview", "needsAttention"].includes(draftSnapshot.get("state"))) {
      throw new HttpsError("failed-precondition", "Draft is no longer available for scheduling.");
    }
    const contentScheduledAt = contentSnapshot.get("scheduledAt");
    if (contentSnapshot.get("authorId") !== ownerUserId ||
        contentSnapshot.get("moderationStatus") !== "draft" ||
        !(contentScheduledAt instanceof Timestamp) ||
        Math.abs(contentScheduledAt.toMillis() - input.scheduledAt.getTime()) > 1000) {
      throw new HttpsError("failed-precondition", "Scheduled content does not match the draft publication.");
    }

    transaction.update(draftReference, {
      state: "scheduled",
      scheduledAt: contentScheduledAt,
      publishedContentId: input.contentId,
      publishedContentKind: input.kind,
      publishedOrganizationId: contentSnapshot.get("organizationId") ?? null,
      publishedOrganizationName: contentSnapshot.get("organizationName") ?? null,
      publicationOutcome: "scheduled",
      failureMessage: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return {scheduled: true};
}

export const scheduleOwnerContentDraft = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return scheduleOwnerContentDraftForUser(
      actor.uid,
      parseScheduledPublicationInput(request.data)
    );
  }
);

interface BeginPublicationInput {
  draftId: string;
  attemptId: string;
}

interface PublicationLeaseResult {
  draftId: string;
  kind: PublicationDraftKind;
  contentId: string;
  leaseId: string;
  expiresAt: string;
  contentAlreadyExists: boolean;
  existingModerationStatus: "draft" | "pendingReview" | "approved" | null;
  existingScheduledAt: string | null;
}

export function parseBeginPublicationInput(value: unknown): BeginPublicationInput {
  const input = record(value, "request");
  const attemptId = requiredString(input.attemptId, "attemptId", 80);
  if (!/^[A-Za-z0-9_-]{16,80}$/.test(attemptId)) {
    throw new HttpsError("invalid-argument", "attemptId is invalid.");
  }
  return {
    draftId: parseOwnerContentDraftID({draftId: input.draftId}),
    attemptId,
  };
}

export async function beginOwnerContentDraftPublicationForUser(
  ownerUserId: string,
  input: BeginPublicationInput,
  now = Timestamp.now()
): Promise<PublicationLeaseResult> {
  const draftReference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(input.draftId);

  return db.runTransaction(async (transaction) => {
    const draftSnapshot = await transaction.get(draftReference);
    if (!draftSnapshot.exists) {
      throw new HttpsError("not-found", "Content planning draft was not found.");
    }
    const kind = enumValue(
      draftSnapshot.get("kind"),
      "draft.kind",
      new Set<PublicationDraftKind>(["news", "event"])
    );
    const state = enumValue(
      draftSnapshot.get("state"),
      "draft.state",
      new Set<StoredDraftState>([
        "readyForReview", "needsAttention", "scheduled", "publishing",
        "failed", "completed", "archived",
      ])
    );
    if (state === "archived") {
      throw new HttpsError("failed-precondition", "Draft is already in a terminal publication state.");
    }

    const existingAttemptId = optionalString(draftSnapshot.get("publicationAttemptId"), 80);
    const existingLeaseId = optionalString(draftSnapshot.get("publicationLeaseId"), 80);
    const existingExpiry = draftSnapshot.get("publicationLeaseExpiresAt");
    const hasActiveLease = state === "publishing"
      && existingLeaseId
      && existingExpiry instanceof Timestamp
      && existingExpiry.toMillis() > now.toMillis();
    if (hasActiveLease && existingAttemptId !== input.attemptId) {
      throw new HttpsError("aborted", "Another publication attempt is still active.");
    }

    const contentId = optionalString(draftSnapshot.get("publishedContentId"), 160)
      ?? `planning-${input.draftId}`;
    const collection = kind === "news" ? "news" : "events";
    const contentReference = db.collection(collection).doc(contentId);
    const contentSnapshot = await transaction.get(contentReference);
    let existingModerationStatus: "draft" | "pendingReview" | "approved" | null = null;
    let existingScheduledAt: string | null = null;
    if (contentSnapshot.exists) {
      const contentAuthorId = optionalString(contentSnapshot.get("authorId"), 128);
      const organizationId = optionalString(contentSnapshot.get("organizationId"), 160);
      const moderationStatus = enumValue(
        contentSnapshot.get("moderationStatus"),
        "content.moderationStatus",
        new Set(["draft", "pendingReview", "approved"] as const)
      );
      if (contentAuthorId !== ownerUserId || !organizationId ||
          !["draft", "pendingReview", "approved"].includes(moderationStatus)) {
        throw new HttpsError(
          "failed-precondition",
          "Reserved publication content exists but does not belong to this planning draft."
        );
      }
      existingModerationStatus = moderationStatus;
      const scheduledAt = contentSnapshot.get("scheduledAt");
      existingScheduledAt = scheduledAt instanceof Timestamp
        ? scheduledAt.toDate().toISOString()
        : null;
    }

    if (["scheduled", "completed"].includes(state)) {
      if (!contentSnapshot.exists || draftSnapshot.get("publishedContentKind") !== kind) {
        throw new HttpsError("failed-precondition", "Terminal planning record has no valid content link.");
      }
      const expiresAt = Timestamp.fromMillis(now.toMillis() + publicationLeaseDurationMilliseconds);
      return {
        draftId: input.draftId,
        kind,
        contentId,
        leaseId: randomUUID(),
        expiresAt: expiresAt.toDate().toISOString(),
        contentAlreadyExists: true,
        existingModerationStatus,
        existingScheduledAt,
      };
    }

    const leaseId = hasActiveLease && existingLeaseId ? existingLeaseId : randomUUID();
    const expiresAt = hasActiveLease && existingExpiry instanceof Timestamp
      ? existingExpiry
      : Timestamp.fromMillis(now.toMillis() + publicationLeaseDurationMilliseconds);
    transaction.update(draftReference, {
      state: "publishing",
      publishedContentId: contentId,
      publishedContentKind: kind,
      publicationAttemptId: input.attemptId,
      publicationLeaseId: leaseId,
      publicationLeaseExpiresAt: expiresAt,
      failureMessage: null,
      updatedAt: now,
    });

    return {
      draftId: input.draftId,
      kind,
      contentId,
      leaseId,
      expiresAt: expiresAt.toDate().toISOString(),
      contentAlreadyExists: contentSnapshot.exists,
      existingModerationStatus,
      existingScheduledAt,
    };
  });
}

export const beginOwnerContentDraftPublication = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return beginOwnerContentDraftPublicationForUser(
      actor.uid,
      parseBeginPublicationInput(request.data)
    );
  }
);

interface FinalizePublicationInput {
  draftId: string;
  leaseId: string;
  contentId: string;
  kind: PublicationDraftKind;
}

export function parseFinalizePublicationInput(value: unknown): FinalizePublicationInput {
  const input = record(value, "request");
  return {
    draftId: parseOwnerContentDraftID({draftId: input.draftId}),
    leaseId: requiredString(input.leaseId, "leaseId", 80),
    contentId: requiredString(input.contentId, "contentId", 160),
    kind: enumValue(input.kind, "kind", new Set<PublicationDraftKind>(["news", "event"])),
  };
}

export async function finalizeOwnerContentDraftPublicationForUser(
  ownerUserId: string,
  input: FinalizePublicationInput,
  now = Timestamp.now()
): Promise<{finalized: boolean; state: "scheduled" | "completed"}> {
  const draftReference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(input.draftId);
  const collection = input.kind === "news" ? "news" : "events";
  const contentReference = db.collection(collection).doc(input.contentId);

  return db.runTransaction(async (transaction) => {
    const [draftSnapshot, contentSnapshot] = await Promise.all([
      transaction.get(draftReference),
      transaction.get(contentReference),
    ]);
    if (!draftSnapshot.exists) {
      throw new HttpsError("not-found", "Content planning draft was not found.");
    }
    const currentState = draftSnapshot.get("state") as StoredDraftState | undefined;
    const linkedContentId = draftSnapshot.get("publishedContentId");
    const linkedKind = draftSnapshot.get("publishedContentKind");
    if (["scheduled", "completed"].includes(currentState ?? "") &&
        linkedContentId === input.contentId && linkedKind === input.kind) {
      return {finalized: true, state: currentState as "scheduled" | "completed"};
    }
    if (currentState !== "publishing" ||
        draftSnapshot.get("publicationLeaseId") !== input.leaseId ||
        linkedContentId !== input.contentId || linkedKind !== input.kind) {
      throw new HttpsError("failed-precondition", "Publication lease no longer owns this draft.");
    }
    if (!contentSnapshot.exists) {
      throw new HttpsError("failed-precondition", "Published content was not created.");
    }
    const organizationId = requiredString(
      contentSnapshot.get("organizationId"),
      "content.organizationId",
      160
    );
    if (contentSnapshot.get("authorId") !== ownerUserId) {
      throw new HttpsError("failed-precondition", "Published content has a different author.");
    }
    const moderationStatus = enumValue(
      contentSnapshot.get("moderationStatus"),
      "content.moderationStatus",
      new Set(["draft", "pendingReview", "approved"])
    );
    const scheduledAt = contentSnapshot.get("scheduledAt");
    const isScheduled = moderationStatus === "draft";
    if (isScheduled && !(scheduledAt instanceof Timestamp)) {
      throw new HttpsError("failed-precondition", "Scheduled content has no valid publication time.");
    }
    const nextState = isScheduled ? "scheduled" : "completed";
    const outcome = isScheduled ? "scheduled" : moderationStatus;
    transaction.update(draftReference, {
      state: nextState,
      scheduledAt: isScheduled ? scheduledAt : null,
      completedAt: isScheduled ? null : now,
      publishedContentId: input.contentId,
      publishedContentKind: input.kind,
      publishedOrganizationId: organizationId,
      publishedOrganizationName: optionalString(contentSnapshot.get("organizationName"), 200) ?? null,
      publicationOutcome: outcome,
      failureMessage: null,
      publicationAttemptId: FieldValue.delete(),
      publicationLeaseId: FieldValue.delete(),
      publicationLeaseExpiresAt: FieldValue.delete(),
      updatedAt: now,
    });
    return {finalized: true, state: nextState};
  });
}

export const finalizeOwnerContentDraftPublication = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return finalizeOwnerContentDraftPublicationForUser(
      actor.uid,
      parseFinalizePublicationInput(request.data)
    );
  }
);

interface FailPublicationInput {
  draftId: string;
  leaseId: string;
  message: string;
}

export function parseFailPublicationInput(value: unknown): FailPublicationInput {
  const input = record(value, "request");
  return {
    draftId: parseOwnerContentDraftID({draftId: input.draftId}),
    leaseId: requiredString(input.leaseId, "leaseId", 80),
    message: requiredString(input.message, "message", 500),
  };
}

export async function failOwnerContentDraftPublicationForUser(
  ownerUserId: string,
  input: FailPublicationInput,
  now = Timestamp.now()
): Promise<{failed: boolean}> {
  const draftReference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(input.draftId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(draftReference);
    if (!snapshot.exists) throw new HttpsError("not-found", "Content planning draft was not found.");
    if (snapshot.get("state") !== "publishing" ||
        snapshot.get("publicationLeaseId") !== input.leaseId) {
      throw new HttpsError("failed-precondition", "Publication lease no longer owns this draft.");
    }
    transaction.update(draftReference, {
      state: "failed",
      failureMessage: input.message,
      publicationAttemptId: FieldValue.delete(),
      publicationLeaseId: FieldValue.delete(),
      publicationLeaseExpiresAt: FieldValue.delete(),
      updatedAt: now,
    });
  });
  return {failed: true};
}

export const failOwnerContentDraftPublication = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return failOwnerContentDraftPublicationForUser(
      actor.uid,
      parseFailPublicationInput(request.data)
    );
  }
);

export async function archiveOwnerContentDraftForUser(
  ownerUserId: string,
  draftId: string,
  now = Timestamp.now()
): Promise<{archived: boolean}> {
  const reference = db.collection("users").doc(ownerUserId)
    .collection("contentPlanningDrafts").doc(draftId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) throw new HttpsError("not-found", "Content planning draft was not found.");
    const state = snapshot.get("state") as StoredDraftState | undefined;
    if (state === "archived") return;
    if (!["readyForReview", "needsAttention", "failed"].includes(state ?? "")) {
      throw new HttpsError("failed-precondition", "Only an unpublished draft can be archived.");
    }
    const linkedContentId = optionalString(snapshot.get("publishedContentId"), 160);
    if (linkedContentId) {
      const kind = enumValue(
        snapshot.get("kind"),
        "draft.kind",
        new Set<PublicationDraftKind>(["news", "event"])
      );
      const linkedContent = await transaction.get(
        db.collection(kind === "news" ? "news" : "events").doc(linkedContentId)
      );
      if (linkedContent.exists) {
        throw new HttpsError(
          "failed-precondition",
          "A planning record linked to content must be resumed instead of archived."
        );
      }
    }
    transaction.update(reference, {
      state: "archived",
      archivedAt: now,
      publicationOutcome: "archived",
      publishedContentId: null,
      publishedContentKind: null,
      publishedOrganizationId: null,
      publishedOrganizationName: null,
      failureMessage: null,
      updatedAt: now,
    });
  });
  return {archived: true};
}

export const archiveOwnerContentDraft = onCall(
  {region: "europe-west3", enforceAppCheck: false},
  async (request) => {
    const actor = await requireVerifiedActiveUser(request);
    assertOwner(actor.permissions);
    return archiveOwnerContentDraftForUser(
      actor.uid,
      parseOwnerContentDraftID(request.data)
    );
  }
);

function validatePayload(kind: DraftKind, payload: Record<string, unknown>): void {
  requiredString(payload.summary, "payload.summary", 200);
  stringArray(payload.tags, "payload.tags", 8, 30);
  const allowedCategories = kind === "news" ? newsCategories : eventCategories;
  const category = payload.category == null
    ? undefined
    : enumValue(payload.category, "payload.category", allowedCategories);
  const additionalCategories = stringArray(
    payload.additionalCategories,
    "payload.additionalCategories",
    2,
    60
  );
  if (additionalCategories.some((candidate) => !allowedCategories.has(candidate))) {
    throw new HttpsError("invalid-argument", "payload.additionalCategories contains an invalid category.");
  }
  if (new Set(additionalCategories).size !== additionalCategories.length) {
    throw new HttpsError("invalid-argument", "payload.additionalCategories must not contain duplicates.");
  }
  if (category && additionalCategories.includes(category)) {
    throw new HttpsError("invalid-argument", "Primary and additional categories must be distinct.");
  }
  if (category) payload.category = category;
  payload.additionalCategories = additionalCategories;
  optionalWebURL(payload.externalActionURL, "payload.externalActionURL");

  if (kind === "news") {
    requiredString(payload.body, "payload.body", 10_000);
    requiredString(payload.sourceInput, "payload.sourceInput", 2_048);
    const regionScope = payload.regionScope ?? "federalState";
    enumValue(regionScope, "payload.regionScope", new Set(["austria", "federalState"]));
    payload.regionScope = regionScope;
    if (regionScope === "federalState" && payload.federalState != null) {
      requiredString(payload.federalState, "payload.federalState", 80);
    }
    validatePublicationTiming(payload);
    return;
  }

  requiredString(payload.details, "payload.details", 2_000);
  requiredString(payload.city, "payload.city", 120);
  requiredString(payload.federalState, "payload.federalState", 80);
  if (!optionalString(payload.venue, 200) && !optionalString(payload.address, 300)) {
    throw new HttpsError("invalid-argument", "Event payload requires venue or address.");
  }
  const startDate = requiredDate(payload.startDate, "payload.startDate");
  const hasExplicitEndDate = payload.hasExplicitEndDate !== false;
  const endDate = hasExplicitEndDate
    ? requiredDate(payload.endDate, "payload.endDate")
    : payload.endDate == null ? startDate : requiredDate(payload.endDate, "payload.endDate");
  if (hasExplicitEndDate && endDate.getTime() <= startDate.getTime()) {
    throw new HttpsError("invalid-argument", "Event endDate must be later than startDate.");
  }
  if (!hasExplicitEndDate && endDate.getTime() < startDate.getTime()) {
    throw new HttpsError("invalid-argument", "Event endDate cannot be earlier than startDate.");
  }
  payload.startDate = Timestamp.fromDate(startDate);
  payload.endDate = Timestamp.fromDate(hasExplicitEndDate ? endDate : startDate);
  payload.hasExplicitEndDate = hasExplicitEndDate;
  optionalWebURL(payload.organizerURL, "payload.organizerURL");
  optionalWebURL(payload.contactURL, "payload.contactURL");
  validatePublicationTiming(payload);
}

function validatePublicationTiming(payload: Record<string, unknown>): void {
  const publicationMode = payload.publicationMode ?? "now";
  enumValue(publicationMode, "payload.publicationMode", new Set(["now", "scheduled"]));
  payload.publicationMode = publicationMode;
  if (publicationMode === "scheduled") {
    const scheduledAt = requiredDate(payload.scheduledAt, "payload.scheduledAt");
    if (scheduledAt.getTime() < Date.now() + 5 * 60 * 1000) {
      throw new HttpsError("invalid-argument", "payload.scheduledAt must be at least five minutes in the future.");
    }
    payload.scheduledAt = Timestamp.fromDate(scheduledAt);
  } else {
    delete payload.scheduledAt;
  }
}

function normalizedPayloadValue(key: string, value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (key === "scheduledAt") return value;
  if (key === "additionalOccurrences") {
    if (!Array.isArray(value) || value.length > 29) {
      throw new HttpsError("invalid-argument", "additionalOccurrences must contain at most 29 items.");
    }
    return value.map((item, index) => {
      const occurrence = record(item, `additionalOccurrences[${index}]`);
      const start = requiredDate(occurrence.startDate, `additionalOccurrences[${index}].startDate`);
      const end = occurrence.endDate == null
        ? start
        : requiredDate(occurrence.endDate, `additionalOccurrences[${index}].endDate`);
      if (end.getTime() < start.getTime()) {
        throw new HttpsError("invalid-argument", "Occurrence endDate cannot be earlier than startDate.");
      }
      return {
        startDate: Timestamp.fromDate(start),
        endDate: Timestamp.fromDate(end),
        isAllDay: occurrence.isAllDay === true,
      };
    });
  }
  if (Array.isArray(value)) return value.map((item) => primitive(item));
  return primitive(value);
}

function sourceArray(value: unknown): Array<Record<string, unknown>> {
  if (!Array.isArray(value) || value.length === 0 || value.length > 10) {
    throw new HttpsError("invalid-argument", "sources must contain between 1 and 10 items.");
  }
  const sources = value.map((item, index) => {
    const source = record(item, `sources[${index}]`) as unknown as SourceInput;
    const url = requiredWebURL(source.url, `sources[${index}].url`);
    return {
      url,
      title: optionalString(source.title, 300) ?? null,
      isPrimary: source.isPrimary === true,
      checkedAt: source.checkedAt ? Timestamp.fromDate(requiredDate(source.checkedAt, `sources[${index}].checkedAt`)) : null,
    };
  });
  if (sources.filter((source) => source.isPrimary).length !== 1) {
    throw new HttpsError("invalid-argument", "Exactly one source must be primary.");
  }
  return sources;
}

function optionalGeneratedImage(value: unknown): ParsedDraftInput["generatedImage"] {
  if (value === undefined || value === null) return undefined;
  const image = record(value, "generatedImage");
  const storagePath = requiredString(image.storagePath, "generatedImage.storagePath", 500);
  if (storagePath.startsWith("/") || storagePath.includes("..")) {
    throw new HttpsError("invalid-argument", "generatedImage.storagePath is invalid.");
  }
  const url = requiredWebURL(image.url, "generatedImage.url");
  if (new URL(url).protocol !== "https:") {
    throw new HttpsError("invalid-argument", "generatedImage.url must use HTTPS.");
  }
  return {
    url,
    storagePath,
    alternativeText: optionalString(image.alternativeText, 500),
    credit: optionalString(image.credit, 200),
  };
}

function record(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${field} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function requiredString(value: unknown, field: string, maxLength: number): string {
  const resolved = optionalString(value, maxLength);
  if (!resolved) throw new HttpsError("invalid-argument", `${field} is required.`);
  return resolved;
}

function optionalString(value: unknown, maxLength: number): string | undefined {
  if (value === null || value === undefined) return undefined;
  if (typeof value !== "string") throw new HttpsError("invalid-argument", "Expected a string.");
  const resolved = value.trim();
  if (resolved.length > maxLength) throw new HttpsError("invalid-argument", "String is too long.");
  return resolved.length > 0 ? resolved : undefined;
}

function stringArray(value: unknown, field: string, maxCount: number, maxLength: number): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > maxCount) {
    throw new HttpsError("invalid-argument", `${field} contains too many items.`);
  }
  return value.map((item) => requiredString(item, field, maxLength));
}

function enumValue<T extends string>(value: unknown, field: string, values: Set<T>): T {
  if (typeof value !== "string" || !values.has(value as T)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value as T;
}

function requiredDate(value: unknown, field: string): Date {
  if (typeof value !== "string") throw new HttpsError("invalid-argument", `${field} must be ISO 8601.`);
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || !/[zZ]|[+-]\d{2}:\d{2}$/.test(value)) {
    throw new HttpsError("invalid-argument", `${field} must include an explicit time zone.`);
  }
  return date;
}

function requiredWebURL(value: unknown, field: string): string {
  const resolved = requiredString(value, field, 2_048);
  let url: URL;
  try { url = new URL(resolved); } catch { throw new HttpsError("invalid-argument", `${field} is not a valid URL.`); }
  if ((url.protocol !== "https:" && url.protocol !== "http:") || !url.hostname) {
    throw new HttpsError("invalid-argument", `${field} must be an HTTP(S) URL.`);
  }
  return url.toString();
}

function optionalWebURL(value: unknown, field: string): void {
  if (value === undefined || value === null || value === "") return;
  requiredWebURL(value, field);
}

function primitive(value: unknown): unknown {
  if (["string", "number", "boolean"].includes(typeof value)) return value;
  throw new HttpsError("invalid-argument", "Payload values must be primitive or supported arrays.");
}
