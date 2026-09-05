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
  | "dsaTargetAuthor"
  | "feedbackMessageAuthor"
  | "legalAcceptance"
  | "organizationPhotoUploader"
  | "organizationReviewer"
  | "organizationSubmitter"
  | "systemLogActor"
  | "systemLogReviewer"
  | "systemLogTarget";

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

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}
