import {dailyDocumentIDFor, datedAnalyticsDocumentIDs} from "./analyticsDate";

export const analyticsUserActivityCollection = "analyticsUserActivity";
export const analyticsDeletedUserEventCollection = "analyticsDeletedUserEvents";
export const analyticsUserRegistrationEventCollection = "analyticsUserRegistrationEvents";
export const analyticsUserLifecycleBaselineCollection = "analyticsUserLifecycleBaselines";
export const analyticsUserActivityRetentionDays = 60;
export const analyticsMaterializationPageSize = 250;
export const analyticsActivityLookupBatchSize = 100;
export const analyticsRegistrationFallbackLimit = 100_000;

export interface AnalyticsActivityWindows {
  today: boolean;
  sevenDays: boolean;
  thirtyDays: boolean;
}

export interface AnalyticsActivityWindowIndex {
  todayDocumentID: string;
  sevenDayDocumentIDs: readonly string[];
  thirtyDayDocumentIDs: readonly string[];
  sevenDayDocumentIDSet: ReadonlySet<string>;
  thirtyDayDocumentIDSet: ReadonlySet<string>;
}

export function analyticsActivityExpirationDate(now: Date): Date {
  return new Date(
    now.getTime() + analyticsUserActivityRetentionDays * 24 * 60 * 60 * 1_000
  );
}

export function latestAnalyticsActivityDate(
  current: Date | undefined,
  candidate: Date
): Date {
  return current !== undefined && current.getTime() > candidate.getTime()
    ? current
    : candidate;
}

export function analyticsActivityWindows(
  lastActiveAt: Date | undefined,
  now: Date,
  windowIndex: AnalyticsActivityWindowIndex = analyticsActivityWindowIndex(now)
): AnalyticsActivityWindows {
  if (lastActiveAt === undefined || lastActiveAt.getTime() > now.getTime()) {
    return {today: false, sevenDays: false, thirtyDays: false};
  }

  const activityDocumentID = dailyDocumentIDFor(lastActiveAt);
  return {
    today: activityDocumentID === windowIndex.todayDocumentID,
    sevenDays: windowIndex.sevenDayDocumentIDSet.has(activityDocumentID),
    thirtyDays: windowIndex.thirtyDayDocumentIDSet.has(activityDocumentID),
  };
}

/**
 * Builds all trailing-window identifiers once for an entire materialization
 * run. The seven-day window is a prefix of the thirty-day window, avoiding a
 * second calendar calculation and per-user Set allocations.
 */
export function analyticsActivityWindowIndex(
  now: Date
): AnalyticsActivityWindowIndex {
  const thirtyDayDocumentIDs = datedAnalyticsDocumentIDs(30, now);
  const sevenDayDocumentIDs = thirtyDayDocumentIDs.slice(0, 7);
  const todayDocumentID = thirtyDayDocumentIDs[0] ?? dailyDocumentIDFor(now);

  return {
    todayDocumentID,
    sevenDayDocumentIDs,
    thirtyDayDocumentIDs,
    sevenDayDocumentIDSet: new Set(sevenDayDocumentIDs),
    thirtyDayDocumentIDSet: new Set(thirtyDayDocumentIDs),
  };
}

/**
 * Splits exact-document lookups into predictable RPC-sized chunks. This keeps
 * memory and request payloads bounded even when a query page size changes.
 */
export function boundedAnalyticsBatches<T>(
  items: readonly T[],
  batchSize: number
): T[][] {
  if (!Number.isInteger(batchSize) || batchSize <= 0) {
    throw new RangeError("batchSize must be a positive integer.");
  }

  const batches: T[][] = [];
  for (let offset = 0; offset < items.length; offset += batchSize) {
    batches.push(items.slice(offset, offset + batchSize));
  }
  return batches;
}

/**
 * Retains only the recent-profile fallback needed to bridge registration
 * events from before the lifecycle ledger existed. Failing explicitly at the
 * cap is safer than exhausting the scheduler and publishing a partial total.
 */
export function setBoundedAnalyticsRegistrationFallback(
  fallbacks: Map<string, string>,
  userKey: string,
  analyticsDay: string,
  maximumEntries = analyticsRegistrationFallbackLimit
): void {
  if (!Number.isInteger(maximumEntries) || maximumEntries <= 0) {
    throw new RangeError("maximumEntries must be a positive integer.");
  }
  if (!fallbacks.has(userKey) && fallbacks.size >= maximumEntries) {
    throw new RangeError(
      `Analytics registration fallback limit ${maximumEntries} exceeded.`
    );
  }
  fallbacks.set(userKey, analyticsDay);
}

export function shouldUseAnalyticsRegistrationFallback(
  analyticsDay: string,
  registeredAt: Date,
  windowIndex: AnalyticsActivityWindowIndex,
  lifecycleCoverageByDay: ReadonlyMap<string, Date>
): boolean {
  if (!windowIndex.thirtyDayDocumentIDSet.has(analyticsDay)) {
    return false;
  }

  const coveredThrough = lifecycleCoverageByDay.get(analyticsDay);
  return coveredThrough === undefined ||
    registeredAt.getTime() > coveredThrough.getTime();
}

/**
 * A migration baseline owns every lifecycle event at or before its exact
 * coverage instant. Events delivered after that instant stay authoritative in
 * the immutable ledger. The strict `>` comparison makes the boundary
 * exhaustive without counting the same event twice.
 */
export function isAnalyticsLifecycleEventAfterCoverage(
  analyticsDay: string,
  occurredAt: Date,
  lifecycleCoverageByDay: ReadonlyMap<string, Date>
): boolean {
  const coveredThrough = lifecycleCoverageByDay.get(analyticsDay);
  return coveredThrough === undefined ||
    occurredAt.getTime() > coveredThrough.getTime();
}

/**
 * Returns the exclusive document-ID cursor for a full page. Short pages are
 * terminal; exact multiples intentionally perform one final empty read.
 */
export function nextAnalyticsScanCursor(
  documentIDs: readonly string[],
  pageSize: number
): string | undefined {
  if (!Number.isInteger(pageSize) || pageSize <= 0) {
    throw new RangeError("pageSize must be a positive integer.");
  }
  if (documentIDs.length > pageSize) {
    throw new RangeError("A scan page cannot exceed its configured page size.");
  }
  if (documentIDs.length < pageSize) {
    return undefined;
  }
  return documentIDs.at(-1);
}
