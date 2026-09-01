import {Timestamp} from "firebase-admin/firestore";

export const contentPlanningReceiptRetentionMonths = 6;
export const contentPlanningReceiptRetentionPolicy = "contentPlanningReceipt6Months";

export type ContentPlanningTerminalState = "completed" | "archived";
export type ContentPlanningPublishedKind = "news" | "event";

export type ContentPlanningDraftMediaCleanupDecision =
  | "deleteArchivedCopy"
  | "deleteRedundantCopy"
  | "noMedia"
  | "retainInvalidPath"
  | "retainLiveReference"
  | "retainMissingLiveContent"
  | "retainMissingLiveImage"
  | "retainUnresolved";

export interface ContentPlanningDraftMediaCleanupInput {
  state: string | undefined;
  draftStoragePath: string | undefined;
  expectedDraftPrefix: string;
  publishedContentId: string | undefined;
  publishedContentKind: string | undefined;
  liveContentExists: boolean;
  liveImagePath: string | undefined;
  liveImageExists: boolean;
  hasOtherLiveReference: boolean;
}

export function contentPlanningRetentionExpiresAt(base: Timestamp): Timestamp {
  const date = base.toDate();
  const originalDay = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + contentPlanningReceiptRetentionMonths);
  const lastDayOfTargetMonth = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth() + 1,
    0
  )).getUTCDate();
  date.setUTCDate(Math.min(originalDay, lastDayOfTargetMonth));
  return Timestamp.fromDate(date);
}

export function contentPlanningDraftImagePrefix(ownerUserId: string, draftId: string): string {
  if (!isSafeFirestoreDocumentId(ownerUserId) || !isSafeFirestoreDocumentId(draftId)) {
    throw new Error("Content planning media identifiers must be non-empty document IDs.");
  }
  return `users/${ownerUserId}/contentPlanningDraftImages/${draftId}/`;
}

export function contentPlanningDraftMediaCleanupDecision(
  input: ContentPlanningDraftMediaCleanupInput
): ContentPlanningDraftMediaCleanupDecision {
  if (input.state !== "completed" && input.state !== "archived") {
    return "retainUnresolved";
  }
  if (!input.draftStoragePath) return "noMedia";
  if (!input.draftStoragePath.startsWith(input.expectedDraftPrefix)) {
    return "retainInvalidPath";
  }
  if (input.state === "archived") {
    if (input.hasOtherLiveReference ||
        (input.liveContentExists && input.liveImagePath === input.draftStoragePath)) {
      return "retainLiveReference";
    }
    return "deleteArchivedCopy";
  }
  if (!input.publishedContentId ||
      (input.publishedContentKind !== "news" && input.publishedContentKind !== "event")) {
    return "retainUnresolved";
  }
  if (!input.liveContentExists) return "retainMissingLiveContent";
  if (!input.liveImagePath || !input.liveImageExists) return "retainMissingLiveImage";
  if (input.liveImagePath === input.draftStoragePath || input.hasOtherLiveReference) {
    return "retainLiveReference";
  }
  return "deleteRedundantCopy";
}

export function isContentPlanningTerminalState(
  value: unknown
): value is ContentPlanningTerminalState {
  return value === "completed" || value === "archived";
}

export function isContentPlanningPublishedKind(
  value: unknown
): value is ContentPlanningPublishedKind {
  return value === "news" || value === "event";
}

function isSafeFirestoreDocumentId(value: string): boolean {
  const normalized = value.trim();
  return normalized.length > 0 && !normalized.includes("/");
}
