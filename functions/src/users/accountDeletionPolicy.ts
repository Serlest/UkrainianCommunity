import type {DocumentData, WhereFilterOp} from "firebase-admin/firestore";

export const deletedUserID = "deleted";
export const deletedUserDisplayName = "Видалений користувач";

export type AccountDeletionPatch =
  | "auditActor"
  | "cancellationActor"
  | "auditTarget"
  | "commentAuthor"
  | "contentAuthor"
  | "dsaReporter"
  | "dsaDecisionActor"
  | "dsaAppealDecisionActor"
  | "dsaPreviousAppealDecisionActor"
  | "dsaPreviousDecisionActor"
  | "dsaTargetAuthor"
  | "feedbackDsaDecisionActor"
  | "feedbackLastMessageActor"
  | "feedbackMessageAuthor"
  | "feedbackReplyActor"
  | "legalAcceptance"
  | "organizationPhotoUploader"
  | "organizationReviewer"
  | "organizationSubmitter"
  | "systemLogActor"
  | "systemLogReviewer"
  | "systemLogTarget"
  | "userStatusUpdater";

export interface AccountDeletionFilter {
  field: string;
  operator: WhereFilterOp;
  value: unknown;
}

export interface AccountDeletionReferencePolicy {
  name: string;
  scope: "collection" | "collectionGroup";
  collection: string;
  field: string;
  operator: "==" | "array-contains";
  action: "anonymize" | "delete" | "removeArrayValue";
  patch?: AccountDeletionPatch;
  filters?: readonly AccountDeletionFilter[];
}

/**
 * Cross-document references that must be handled before the user document and
 * Firebase Auth identity are removed. The runtime consumes this list directly,
 * so the tested policy cannot drift away from the deletion implementation.
 */
export const accountDeletionReferencePolicies = [
  {name: "photo operation actors", scope: "collection", collection: "organizationPhotoOperations",
    field: "actorUserId", operator: "==", action: "anonymize", patch: "cancellationActor"},
  {name: "organization mutation receipts", scope: "collection", collection: "organizationMutationReceipts",
    field: "userId", operator: "==", action: "delete"},
  {name: "cancellation actors", scope: "collection", collection: "eventCancellationOperations",
    field: "actorUserId", operator: "==", action: "anonymize", patch: "cancellationActor"},
  {name: "cancellation recipients", scope: "collection", collection: "eventCancellationOperations",
    field: "recipients", operator: "array-contains", action: "removeArrayValue"},
  {
    name: "event authors",
    scope: "collection",
    collection: "events",
    field: "authorId",
    operator: "==",
    action: "anonymize",
    patch: "contentAuthor",
  },
  {
    name: "legacy news authors",
    scope: "collection",
    collection: "news",
    field: "authorId",
    operator: "==",
    action: "anonymize",
    patch: "contentAuthor",
  },
  {
    name: "comments",
    scope: "collectionGroup",
    collection: "comments",
    field: "authorId",
    operator: "==",
    action: "anonymize",
    patch: "commentAuthor",
  },
  {
    name: "organization administrators",
    scope: "collection",
    collection: "organizations",
    field: "adminIds",
    operator: "array-contains",
    action: "removeArrayValue",
  },
  {
    name: "organization moderators",
    scope: "collection",
    collection: "organizations",
    field: "moderatorIds",
    operator: "array-contains",
    action: "removeArrayValue",
  },
  {
    name: "organization submitters",
    scope: "collection",
    collection: "organizations",
    field: "submittedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "organizationSubmitter",
  },
  {
    name: "organization reviewers",
    scope: "collection",
    collection: "organizations",
    field: "reviewedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "organizationReviewer",
  },
  {
    name: "organization photo uploaders",
    scope: "collectionGroup",
    collection: "photos",
    field: "uploadedBy",
    operator: "==",
    action: "anonymize",
    patch: "organizationPhotoUploader",
  },
  {
    name: "DSA case reporters",
    scope: "collection",
    collection: "dsaCases",
    field: "reporterUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaReporter",
  },
  {
    name: "DSA case affected authors",
    scope: "collection",
    collection: "dsaCases",
    field: "targetAuthorId",
    operator: "==",
    action: "anonymize",
    patch: "dsaTargetAuthor",
  },
  {
    name: "DSA decision actors",
    scope: "collection",
    collection: "dsaCases",
    field: "decision.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaDecisionActor",
  },
  {
    name: "DSA appeal decision actors",
    scope: "collection",
    collection: "dsaCases",
    field: "appeal.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaAppealDecisionActor",
  },
  {
    name: "DSA previous decision actors",
    scope: "collection",
    collection: "dsaCases",
    field: "previousDecision.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaPreviousDecisionActor",
  },
  {
    name: "DSA previous appeal decision actors",
    scope: "collection",
    collection: "dsaCases",
    field: "previousAppeal.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaPreviousAppealDecisionActor",
  },
  {
    name: "feedback DSA decision actors",
    scope: "collection",
    collection: "feedback",
    field: "dsaCase.decision.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "feedbackDsaDecisionActor",
  },
  {
    name: "DSA statement decision actors",
    scope: "collectionGroup",
    collection: "dsaStatements",
    field: "decision.decidedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "dsaDecisionActor",
  },
  {
    name: "feedback reply actors",
    scope: "collection",
    collection: "feedback",
    field: "repliedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "feedbackReplyActor",
  },
  {
    name: "feedback latest message actors",
    scope: "collection",
    collection: "feedback",
    field: "lastMessageByUserId",
    operator: "==",
    action: "anonymize",
    patch: "feedbackLastMessageActor",
  },
  {
    name: "feedback messages written as a manager",
    scope: "collectionGroup",
    collection: "messages",
    field: "senderId",
    operator: "==",
    action: "anonymize",
    patch: "feedbackMessageAuthor",
  },
  {
    name: "notifications in other users' inboxes",
    scope: "collectionGroup",
    collection: "notificationInbox",
    field: "actorUserId",
    operator: "==",
    action: "delete",
  },
  {
    name: "user status update actors",
    scope: "collection",
    collection: "users",
    field: "statusUpdatedBy",
    operator: "==",
    action: "anonymize",
    patch: "userStatusUpdater",
  },
  {
    name: "legal acceptance records",
    scope: "collection",
    collection: "legalAcceptanceLogs",
    field: "userId",
    operator: "==",
    action: "anonymize",
    patch: "legalAcceptance",
  },
  {
    name: "audit targets",
    scope: "collection",
    collection: "auditLogs",
    field: "targetUserId",
    operator: "==",
    action: "anonymize",
    patch: "auditTarget",
  },
  {
    name: "audit actors",
    scope: "collection",
    collection: "auditLogs",
    field: "performedBy",
    operator: "==",
    action: "anonymize",
    patch: "auditActor",
  },
  {
    name: "system log actors",
    scope: "collection",
    collection: "systemLogs",
    field: "actorUserId",
    operator: "==",
    action: "anonymize",
    patch: "systemLogActor",
  },
  {
    name: "system log reviewers",
    scope: "collection",
    collection: "systemLogs",
    field: "reviewedByUserId",
    operator: "==",
    action: "anonymize",
    patch: "systemLogReviewer",
  },
  {
    name: "system log account targets",
    scope: "collection",
    collection: "systemLogs",
    field: "targetId",
    operator: "==",
    action: "anonymize",
    patch: "systemLogTarget",
    filters: [{field: "targetType", operator: "in", value: ["account", "userProfile"]}],
  },
] as const satisfies readonly AccountDeletionReferencePolicy[];

export function personalReferenceValues(
  uid: string,
  userData: DocumentData | undefined
): string[] {
  const candidates = [
    uid,
    userData?.email,
    userData?.displayName,
    userData?.fullName,
    userData?.telegramUsername,
    userData?.avatarURL,
  ];

  return Array.from(new Set(candidates
    .filter((value): value is string => typeof value === "string")
    .map((value) => value.trim())
    .filter((value) => value.length >= 3 && value !== deletedUserID)));
}

/** Redacts known identifiers in plain Firestore maps without damaging Timestamps. */
export function redactPersonalReferences(
  value: unknown,
  identifiers: readonly string[]
): unknown {
  if (typeof value === "string") {
    return identifiers.reduce(
      (redacted, identifier) => redacted.split(identifier).join(deletedUserID),
      value
    );
  }

  if (Array.isArray(value)) {
    return value.map((item) => redactPersonalReferences(item, identifiers));
  }

  if (!isPlainRecord(value)) {
    return value;
  }

  return Object.fromEntries(Object.entries(value).map(([key, item]) => [
    key,
    redactPersonalReferences(item, identifiers),
  ]));
}

export function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}
