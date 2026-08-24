import {datedAnalyticsDocumentIDs} from "./analyticsDate";

const preservedDocumentIDs = new Set(["today", "seven_days", "thirty_days"]);

export function shouldDeleteAggregateDocument(
  documentID: string,
  cutoffDocumentID: string,
): boolean {
  if (preservedDocumentIDs.has(documentID)) {
    return false;
  }

  const documentDate = dateFromDocumentID(documentID);
  const cutoffDate = dateFromDocumentID(cutoffDocumentID);
  return documentDate !== undefined
    && cutoffDate !== undefined
    && documentDate < cutoffDate;
}

/**
 * Returns the first Vienna calendar day that must be retained.
 *
 * A retention value of 60 keeps exactly 60 Vienna calendar IDs: the current
 * day and the preceding 59 days. Aggregate roots with earlier dated IDs are
 * eligible for cleanup. Calendar IDs keep 23/25-hour DST days from changing
 * the policy.
 */
export function aggregateRetentionCutoffDocumentID(
  now: Date,
  retentionDays: number,
): string {
  if (!Number.isInteger(retentionDays) || retentionDays <= 0) {
    throw new RangeError("retentionDays must be a positive integer");
  }

  const documentIDs = datedAnalyticsDocumentIDs(retentionDays, now);
  return documentIDs[retentionDays - 1];
}

export type AggregateCleanupPagePlan = {
  documentIDsToInspect: string[];
  nextCursor: string | undefined;
};

/**
 * Plans one bounded page from a query that requested pageSize + 1 documents.
 * The look-ahead document tells the caller whether another page exists without
 * requiring an additional read. The returned cursor always advances.
 */
export function planAggregateCleanupPage(
  orderedDocumentIDs: string[],
  pageSize: number,
): AggregateCleanupPagePlan {
  if (!Number.isInteger(pageSize) || pageSize <= 0) {
    throw new RangeError("pageSize must be a positive integer");
  }

  const documentIDsToInspect = orderedDocumentIDs.slice(0, pageSize);
  const hasMore = orderedDocumentIDs.length > pageSize;
  return {
    documentIDsToInspect,
    nextCursor: hasMore ? documentIDsToInspect.at(-1) : undefined,
  };
}

export function dateFromDocumentID(documentID: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(documentID);
  if (!match) {
    return undefined;
  }

  const [, yearValue, monthValue, dayValue] = match;
  const year = Number(yearValue);
  const month = Number(monthValue);
  const day = Number(dayValue);
  const date = new Date(Date.UTC(year, month - 1, day));

  if (
    date.getUTCFullYear() !== year
    || date.getUTCMonth() !== month - 1
    || date.getUTCDate() !== day
  ) {
    return undefined;
  }

  return date;
}
