import {
  FieldPath,
  FieldValue,
  Timestamp,
  type DocumentData,
  type Query,
  type QueryDocumentSnapshot,
  type Transaction,
} from "firebase-admin/firestore";
import {
  onDocumentCreated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {defineBoolean} from "firebase-functions/params";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {assertActiveUser} from "../auth/context";
import {requireLegacyCallableUser as requireVerifiedActiveUser} from "../auth/legacyCallableContext";
import { db } from "../firebase/admin";
import {userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {
  analyticsActionProofCollection,
  analyticsActionReceiptID,
  isMatchingAnalyticsActionReceipt,
  optionalAnalyticsActionProofBinding,
  validateAnalyticsActionProof,
  type AnalyticsActionProofBinding,
} from "./analyticsActionProof";
import {
  analyticsConsentStateCollection, analyticsConsentReceiptCollection, analyticsConsentReceiptID,
  isCurrentAnalyticsConsent,
} from "./analyticsConsent";
import {dailyDocumentIDFor, datedAnalyticsDocumentIDs} from "./analyticsDate";
import {
  analyticsDetailCoverage,
  rollupAnalyticsDetailPeriods,
} from "./analyticsDetailRollup";
import {hasActiveRegionAnalytics} from "./analyticsRollupSanitization";
import {
  loadAnalyticsSchemaGateState,
  requireAnalyticsSchemaReady,
} from "./analyticsSchemaGate";
import {
  analyticsActivityLookupBatchSize,
  analyticsActivityExpirationDate,
  analyticsActivityWindowIndex,
  analyticsActivityWindows,
  analyticsDeletedUserEventCollection,
  analyticsMaterializationPageSize,
  analyticsUserRegistrationEventCollection,
  analyticsUserLifecycleBaselineCollection,
  analyticsUserActivityCollection,
  boundedAnalyticsBatches,
  isAnalyticsLifecycleEventAfterCoverage,
  latestAnalyticsActivityDate,
  nextAnalyticsScanCursor,
  setBoundedAnalyticsRegistrationFallback,
  shouldUseAnalyticsRegistrationFallback,
  type AnalyticsActivityWindowIndex,
} from "./analyticsUserActivity";
import {
  analyticsDeletionEventID,
  analyticsEventReceiptCollection,
  analyticsRateLimitID,
  analyticsRateLimitCollection,
  analyticsRegistrationEventID,
  analyticsRegistrationUserKey,
  analyticsReceiptID,
  analyticsReceiptRetentionHours,
  expirationDate,
  nextAnalyticsRateLimitState,
} from "./analyticsEventGuard";
import {
  resolveCanonicalAnalyticsContent,
  type AnalyticsContentType,
  type CanonicalAnalyticsContent,
} from "./canonicalAnalyticsContent";

type AnalyticsEventName =
  | "news_view"
  | "news_like"
  | "news_bookmark"
  | "event_view"
  | "event_register"
  | "event_bookmark"
  | "organization_view"
  | "organization_follow"
  | "organization_bookmark";

type AnalyticsEventKind = "view" | "action";

interface AnalyticsEventConfig {
  contentType: AnalyticsContentType;
  metricField: string;
  eventKind: AnalyticsEventKind;
  contentMetricField: string;
  organizationMetricField?: string;
  compatibilityMetricFields?: string[];
}

interface TrackAnalyticsEventRequest {
  name: AnalyticsEventName;
  parameters: Record<string, unknown>;
  consentID: string;
  actionProof?: AnalyticsActionProofBinding;
  occurredAtMilliseconds?: number;
}

interface AnalyticsActionProofDescriptor {
  documentPath: string;
  contentField: "newsId" | "eventId" | "organizationId" | "subscribedOrganizationId";
}

interface NormalizedAnalyticsRegion {
  regionScope: "austria" | "federalState";
  federalState?: string;
}

interface RateLimitedAnalyticsContentDependencies {
  consumeRateLimit: (uid: string, receivedAt: Date) => Promise<void>;
  resolveCanonicalContent: (
    contentType: AnalyticsContentType,
    contentID: string
  ) => Promise<CanonicalAnalyticsContent>;
}

interface SanitizedAnalyticsEvent {
  contentID: string;
  contentType: AnalyticsContentType;
  category?: string;
  organizationID?: string;
  organizationName?: string;
  federalState?: string;
  regionScope?: string;
  title: string;
  metricField: string;
  contentMetricField: string;
  organizationMetricField?: string;
  eventKind: AnalyticsEventKind;
  compatibilityMetricFields: string[];
}

interface RollupPeriod {
  documentID: "today" | "seven_days" | "thirty_days";
  dayCount: number;
}

export interface RollupTopContentItem {
  contentID: string;
  contentType: AnalyticsContentType;
  title: string;
  category?: string;
  organizationID?: string;
  organizationName?: string;
  federalState?: string;
  regionScope?: string;
  viewCount: number;
  rank: number;
}

interface RollupRegionStatsItem {
  regionScope: string;
  federalState?: string;
  viewCount: number;
  metrics: Map<string, number>;
}

const enforceAnalyticsAppCheck = defineBoolean(
  "ENFORCE_ANALYTICS_APP_CHECK",
  {default: false}
);

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
  // Release gate: keep the default false until App Attest/DeviceCheck metrics,
  // production registration, and CI debug-token coverage are verified.
  enforceAppCheck: enforceAnalyticsAppCheck,
};

const analyticsRollupScheduleOptions = {
  // Anchor materialization to the Vienna clock. A relative hourly schedule can
  // otherwise leave the new dated "today" documents missing for most of the
  // first hour after midnight while seven/thirty-day rollups still look valid.
  schedule: "1 * * * *",
  timeZone: "Europe/Vienna",
  region: "europe-west3",
  maxInstances: 1,
  // A detail generation rewrites and then prunes a shared materialized view.
  // Never allow two invocations to interleave inside the single instance.
  concurrency: 1,
  timeoutSeconds: 540,
  memory: "512MiB" as const,
};

const schema = {
  collections: {
    dailyStats: "analyticsDailyStats",
    topContent: "analyticsTopContent",
    regionStats: "analyticsRegionStats",
    contentStats: "analyticsContentStats",
    organizationStats: "analyticsOrganizationStats",
    userStats: "analyticsUserStats",
    userActivity: analyticsUserActivityCollection,
    registeredUserEvents: analyticsUserRegistrationEventCollection,
    userLifecycleBaselines: analyticsUserLifecycleBaselineCollection,
    deletedUserEvents: analyticsDeletedUserEventCollection,
    rollupState: "analyticsRollupState",
    eventReceipts: analyticsEventReceiptCollection,
    rateLimits: analyticsRateLimitCollection,
  },
  periodDocumentIDs: ["today", "seven_days", "thirty_days"],
  dailyStatsFields: {
    date: "date",
    metrics: "metrics",
    totalViews: "totalViews",
    totalActions: "totalActions",
    totalLikes: "totalLikes",
    totalBookmarks: "totalBookmarks",
    newsLikes: "newsLikes",
    newsBookmarks: "newsBookmarks",
    eventRegistrations: "eventRegistrations",
    eventCancelledRegistrations: "eventCancelledRegistrations",
    cancelledEventRegistrations: "cancelledEventRegistrations",
    eventBookmarks: "eventBookmarks",
    organizationFollows: "organizationFollows",
    organizationUnfollows: "organizationUnfollows",
    organizationBookmarks: "organizationBookmarks",
    activeRegions: "activeRegions",
  },
  topContentFields: {
    items: "items",
    itemsByKey: "itemsByKey",
    contentID: "contentID",
    contentType: "contentType",
    title: "title",
    category: "category",
    organizationID: "organizationID",
    organizationName: "organizationName",
    regionScope: "regionScope",
    federalState: "federalState",
    viewCount: "viewCount",
    rank: "rank",
  },
  regionStatsFields: {
    regions: "regions",
    regionsByKey: "regionsByKey",
    regionScope: "regionScope",
    federalState: "federalState",
    viewCount: "viewCount",
    contentCount: "contentCount",
    contentKeys: "contentKeys",
    metrics: "metrics",
  },
  detailStatsFields: {
    items: "items",
    organizations: "organizations",
    periodID: "periodId",
    contentID: "contentID",
    contentType: "contentType",
    contentTitle: "contentTitle",
    organizationID: "organizationID",
    organizationName: "organizationName",
    category: "category",
    regionScope: "regionScope",
    federalState: "federalState",
    metrics: "metrics",
    regionsByKey: "regionsByKey",
    topNews: "topNews",
    topEvents: "topEvents",
    updatedAt: "updatedAt",
  },
  rollupStateFields: {
    dateDocumentID: "dateDocumentID",
  },
  userStatsFields: {
    period: "period",
    generatedAt: "generatedAt",
    metrics: "metrics",
    totalUsers: "totalUsers",
    newRegistrations: "newRegistrations",
    deletedAccounts: "deletedAccounts",
    blockedUsers: "blockedUsers",
    deactivatedUsers: "deactivatedUsers",
    activeUsersToday: "activeUsersToday",
    activeUsersSevenDays: "activeUsersSevenDays",
    activeUsersThirtyDays: "activeUsersThirtyDays",
    activeToday: "activeToday",
    activeSevenDays: "activeSevenDays",
    activeThirtyDays: "activeThirtyDays",
    usersByFederalState: "usersByFederalState",
    sourceDocumentIDs: "sourceDocumentIDs",
    lifecycleCoverageStartDay: "lifecycleCoverageStartDay",
    coveredLifecycleSourceDocumentIDs: "coveredLifecycleSourceDocumentIDs",
    isLifecyclePartialCoverage: "isLifecyclePartialCoverage",
  },
} as const;

const eventConfigs: Record<AnalyticsEventName, AnalyticsEventConfig> = {
  news_view: {
    contentType: "news",
    metricField: "newsViews",
    eventKind: "view",
    contentMetricField: "views",
    organizationMetricField: "newsViews",
  },
  news_like: {
    contentType: "news",
    metricField: "newsLikes",
    eventKind: "action",
    contentMetricField: "likes",
    compatibilityMetricFields: ["totalLikes"],
  },
  news_bookmark: {
    contentType: "news",
    metricField: "newsBookmarks",
    eventKind: "action",
    contentMetricField: "bookmarks",
    compatibilityMetricFields: ["totalBookmarks"],
  },
  event_view: {
    contentType: "event",
    metricField: "eventViews",
    eventKind: "view",
    contentMetricField: "views",
    organizationMetricField: "eventViews",
  },
  event_register: {
    contentType: "event",
    metricField: "eventRegistrations",
    eventKind: "action",
    contentMetricField: "registrations",
    organizationMetricField: "eventRegistrations",
  },
  event_bookmark: {
    contentType: "event",
    metricField: "eventBookmarks",
    eventKind: "action",
    contentMetricField: "bookmarks",
    compatibilityMetricFields: ["totalBookmarks"],
  },
  organization_view: {
    contentType: "organization",
    metricField: "organizationViews",
    eventKind: "view",
    contentMetricField: "views",
    organizationMetricField: "profileViews",
  },
  organization_follow: {
    contentType: "organization",
    metricField: "organizationFollows",
    eventKind: "action",
    contentMetricField: "follows",
    organizationMetricField: "follows",
  },
  organization_bookmark: {
    contentType: "organization",
    metricField: "organizationBookmarks",
    eventKind: "action",
    contentMetricField: "bookmarks",
    organizationMetricField: "bookmarks",
    compatibilityMetricFields: ["totalBookmarks"],
  },
};

const activeRegionViewMetricFields = [
  "newsViews",
  "eventViews",
  "organizationViews",
] as const;

const federalStates = new Set([
  "burgenland",
  "kaernten",
  "niederoesterreich",
  "oberoesterreich",
  "salzburg",
  "steiermark",
  "tirol",
  "vorarlberg",
  "wien",
]);

const regionScopes = new Set([
  "austria",
  "federalState",
  "city",
]);

const allowedAnalyticsParameterNames = new Set([
  "content_id",
  "content_type",
  "content_title",
  "organization_id",
  "organization_name",
  "category",
  "federal_state",
  "region_scope",
  "is_guest",
  "account_state",
]);

const rollupPeriods: RollupPeriod[] = [
  {
    documentID: "today",
    dayCount: 1,
  },
  {
    documentID: "seven_days",
    dayCount: 7,
  },
  {
    documentID: "thirty_days",
    dayCount: 30,
  },
];

export const trackAnalyticsEvent = onCall(
  callableOptions,
  async (request): Promise<{ tracked: boolean }> => {
    const actor = await requireVerifiedActiveUser(request);
    // This read intentionally precedes parsing, rate-limit consumption,
    // canonical lookups, proofs, and aggregate writes. A prepared v1→v2
    // cutover therefore leaves the client outbox retryable without consuming
    // its attempt budget or opening a write window that finalize could erase.
    await requireAnalyticsSchemaReady(db);
    const receivedAt = new Date();

    const analyticsRequest = parseAnalyticsRequest(request.data);
    const requestedOccurredAt = analyticsEventDate(
      analyticsRequest.occurredAtMilliseconds,
      receivedAt
    );
    const config = eventConfigs[analyticsRequest.name];
    const contentID = requiredSafeID(
      analyticsRequest.parameters.content_id,
      "content_id"
    );
    const canonicalContent = await resolveRateLimitedAnalyticsContent(
      actor.uid,
      config.contentType,
      contentID,
      receivedAt
    );
    const analyticsEvent = sanitizeAnalyticsEvent(analyticsRequest, canonicalContent);
    if (analyticsRequest.actionProof === undefined) {
      await requireLegacyAnalyticsActionProof(
        actor.uid,
        analyticsRequest.name,
        analyticsEvent.contentID,
        requestedOccurredAt
      );
    }
    const tracked = await commitAnalyticsEvent(
      actor.uid,
      analyticsRequest.consentID,
      analyticsRequest.name,
      analyticsEvent,
      analyticsRequest.actionProof,
      requestedOccurredAt,
      receivedAt
    );

    return {tracked};
  }
);

export const rollupAnalyticsPeriods = onSchedule(
  analyticsRollupScheduleOptions,
  async () => {
    const schemaState = await analyticsSchemaStateForSchedule();
    if (schemaState === undefined) {
      return;
    }
    const anchor = new Date();
    await Promise.all([
      ...rollupPeriods.map((period) => rollupAnalyticsPeriod(period, anchor)),
      rollupAnalyticsDetailPeriods(
        db,
        rollupPeriods,
        anchor,
        schemaState.cutoverDay
      ),
    ]);
  }
);

export const rollupUserAnalyticsStats = onSchedule(
  analyticsRollupScheduleOptions,
  async () => {
    const schemaState = await analyticsSchemaStateForSchedule();
    if (schemaState === undefined) {
      return;
    }
    await materializeUserAnalyticsStats(schemaState.cutoverDay);
  }
);

async function analyticsSchemaStateForSchedule() {
  const state = await loadAnalyticsSchemaGateState(db);
  const isReady = state?.status === "complete";
  if (!isReady) {
    logger.warn("Analytics materialization paused for schema transition.", {
      schemaVersion: state?.schemaVersion ?? null,
      cutoverStatus: state?.status ?? "missing-or-invalid",
    });
  }
  return isReady ? state : undefined;
}

export const trackDeletedUserAnalyticsAggregate = onDocumentDeleted(
  {
    document: "users/{userID}",
    region: "europe-west3",
    maxInstances: 10,
    retry: true,
  },
  async (event) => {
    const eventTime = new Date(event.time);
    const now = Number.isFinite(eventTime.getTime()) ? eventTime : new Date();
    const datedDocumentID = dailyDocumentIDFor(now);
    const eventReference = db
      .collection(schema.collections.deletedUserEvents)
      .doc(analyticsDeletionEventID(event.id));

    await Promise.all([
      eventReference.set({
        analyticsDay: datedDocumentID,
        deletedAt: Timestamp.fromDate(now),
        expiresAt: Timestamp.fromDate(analyticsActivityExpirationDate(now)),
      }),
      db.collection(schema.collections.userActivity).doc(event.params.userID).delete(),
    ]);
  }
);

export const trackRegisteredUserAnalyticsAggregate = onDocumentCreated(
  {
    document: "users/{userID}",
    region: "europe-west3",
    maxInstances: 10,
    retry: true,
  },
  async (event) => {
    // The profile's immutable createdAt is also used by the migration
    // baseline. Using CloudEvent delivery time here would put one account on
    // opposite sides of the cutover boundary when delivery is delayed.
    const registeredAt = dateValue(event.data?.data().createdAt);
    if (registeredAt === undefined) {
      throw new Error("Created user profile is missing an immutable createdAt timestamp.");
    }
    const eventReference = db
      .collection(schema.collections.registeredUserEvents)
      .doc(analyticsRegistrationEventID(event.id));

    await eventReference.set({
      analyticsDay: dailyDocumentIDFor(registeredAt),
      registeredAt: Timestamp.fromDate(registeredAt),
      userKey: analyticsRegistrationUserKey(event.params.userID),
      expiresAt: Timestamp.fromDate(analyticsActivityExpirationDate(registeredAt)),
    });
  }
);

export function parseAnalyticsRequest(data: unknown): TrackAnalyticsEventRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const allowedFields = new Set([
    "name",
    "parameters",
    "consentID",
    "actionProof",
    "occurredAtMilliseconds",
  ]);
  if (!("name" in data)
    || !("parameters" in data)
    || !("consentID" in data)
    || Object.keys(data).some((field) => !allowedFields.has(field))) {
    throw new HttpsError("invalid-argument", "Request payload has unsupported fields.");
  }

  const name = parseEventName(data.name);
  const parameters = data.parameters;
  if (!isRecord(parameters)) {
    throw new HttpsError("invalid-argument", "parameters must be an object.");
  }

  return {
    name,
    parameters,
    consentID: requiredConsentID(data.consentID),
    actionProof: optionalAnalyticsActionProofBinding(data.actionProof),
    occurredAtMilliseconds: optionalTimestampMilliseconds(
      data.occurredAtMilliseconds
    ),
  };
}

export async function resolveRateLimitedAnalyticsContent(
  uid: string,
  contentType: AnalyticsContentType,
  contentID: string,
  receivedAt: Date,
  dependencies: RateLimitedAnalyticsContentDependencies = {
    consumeRateLimit: consumeAnalyticsRateLimit,
    resolveCanonicalContent: resolveCanonicalAnalyticsContent,
  }
): Promise<CanonicalAnalyticsContent> {
  // Consume the attempt budget before the canonical Firestore lookup. This
  // prevents forged/missing content IDs from creating unmetered document reads.
  await dependencies.consumeRateLimit(uid, receivedAt);
  return dependencies.resolveCanonicalContent(contentType, contentID);
}

export function analyticsEventDate(
  occurredAtMilliseconds: number | undefined,
  receivedAt: Date
): Date {
  if (occurredAtMilliseconds === undefined) {
    return receivedAt;
  }

  const occurredAt = new Date(occurredAtMilliseconds);
  const maximumFutureSkewMilliseconds = 5 * 60 * 1_000;
  const maximumDeliveryDelayMilliseconds = 48 * 60 * 60 * 1_000;
  if (!Number.isFinite(occurredAt.getTime())
    || occurredAt.getTime() > receivedAt.getTime() + maximumFutureSkewMilliseconds
    || occurredAt.getTime() < receivedAt.getTime() - maximumDeliveryDelayMilliseconds) {
    throw new HttpsError(
      "invalid-argument",
      "occurredAtMilliseconds is outside the accepted delivery window."
    );
  }

  return occurredAt;
}

export function analyticsActionProofDescriptor(
  eventName: AnalyticsEventName,
  uid: string,
  contentID: string
): AnalyticsActionProofDescriptor | undefined {
  switch (eventName) {
    case "news_like":
      return {
        documentPath: `likes/${contentID}_${uid}`,
        contentField: "newsId",
      };
    case "news_bookmark":
      return {
        documentPath: `users/${uid}/newsBookmarks/${contentID}`,
        contentField: "newsId",
      };
    case "event_register":
      return {
        documentPath: `registrations/event_${contentID}_${uid}`,
        contentField: "eventId",
      };
    case "event_bookmark":
      return {
        documentPath: `users/${uid}/eventBookmarks/${contentID}`,
        contentField: "eventId",
      };
    case "organization_follow":
      return {
        documentPath: `likes/organization_follow_${contentID}_${uid}`,
        contentField: "subscribedOrganizationId",
      };
    case "organization_bookmark":
      return {
        documentPath: `users/${uid}/organizationBookmarks/${contentID}`,
        contentField: "organizationId",
      };
    case "news_view":
    case "event_view":
    case "organization_view":
      return undefined;
  }
}

export function isValidAnalyticsActionProof(
  data: DocumentData | undefined,
  descriptor: AnalyticsActionProofDescriptor,
  uid: string,
  contentID: string,
  occurredAt: Date
): boolean {
  if (data === undefined
    || data.userId !== uid
    || data[descriptor.contentField] !== contentID) {
    return false;
  }

  const createdAt = dateValue(data.createdAt);
  return createdAt !== undefined
    && dailyDocumentIDFor(createdAt) === dailyDocumentIDFor(occurredAt);
}

async function requireLegacyAnalyticsActionProof(
  uid: string,
  eventName: AnalyticsEventName,
  contentID: string,
  occurredAt: Date
): Promise<void> {
  const descriptor = analyticsActionProofDescriptor(eventName, uid, contentID);
  if (descriptor === undefined) {
    return;
  }

  const snapshot = await db.doc(descriptor.documentPath).get();
  if (!snapshot.exists || !isValidAnalyticsActionProof(
    snapshot.data(),
    descriptor,
    uid,
    contentID,
    occurredAt
  )) {
    throw new HttpsError(
      "failed-precondition",
      "The tracked action could not be verified."
    );
  }
}

export function sanitizeAnalyticsEvent(
  request: TrackAnalyticsEventRequest,
  canonicalContent: CanonicalAnalyticsContent
): SanitizedAnalyticsEvent {
  validateAllowedParameterNames(request.parameters);
  const config = eventConfigs[request.name];
  const contentID = requiredSafeID(request.parameters.content_id, "content_id");
  if (contentID !== canonicalContent.contentID || config.contentType !== canonicalContent.contentType) {
    throw new HttpsError("internal", "Canonical analytics content is inconsistent.");
  }
  validateOptionalContentType(request.parameters.content_type, config.contentType);
  optionalSlug(request.parameters.category, "category");
  optionalSafeID(request.parameters.organization_id, "organization_id");
  optionalFederalState(request.parameters.federal_state);
  optionalRegionScope(request.parameters.region_scope);
  validateOptionalGuestFlag(request.parameters.is_guest);
  optionalSlug(request.parameters.account_state, "account_state");
  optionalSafeTitle(request.parameters.content_title, "content_title");
  optionalSafeTitle(
    request.parameters.organization_name,
    "organization_name"
  );

  return {
    ...canonicalContent,
    metricField: config.metricField,
    contentMetricField: config.contentMetricField,
    organizationMetricField: config.organizationMetricField,
    eventKind: config.eventKind,
    compatibilityMetricFields: config.compatibilityMetricFields ?? [],
  };
}

function parseEventName(value: unknown): AnalyticsEventName {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "name must be a string.");
  }

  if (isAnalyticsEventName(value)) {
    return value;
  }

  throw new HttpsError("invalid-argument", "Analytics event is not supported.");
}

function isAnalyticsEventName(value: string): value is AnalyticsEventName {
  return Object.prototype.hasOwnProperty.call(eventConfigs, value);
}

function validateAllowedParameterNames(parameters: Record<string, unknown>): void {
  for (const parameterName of Object.keys(parameters)) {
    if (!allowedAnalyticsParameterNames.has(parameterName)) {
      throw new HttpsError("invalid-argument", `${parameterName} is not supported.`);
    }
  }
}

function validateOptionalContentType(
  value: unknown,
  expectedContentType: AnalyticsContentType
): void {
  if (value === undefined || value === null) {
    return;
  }

  const contentType = analyticsContentType(value);
  if (contentType === undefined || contentType !== expectedContentType) {
    throw new HttpsError("invalid-argument", "content_type is not valid for this event.");
  }
}

function validateOptionalGuestFlag(value: unknown): void {
  if (value === undefined || value === null) {
    return;
  }

  if (typeof value === "boolean") {
    return;
  }

  if (typeof value === "string" && (value === "true" || value === "false")) {
    return;
  }

  throw new HttpsError("invalid-argument", "is_guest must be a boolean value.");
}

function optionalTimestampMilliseconds(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "number"
    || !Number.isSafeInteger(value)
    || value <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "occurredAtMilliseconds must be a positive integer."
    );
  }

  return value;
}

async function consumeAnalyticsRateLimit(uid: string, receivedAt: Date): Promise<void> {
  const reference = db.collection(schema.collections.rateLimits).doc(
    analyticsRateLimitID(uid, receivedAt)
  );

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const state = nextAnalyticsRateLimitState(snapshot.data()?.count, receivedAt);

    transaction.set(reference, {
      count: state.count,
      bucketStartedAt: Timestamp.fromDate(state.bucketStartedAt),
      updatedAt: Timestamp.fromDate(state.updatedAt),
      expiresAt: Timestamp.fromDate(state.expiresAt),
    });
  });
}

async function commitAnalyticsEvent(
  uid: string,
  consentID: string,
  eventName: AnalyticsEventName,
  analyticsEvent: SanitizedAnalyticsEvent,
  actionProof: AnalyticsActionProofBinding | undefined,
  requestedOccurredAt: Date,
  receivedAt: Date
): Promise<boolean> {
  const activityReference = db.collection(schema.collections.userActivity).doc(uid);
  const userReference = db.collection("users").doc(uid);
  const consentReference = db.collection(analyticsConsentStateCollection).doc(uid);
  const proofReference = actionProof === undefined
    ? undefined
    : db.collection(analyticsActionProofCollection).doc(actionProof.proofID);
  const actionReceiptReference = actionProof === undefined
    ? undefined
    : db.collection(schema.collections.eventReceipts)
      .doc(analyticsActionReceiptID(actionProof.proofID));

  return db.runTransaction(async (transaction) => {
    // Re-read the profile inside the same transaction as the activity marker.
    // Account deletion first mutates and then deletes this document, which now
    // conflicts with an in-flight analytics write and prevents a UID-keyed
    // marker from being recreated after deletion.
    const [userSnapshot, consentSnapshot, consentReceipt] = await transaction.getAll(
      userReference,
      consentReference,
      db.collection(analyticsConsentReceiptCollection).doc(analyticsConsentReceiptID(uid, consentID))
    );
    assertAnalyticsUserProfileActive(uid, userSnapshot.exists, userSnapshot.data());
    if (!isCurrentAnalyticsConsent(consentSnapshot.data(), consentID)
      || consentReceipt.get("enabled") !== true || consentReceipt.get("withdrawnAt") != null) {
      throw new HttpsError(
        "failed-precondition",
        "A current server-recorded analytics consent is required."
      );
    }

    let occurredAt = requestedOccurredAt;
    if (actionProof !== undefined && actionReceiptReference !== undefined) {
      const actionReceiptSnapshot = await transaction.get(actionReceiptReference);
      if (actionReceiptSnapshot.exists) {
        if (!isMatchingAnalyticsActionReceipt(
          actionReceiptSnapshot.data(),
          actionProof,
          uid,
          analyticsEvent.contentType
        )) {
          throw new HttpsError("already-exists", "The analytics proof receipt conflicts.");
        }
        return false;
      }
      if (proofReference === undefined) {
        throw new HttpsError("internal", "Analytics proof reference is unavailable.");
      }
      const proofSnapshot = await transaction.get(proofReference);
      occurredAt = validateAnalyticsActionProof(
        proofSnapshot.data(),
        actionProof,
        uid,
        consentID,
        receivedAt
      ).createdAt;
    }

    const dailyDocumentID = dailyDocumentIDFor(occurredAt);
    const receiptReference = db.collection(schema.collections.eventReceipts).doc(
      analyticsReceiptID(
        uid,
        dailyDocumentID,
        eventName,
        analyticsEvent.contentType,
        analyticsEvent.contentID
      )
    );
    const receiptSnapshot = await transaction.get(receiptReference);
    const activitySnapshot = await transaction.get(activityReference);
    const lastActiveAt = latestAnalyticsActivityDate(
      dateValue(activitySnapshot.data()?.lastActiveAt),
      occurredAt
    );

    // This server-only marker powers active-user aggregates without using
    // profile edits as a proxy for activity. It contains no event or content data.
    transaction.set(activityReference, {
      lastActiveAt: Timestamp.fromDate(lastActiveAt),
      updatedAt: Timestamp.fromDate(receivedAt),
      expiresAt: Timestamp.fromDate(analyticsActivityExpirationDate(lastActiveAt)),
    }, {merge: true});

    if (actionProof !== undefined
      && proofReference !== undefined
      && actionReceiptReference !== undefined) {
      transaction.create(actionReceiptReference, {
        receiptKind: "actionProof",
        proofId: actionProof.proofID,
        actorBinding: actionProof.actorBinding,
        eventName: actionProof.eventName,
        contentType: analyticsEvent.contentType,
        contentID: actionProof.contentID,
        sessionBinding: actionProof.sessionBinding,
        createdAt: Timestamp.fromDate(receivedAt),
        expiresAt: Timestamp.fromMillis(receivedAt.getTime() + 48 * 60 * 60 * 1_000),
      });
      transaction.delete(proofReference);
    }

    if (receiptSnapshot.exists) {
      return false;
    }

    transaction.set(receiptReference, {
      eventName,
      contentType: analyticsEvent.contentType,
      contentID: analyticsEvent.contentID,
      analyticsDay: dailyDocumentID,
      occurredAt: Timestamp.fromDate(occurredAt),
      createdAt: Timestamp.fromDate(receivedAt),
      expiresAt: Timestamp.fromDate(
        expirationDate(receivedAt, analyticsReceiptRetentionHours)
      ),
    });

    updateDailyStats(transaction, dailyDocumentID, occurredAt, analyticsEvent);
    updateContentDetailStats(transaction, dailyDocumentID, analyticsEvent);

    if (analyticsEvent.organizationID !== undefined) {
      updateOrganizationDetailStats(transaction, dailyDocumentID, analyticsEvent);
    }

    if (analyticsEvent.eventKind === "view") {
      updateTopContent(transaction, dailyDocumentID, analyticsEvent);
      updateRegionStats(transaction, dailyDocumentID, analyticsEvent);
    }

    return true;
  });
}

function requiredConsentID(value: unknown): string {
  if (typeof value !== "string"
    || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new HttpsError("invalid-argument", "consentID is invalid.");
  }
  return value;
}

export function assertAnalyticsUserProfileActive(
  uid: string,
  exists: boolean,
  data: DocumentData | undefined
): void {
  if (!exists) {
    throw new HttpsError("permission-denied", "User profile does not exist.");
  }
  assertActiveUser(userPermissionSnapshotFromData(uid, data));
}

function updateDailyStats(
  transaction: Transaction,
  dailyDocumentID: string,
  occurredAt: Date,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const dailyStatsReference = db
    .collection(schema.collections.dailyStats)
    .doc(dailyDocumentID);

  const metrics: DocumentData = {
    [analyticsEvent.metricField]: FieldValue.increment(1),
  };
  for (const metricField of analyticsEvent.compatibilityMetricFields) {
    metrics[metricField] = FieldValue.increment(1);
  }

  if (analyticsEvent.eventKind === "view") {
    metrics[schema.dailyStatsFields.totalViews] = FieldValue.increment(1);
  } else {
    metrics[schema.dailyStatsFields.totalActions] = FieldValue.increment(1);
  }

  const data: DocumentData = {
    [schema.dailyStatsFields.date]: Timestamp.fromDate(occurredAt),
    updatedAt: FieldValue.serverTimestamp(),
    [schema.dailyStatsFields.metrics]: metrics,
  };
  const regionKey = analyticsRegionKey(analyticsEvent);

  if (analyticsEvent.eventKind === "view" && regionKey !== undefined) {
    data.activeRegionKeys = {
      [regionKey]: true,
    };
  }

  transaction.set(dailyStatsReference, data, {merge: true});
}

function updateContentDetailStats(
  transaction: Transaction,
  dailyDocumentID: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const parentReference = db
    .collection(schema.collections.contentStats)
    .doc(dailyDocumentID);
  const reference = parentReference
    .collection(schema.detailStatsFields.items)
    .doc(contentMapKey(analyticsEvent));
  const data: DocumentData = {
    [schema.detailStatsFields.periodID]: dailyDocumentID,
    [schema.detailStatsFields.contentID]: analyticsEvent.contentID,
    [schema.detailStatsFields.contentType]: analyticsEvent.contentType,
    [schema.detailStatsFields.contentTitle]: analyticsEvent.title,
    [schema.detailStatsFields.metrics]: {
      [analyticsEvent.contentMetricField]: FieldValue.increment(1),
    },
    [schema.detailStatsFields.updatedAt]: FieldValue.serverTimestamp(),
  };

  addOptionalDetailMetadata(data, analyticsEvent);
  addRegionDetailMetrics(data, analyticsEvent.contentMetricField, analyticsEvent);

  transaction.set(parentReference, {
    [schema.detailStatsFields.periodID]: dailyDocumentID,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  transaction.set(reference, data, {merge: true});
}

function updateOrganizationDetailStats(
  transaction: Transaction,
  dailyDocumentID: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  if (analyticsEvent.organizationID === undefined) {
    return;
  }

  const organizationMetricField = analyticsEvent.organizationMetricField;
  const parentReference = db
    .collection(schema.collections.organizationStats)
    .doc(dailyDocumentID);
  const reference = parentReference
    .collection(schema.detailStatsFields.organizations)
    .doc(analyticsEvent.organizationID);
  const data: DocumentData = {
    [schema.detailStatsFields.periodID]: dailyDocumentID,
    [schema.detailStatsFields.organizationID]: analyticsEvent.organizationID,
    [schema.detailStatsFields.updatedAt]: FieldValue.serverTimestamp(),
  };

  data[schema.detailStatsFields.organizationName] =
    analyticsEvent.organizationName ?? null;
  data[schema.detailStatsFields.regionScope] =
    analyticsEvent.regionScope ?? null;
  data[schema.detailStatsFields.federalState] =
    analyticsEvent.federalState ?? null;

  if (organizationMetricField !== undefined) {
    data[schema.detailStatsFields.metrics] = {
      [organizationMetricField]: FieldValue.increment(1),
    };
    addRegionDetailMetrics(data, organizationMetricField, analyticsEvent);
  }

  addOrganizationTopContent(data, analyticsEvent);

  transaction.set(parentReference, {
    [schema.detailStatsFields.periodID]: dailyDocumentID,
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  transaction.set(reference, data, {merge: true});
}

function addOptionalDetailMetadata(
  data: DocumentData,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  // These maps are updated with merge semantics throughout a Vienna day.
  // Writing an explicit null is the tombstone for canonical metadata that was
  // removed or became inapplicable; omitting the key would preserve stale data.
  data[schema.detailStatsFields.category] = analyticsEvent.category ?? null;
  data[schema.detailStatsFields.organizationID] =
    analyticsEvent.organizationID ?? null;
  data[schema.detailStatsFields.organizationName] =
    analyticsEvent.organizationName ?? null;
  data[schema.detailStatsFields.regionScope] =
    analyticsEvent.regionScope ?? null;
  data[schema.detailStatsFields.federalState] =
    analyticsEvent.federalState ?? null;
}

function addRegionDetailMetrics(
  data: DocumentData,
  metricField: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const normalizedRegion = normalizeAnalyticsRegion(
    analyticsEvent.regionScope,
    analyticsEvent.federalState
  );
  const regionKey = analyticsRegionKey(analyticsEvent);
  if (normalizedRegion === undefined || regionKey === undefined) {
    return;
  }

  const region: DocumentData = {
    [schema.detailStatsFields.regionScope]: normalizedRegion.regionScope,
    [schema.detailStatsFields.metrics]: {
      [metricField]: FieldValue.increment(1),
    },
  };

  if (normalizedRegion.federalState !== undefined) {
    region[schema.detailStatsFields.federalState] = normalizedRegion.federalState;
  }

  data[schema.detailStatsFields.regionsByKey] = {
    [regionKey]: region,
  };
}

function addOrganizationTopContent(
  data: DocumentData,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  if (analyticsEvent.eventKind !== "view"
    || (analyticsEvent.contentType !== "news" && analyticsEvent.contentType !== "event")) {
    return;
  }

  const field = analyticsEvent.contentType === "news"
    ? schema.detailStatsFields.topNews
    : schema.detailStatsFields.topEvents;
  const item: DocumentData = {
    [schema.detailStatsFields.contentID]: analyticsEvent.contentID,
    [schema.detailStatsFields.contentType]: analyticsEvent.contentType,
    [schema.detailStatsFields.contentTitle]: analyticsEvent.title,
    [schema.detailStatsFields.metrics]: {
      [analyticsEvent.contentMetricField]: FieldValue.increment(1),
    },
  };

  item[schema.detailStatsFields.category] = analyticsEvent.category ?? null;
  item[schema.detailStatsFields.regionScope] =
    analyticsEvent.regionScope ?? null;
  item[schema.detailStatsFields.federalState] =
    analyticsEvent.federalState ?? null;

  data[field] = {
    [contentMapKey(analyticsEvent)]: item,
  };
}

function updateTopContent(
  transaction: Transaction,
  dailyDocumentID: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const reference = db
    .collection(schema.collections.topContent)
    .doc(dailyDocumentID);
  const item: DocumentData = {
    [schema.topContentFields.contentID]: analyticsEvent.contentID,
    [schema.topContentFields.contentType]: analyticsEvent.contentType,
    [schema.topContentFields.title]: analyticsEvent.title,
    [schema.topContentFields.viewCount]: FieldValue.increment(1),
  };

  item[schema.topContentFields.category] = analyticsEvent.category ?? null;
  item[schema.topContentFields.organizationID] =
    analyticsEvent.organizationID ?? null;
  item[schema.topContentFields.organizationName] =
    analyticsEvent.organizationName ?? null;
  item[schema.topContentFields.regionScope] =
    analyticsEvent.regionScope ?? null;
  item[schema.topContentFields.federalState] =
    analyticsEvent.federalState ?? null;

  transaction.set(reference, {
    [schema.rollupStateFields.dateDocumentID]: dailyDocumentID,
    [schema.topContentFields.itemsByKey]: {
      [contentMapKey(analyticsEvent)]: item,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

function updateRegionStats(
  transaction: Transaction,
  dailyDocumentID: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const normalizedRegion = normalizeAnalyticsRegion(
    analyticsEvent.regionScope,
    analyticsEvent.federalState
  );
  const regionKey = analyticsRegionKey(analyticsEvent);
  if (normalizedRegion === undefined || regionKey === undefined) {
    return;
  }

  const reference = db
    .collection(schema.collections.regionStats)
    .doc(dailyDocumentID);
  const region: DocumentData = {
    [schema.regionStatsFields.regionScope]: normalizedRegion.regionScope,
    [schema.regionStatsFields.viewCount]: FieldValue.increment(1),
    [schema.regionStatsFields.metrics]: {
      [schema.dailyStatsFields.totalViews]: FieldValue.increment(1),
      [analyticsEvent.metricField]: FieldValue.increment(1),
    },
  };

  if (normalizedRegion.federalState !== undefined) {
    region[schema.regionStatsFields.federalState] = normalizedRegion.federalState;
  }

  transaction.set(reference, {
    [schema.rollupStateFields.dateDocumentID]: dailyDocumentID,
    [schema.regionStatsFields.regionsByKey]: {
      [regionKey]: region,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function rollupAnalyticsPeriod(
  period: RollupPeriod,
  anchor: Date
): Promise<void> {
  const sourceDocumentIDs = datedAnalyticsDocumentIDs(period.dayCount, anchor);
  const [topContent, regionStats] = await Promise.all([
    loadTopContentRollup(sourceDocumentIDs),
    loadRegionStatsRollup(sourceDocumentIDs),
  ]);
  const batch = db.batch();

  // Seven-day and thirty-day documents are derived rollups. They are refreshed
  // on a schedule instead of being updated on every view event.
  batch.set(
    db.collection(schema.collections.topContent).doc(period.documentID),
    {
      [schema.topContentFields.items]: rankedTopContentItems(topContent),
      [schema.topContentFields.itemsByKey]: topContentMap(topContent),
      sourceDocumentIDs,
      updatedAt: FieldValue.serverTimestamp(),
    }
  );

  batch.set(
    db.collection(schema.collections.regionStats).doc(period.documentID),
    {
      [schema.regionStatsFields.regions]: rankedRegionStats(regionStats),
      [schema.regionStatsFields.regionsByKey]: regionStatsMap(regionStats),
      sourceDocumentIDs,
      updatedAt: FieldValue.serverTimestamp(),
    }
  );

  await batch.commit();
}

async function materializeUserAnalyticsStats(
  lifecycleCoverageStartDay: string
): Promise<void> {
  const now = new Date();
  const windowIndex = analyticsActivityWindowIndex(now);
  const currentDatedDocumentID = windowIndex.todayDocumentID;
  const todayDocumentID = schema.periodDocumentIDs[0];
  let baseStats = emptyUserAnalyticsBaseStats();
  const fallbackRegistrationDayByUserKey = new Map<string, string>();
  const lifecycleBaselineSnapshots = await db.getAll(
    ...windowIndex.thirtyDayDocumentIDs.map((documentID) => db
      .collection(schema.collections.userLifecycleBaselines)
      .doc(documentID))
  );
  const lifecycleBaselines = lifecycleBaselineSnapshots.flatMap((snapshot) => {
    if (!snapshot.exists) {
      return [];
    }
    const data = snapshot.data();
    const newRegistrations = requiredLifecycleBaselineCount(
      data?.newRegistrations,
      snapshot.id,
      "newRegistrations"
    );
    const deletedAccounts = requiredLifecycleBaselineCount(
      data?.deletedAccounts,
      snapshot.id,
      "deletedAccounts"
    );
    const coveredThrough = dateValue(data?.coveredThrough);
    if (data?.schemaVersion !== 2 || data?.analyticsDay !== snapshot.id ||
      coveredThrough === undefined) {
      throw new Error(`Analytics lifecycle baseline ${snapshot.id} is malformed.`);
    }
    return [{
      analyticsDay: snapshot.id,
      newRegistrations,
      deletedAccounts,
      coveredThrough,
    }];
  });
  const lifecycleCoverageByDay = new Map(
    lifecycleBaselines.map((baseline) => [
      baseline.analyticsDay,
      baseline.coveredThrough,
    ] as const)
  );

  // User profiles are streamed in stable document-ID order. Activity is read
  // only for the current page, so neither collection is ever loaded into one
  // unbounded snapshot or retained in memory for the whole run.
  await forEachAnalyticsScanPage(
    db.collection("users")
      .select("createdAt", "accountStatus", "blockState", "selectedFederalState"),
    async (documents) => {
      const activityByUserID = await loadAnalyticsActivityByUserID(
        documents.map((document) => document.id)
      );
      const users = documents.map((document): UserAnalyticsSourceUser => ({
        userKey: analyticsRegistrationUserKey(document.id),
        data: document.data(),
        lastActiveAt: activityByUserID.get(document.id),
      }));
      baseStats = combinedUserAnalyticsBaseStats(
        baseStats,
        userAnalyticsBaseStats(users, now, windowIndex)
      );

      for (const user of users) {
        const createdAt = dateValue(user.data.createdAt);
        if (createdAt === undefined || createdAt.getTime() > now.getTime()) {
          continue;
        }

        const createdDay = dailyDocumentIDFor(createdAt);
        if (shouldUseAnalyticsRegistrationFallback(
          createdDay,
          createdAt,
          windowIndex,
          lifecycleCoverageByDay
        )) {
          setBoundedAnalyticsRegistrationFallback(
            fallbackRegistrationDayByUserKey,
            user.userKey,
            createdDay
          );
        }
      }
    }
  );

  let registrationCounts = emptyAnalyticsLifecyclePeriodCounts();
  await forEachAnalyticsScanPage(
    db.collection(schema.collections.registeredUserEvents)
      .select("analyticsDay", "userKey", "registeredAt"),
    (documents) => {
      const eventDays: string[] = [];
      for (const document of documents) {
        const analyticsDay = stringValue(document.data().analyticsDay);
        const userKey = stringValue(document.data().userKey);
        const registeredAt = dateValue(document.data().registeredAt);
        if (analyticsDay === undefined || userKey === undefined ||
          registeredAt === undefined || dailyDocumentIDFor(registeredAt) !== analyticsDay) {
          throw new Error(`Analytics registration event ${document.id} is malformed.`);
        }

        if (isAnalyticsLifecycleEventAfterCoverage(
          analyticsDay,
          registeredAt,
          lifecycleCoverageByDay
        )) {
          eventDays.push(analyticsDay);
          fallbackRegistrationDayByUserKey.delete(userKey);
        }
      }
      registrationCounts = combinedAnalyticsLifecyclePeriodCounts(
        registrationCounts,
        analyticsLifecyclePeriodCounts(eventDays, windowIndex)
      );
    }
  );
  registrationCounts = combinedAnalyticsLifecyclePeriodCounts(
    registrationCounts,
    analyticsLifecyclePeriodCounts(
      fallbackRegistrationDayByUserKey.values(),
      windowIndex
    )
  );

  registrationCounts = combinedAnalyticsLifecyclePeriodCounts(
    registrationCounts,
    analyticsLifecycleWeightedPeriodCounts(
      lifecycleBaselines.map((baseline) => ({
        analyticsDay: baseline.analyticsDay,
        count: baseline.newRegistrations,
      })),
      windowIndex
    )
  );

  let deletionCounts = emptyAnalyticsLifecyclePeriodCounts();
  await forEachAnalyticsScanPage(
    db.collection(schema.collections.deletedUserEvents)
      .select("analyticsDay", "deletedAt"),
    (documents) => {
      const eventDays = documents.flatMap((document) => {
        const analyticsDay = stringValue(document.data().analyticsDay);
        const deletedAt = dateValue(document.data().deletedAt);
        if (analyticsDay === undefined || deletedAt === undefined ||
          dailyDocumentIDFor(deletedAt) !== analyticsDay) {
          throw new Error(`Analytics deletion event ${document.id} is malformed.`);
        }
        return isAnalyticsLifecycleEventAfterCoverage(
          analyticsDay,
          deletedAt,
          lifecycleCoverageByDay
        ) ? [analyticsDay] : [];
      });
      deletionCounts = combinedAnalyticsLifecyclePeriodCounts(
        deletionCounts,
        analyticsLifecyclePeriodCounts(eventDays, windowIndex)
      );
    }
  );
  deletionCounts = combinedAnalyticsLifecyclePeriodCounts(
    deletionCounts,
    analyticsLifecycleWeightedPeriodCounts(
      lifecycleBaselines.map((baseline) => ({
        analyticsDay: baseline.analyticsDay,
        count: baseline.deletedAccounts,
      })),
      windowIndex
    )
  );

  const todaySourceDocumentIDs = [currentDatedDocumentID];
  const todayStats = userAnalyticsPeriodStats(
    baseStats,
    registrationCounts.today,
    deletionCounts.today
  );
  const sevenDaySourceDocumentIDs = windowIndex.sevenDayDocumentIDs;
  const thirtyDaySourceDocumentIDs = windowIndex.thirtyDayDocumentIDs;
  const sevenDayStats = userAnalyticsPeriodStats(
    baseStats,
    registrationCounts.sevenDays,
    deletionCounts.sevenDays
  );
  const thirtyDayStats = userAnalyticsPeriodStats(
    baseStats,
    registrationCounts.thirtyDays,
    deletionCounts.thirtyDays
  );
  const batch = db.batch();

  batch.set(
    db.collection(schema.collections.userStats).doc(todayDocumentID),
    userAnalyticsDocumentData(
      "today",
      todayStats,
      todaySourceDocumentIDs,
      lifecycleCoverageStartDay
    )
  );
  batch.set(
    db.collection(schema.collections.userStats).doc(currentDatedDocumentID),
    userAnalyticsDocumentData(
      currentDatedDocumentID,
      todayStats,
      todaySourceDocumentIDs,
      lifecycleCoverageStartDay
    )
  );
  batch.set(
    db.collection(schema.collections.userStats).doc("seven_days"),
    userAnalyticsDocumentData(
      "seven_days",
      sevenDayStats,
      sevenDaySourceDocumentIDs,
      lifecycleCoverageStartDay
    )
  );
  batch.set(
    db.collection(schema.collections.userStats).doc("thirty_days"),
    userAnalyticsDocumentData(
      "thirty_days",
      thirtyDayStats,
      thirtyDaySourceDocumentIDs,
      lifecycleCoverageStartDay
    )
  );

  await batch.commit();
}

type UserAnalyticsStats = {
  totalUsers: number;
  newRegistrations: number;
  deletedAccounts: number;
  blockedUsers: number;
  deactivatedUsers: number;
  activeUsersToday: number;
  activeUsersSevenDays: number;
  activeUsersThirtyDays: number;
  usersByFederalState: Record<string, number>;
};

type UserAnalyticsBaseStats = {
  totalUsers: number;
  blockedUsers: number;
  deactivatedUsers: number;
  activeUsersToday: number;
  activeUsersSevenDays: number;
  activeUsersThirtyDays: number;
  usersByFederalState: Record<string, number>;
};

type UserAnalyticsSourceUser = {
  userKey: string;
  data: DocumentData;
  lastActiveAt?: Date;
};

export type AnalyticsLifecyclePeriodCounts = {
  today: number;
  sevenDays: number;
  thirtyDays: number;
};

async function forEachAnalyticsScanPage(
  baseQuery: Query<DocumentData>,
  processPage: (
    documents: QueryDocumentSnapshot<DocumentData>[]
  ) => Promise<void> | void
): Promise<void> {
  let cursor: string | undefined;

  while (true) {
    let query = baseQuery
      .orderBy(FieldPath.documentId())
      .limit(analyticsMaterializationPageSize);
    if (cursor !== undefined) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    if (snapshot.empty) {
      return;
    }

    await processPage(snapshot.docs);
    cursor = nextAnalyticsScanCursor(
      snapshot.docs.map((document) => document.id),
      analyticsMaterializationPageSize
    );
    if (cursor === undefined) {
      return;
    }
  }
}

async function loadAnalyticsActivityByUserID(
  userIDs: readonly string[]
): Promise<Map<string, Date>> {
  const activityByUserID = new Map<string, Date>();
  const batches = boundedAnalyticsBatches(
    userIDs,
    analyticsActivityLookupBatchSize
  );
  const snapshotBatches = await Promise.all(batches.map((batch) => {
    const references = batch.map((userID) => db
      .collection(schema.collections.userActivity)
      .doc(userID));
    return db.getAll(...references);
  }));

  for (const snapshots of snapshotBatches) {
    for (const snapshot of snapshots) {
      const lastActiveAt = dateValue(snapshot.data()?.lastActiveAt);
      if (lastActiveAt !== undefined) {
        activityByUserID.set(snapshot.id, lastActiveAt);
      }
    }
  }

  return activityByUserID;
}

function emptyUserAnalyticsBaseStats(): UserAnalyticsBaseStats {
  return {
    totalUsers: 0,
    blockedUsers: 0,
    deactivatedUsers: 0,
    activeUsersToday: 0,
    activeUsersSevenDays: 0,
    activeUsersThirtyDays: 0,
    usersByFederalState: {},
  };
}

function combinedUserAnalyticsBaseStats(
  left: UserAnalyticsBaseStats,
  right: UserAnalyticsBaseStats
): UserAnalyticsBaseStats {
  const usersByFederalState = {...left.usersByFederalState};
  for (const [federalState, count] of Object.entries(right.usersByFederalState)) {
    usersByFederalState[federalState] =
      (usersByFederalState[federalState] ?? 0) + count;
  }

  return {
    totalUsers: left.totalUsers + right.totalUsers,
    blockedUsers: left.blockedUsers + right.blockedUsers,
    deactivatedUsers: left.deactivatedUsers + right.deactivatedUsers,
    activeUsersToday: left.activeUsersToday + right.activeUsersToday,
    activeUsersSevenDays: left.activeUsersSevenDays + right.activeUsersSevenDays,
    activeUsersThirtyDays: left.activeUsersThirtyDays + right.activeUsersThirtyDays,
    usersByFederalState,
  };
}

function userAnalyticsBaseStats(
  users: UserAnalyticsSourceUser[],
  now: Date,
  windowIndex: AnalyticsActivityWindowIndex
): UserAnalyticsBaseStats {
  const usersByFederalState: Record<string, number> = {};
  let blockedUsers = 0;
  let deactivatedUsers = 0;
  let activeUsersToday = 0;
  let activeUsersSevenDays = 0;
  let activeUsersThirtyDays = 0;

  for (const user of users) {
    const federalState = stringValue(user.data.selectedFederalState);
    if (federalState !== undefined && federalStates.has(federalState)) {
      usersByFederalState[federalState] = (usersByFederalState[federalState] ?? 0) + 1;
    }

    const restricted = isRestrictedUser(user.data);
    if (isDeactivatedUser(user.data)) {
      deactivatedUsers += 1;
    } else if (restricted) {
      blockedUsers += 1;
    }

    if (!restricted) {
      const activity = analyticsActivityWindows(
        user.lastActiveAt,
        now,
        windowIndex
      );
      if (activity.today) {
        activeUsersToday += 1;
      }

      if (activity.sevenDays) {
        activeUsersSevenDays += 1;
      }

      if (activity.thirtyDays) {
        activeUsersThirtyDays += 1;
      }
    }
  }

  return {
    totalUsers: users.length,
    blockedUsers,
    deactivatedUsers,
    activeUsersToday,
    activeUsersSevenDays,
    activeUsersThirtyDays,
    usersByFederalState,
  };
}

function userAnalyticsPeriodStats(
  baseStats: UserAnalyticsBaseStats,
  newRegistrations: number,
  deletedAccounts: number
): UserAnalyticsStats {
  return {
    ...baseStats,
    newRegistrations,
    deletedAccounts,
  };
}

function userAnalyticsDocumentData(
  period: string,
  stats: UserAnalyticsStats,
  sourceDocumentIDs: readonly string[],
  lifecycleCoverageStartDay: string
): DocumentData {
  const lifecycleCoverage = analyticsDetailCoverage(
    sourceDocumentIDs,
    lifecycleCoverageStartDay
  );
  return {
    [schema.userStatsFields.period]: period,
    [schema.userStatsFields.generatedAt]: FieldValue.serverTimestamp(),
    [schema.userStatsFields.metrics]: {
      [schema.userStatsFields.totalUsers]: stats.totalUsers,
      [schema.userStatsFields.newRegistrations]: stats.newRegistrations,
      [schema.userStatsFields.deletedAccounts]: stats.deletedAccounts,
      [schema.userStatsFields.blockedUsers]: stats.blockedUsers,
      [schema.userStatsFields.deactivatedUsers]: stats.deactivatedUsers,
      [schema.userStatsFields.activeUsersToday]: stats.activeUsersToday,
      [schema.userStatsFields.activeUsersSevenDays]: stats.activeUsersSevenDays,
      [schema.userStatsFields.activeUsersThirtyDays]: stats.activeUsersThirtyDays,
      [schema.userStatsFields.activeToday]: stats.activeUsersToday,
      [schema.userStatsFields.activeSevenDays]: stats.activeUsersSevenDays,
      [schema.userStatsFields.activeThirtyDays]: stats.activeUsersThirtyDays,
    },
    [schema.userStatsFields.usersByFederalState]: stats.usersByFederalState,
    [schema.userStatsFields.sourceDocumentIDs]: sourceDocumentIDs,
    [schema.userStatsFields.lifecycleCoverageStartDay]:
      lifecycleCoverage.coverageStartDay,
    [schema.userStatsFields.coveredLifecycleSourceDocumentIDs]:
      lifecycleCoverage.coveredSourceDocumentIDs,
    [schema.userStatsFields.isLifecyclePartialCoverage]:
      lifecycleCoverage.isPartialCoverage,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

export function analyticsLifecyclePeriodCounts(
  eventDays: Iterable<string>,
  windowIndex: AnalyticsActivityWindowIndex
): AnalyticsLifecyclePeriodCounts {
  const counts = emptyAnalyticsLifecyclePeriodCounts();
  for (const eventDay of eventDays) {
    if (eventDay === windowIndex.todayDocumentID) {
      counts.today += 1;
    }
    if (windowIndex.sevenDayDocumentIDSet.has(eventDay)) {
      counts.sevenDays += 1;
    }
    if (windowIndex.thirtyDayDocumentIDSet.has(eventDay)) {
      counts.thirtyDays += 1;
    }
  }
  return counts;
}

export function analyticsLifecycleWeightedPeriodCounts(
  dailyCounts: Iterable<{analyticsDay: string; count: number}>,
  windowIndex: AnalyticsActivityWindowIndex
): AnalyticsLifecyclePeriodCounts {
  const counts = emptyAnalyticsLifecyclePeriodCounts();
  for (const dailyCount of dailyCounts) {
    if (!Number.isSafeInteger(dailyCount.count) || dailyCount.count < 0) {
      throw new RangeError("Analytics lifecycle baseline count must be non-negative.");
    }
    if (dailyCount.analyticsDay === windowIndex.todayDocumentID) {
      counts.today += dailyCount.count;
    }
    if (windowIndex.sevenDayDocumentIDSet.has(dailyCount.analyticsDay)) {
      counts.sevenDays += dailyCount.count;
    }
    if (windowIndex.thirtyDayDocumentIDSet.has(dailyCount.analyticsDay)) {
      counts.thirtyDays += dailyCount.count;
    }
  }
  return counts;
}

function emptyAnalyticsLifecyclePeriodCounts(): AnalyticsLifecyclePeriodCounts {
  return {today: 0, sevenDays: 0, thirtyDays: 0};
}

function combinedAnalyticsLifecyclePeriodCounts(
  left: AnalyticsLifecyclePeriodCounts,
  right: AnalyticsLifecyclePeriodCounts
): AnalyticsLifecyclePeriodCounts {
  return {
    today: left.today + right.today,
    sevenDays: left.sevenDays + right.sevenDays,
    thirtyDays: left.thirtyDays + right.thirtyDays,
  };
}

export function analyticsLifecycleEventCount(
  eventDays: string[],
  sourceDocumentIDs: string[]
): number {
  const sourceDocumentIDSet = new Set(sourceDocumentIDs);
  return eventDays.filter((documentID) =>
    sourceDocumentIDSet.has(documentID)
  ).length;
}

export function analyticsRegistrationDays(
  registrationEvents: Array<{analyticsDay: string; userKey: string}>,
  currentUsers: Array<{userKey: string; createdAt?: Date}>,
  now: Date
): string[] {
  const registeredUserKeys = new Set(
    registrationEvents.map((event) => event.userKey)
  );
  const fallbackDays = currentUsers.flatMap((user) => {
    if (registeredUserKeys.has(user.userKey)
      || user.createdAt === undefined
      || user.createdAt.getTime() > now.getTime()) {
      return [];
    }
    return [dailyDocumentIDFor(user.createdAt)];
  });

  return [
    ...registrationEvents.map((event) => event.analyticsDay),
    ...fallbackDays,
  ];
}

async function loadTopContentRollup(
  sourceDocumentIDs: string[]
): Promise<RollupTopContentItem[]> {
  const snapshots = await Promise.all(sourceDocumentIDs.map((documentID) =>
    db.collection(schema.collections.topContent).doc(documentID).get()
  ));
  return mergeAnalyticsTopContentSources(snapshots.map((snapshot) => {
    const data = snapshot.data();
    return data === undefined ? [] : topContentItemsFromData(data);
  }));
}

export function mergeAnalyticsTopContentSources(
  sourcesNewestFirst: ReadonlyArray<ReadonlyArray<RollupTopContentItem>>
): RollupTopContentItem[] {
  const itemsByKey = new Map<string, RollupTopContentItem>();

  for (const sourceItems of sourcesNewestFirst) {
    for (const item of sourceItems) {
      const key = contentRollupKey(item.contentType, item.contentID);
      const current = itemsByKey.get(key);
      if (current === undefined) {
        itemsByKey.set(key, item);
        continue;
      }

      itemsByKey.set(key, {
        ...current,
        title: current.title || item.title,
        viewCount: current.viewCount + item.viewCount,
      });
    }
  }

  // Each UI section gets its own meaningful ranking. A single global top 20
  // allowed one dominant content type to hide every item from the others.
  return (["news", "event", "organization"] as AnalyticsContentType[])
    .flatMap((contentType) => Array.from(itemsByKey.values())
      .filter((item) => item.contentType === contentType)
      .sort((left, right) => {
        if (left.viewCount === right.viewCount) {
          return left.contentID.localeCompare(right.contentID);
        }
        return right.viewCount - left.viewCount;
      })
      .slice(0, 20)
      .map((item, index) => ({
        ...item,
        rank: index + 1,
      })));
}

async function loadRegionStatsRollup(
  sourceDocumentIDs: string[]
): Promise<RollupRegionStatsItem[]> {
  const snapshots = await Promise.all(sourceDocumentIDs.map((documentID) =>
    db.collection(schema.collections.regionStats).doc(documentID).get()
  ));
  const regionsByKey = new Map<string, RollupRegionStatsItem>();

  for (const snapshot of snapshots) {
    const data = snapshot.data();
    if (data === undefined) {
      continue;
    }

    for (const region of regionStatsItemsFromData(data)) {
      const key = regionRollupKey(region.regionScope, region.federalState);
      const current = regionsByKey.get(key);
      if (current === undefined) {
        regionsByKey.set(key, region);
        continue;
      }

      regionsByKey.set(key, {
        ...current,
        viewCount: current.viewCount + region.viewCount,
        metrics: combinedMetrics(current.metrics, region.metrics),
      });
    }
  }

  return Array.from(regionsByKey.values())
    .sort((left, right) => right.viewCount - left.viewCount)
    .slice(0, 50);
}

export function topContentItemsFromData(data: DocumentData): RollupTopContentItem[] {
  const itemsByKey = data[schema.topContentFields.itemsByKey];
  if (isRecord(itemsByKey)) {
    const mappedItems = Object.values(itemsByKey).flatMap(topContentItemFromUnknown);
    if (mappedItems.length > 0) {
      return mappedItems;
    }
  }

  const items = data[schema.topContentFields.items];
  if (Array.isArray(items)) {
    return items.flatMap(topContentItemFromUnknown);
  }

  return [];
}

function topContentItemFromUnknown(value: unknown): RollupTopContentItem[] {
  if (!isRecord(value)) {
    return [];
  }

  const contentID = stringValue(value[schema.topContentFields.contentID]);
  const contentType = analyticsContentType(value[schema.topContentFields.contentType]);
  const viewCount = positiveInteger(value[schema.topContentFields.viewCount]);
  if (contentID === undefined || contentType === undefined || viewCount === 0) {
    return [];
  }

  return [{
    contentID,
    contentType,
    title: stringValue(value[schema.topContentFields.title]) ?? "",
    category: stringValue(value[schema.topContentFields.category]),
    organizationID: stringValue(value[schema.topContentFields.organizationID]),
    organizationName: stringValue(value[schema.topContentFields.organizationName]),
    federalState: stringValue(value[schema.topContentFields.federalState]),
    regionScope: stringValue(value[schema.topContentFields.regionScope]),
    viewCount,
    rank: positiveInteger(value[schema.topContentFields.rank]),
  }];
}

export function regionStatsItemsFromData(data: DocumentData): RollupRegionStatsItem[] {
  const regionsByKey = data[schema.regionStatsFields.regionsByKey];
  if (isRecord(regionsByKey)) {
    const mappedRegions = Object.values(regionsByKey).flatMap(regionStatsItemFromUnknown);
    if (mappedRegions.length > 0) {
      return mappedRegions;
    }
  }

  const regions = data[schema.regionStatsFields.regions];
  if (Array.isArray(regions)) {
    return regions.flatMap(regionStatsItemFromUnknown);
  }

  return [];
}

function regionStatsItemFromUnknown(value: unknown): RollupRegionStatsItem[] {
  if (!isRecord(value)) {
    return [];
  }

  const regionScope = stringValue(value[schema.regionStatsFields.regionScope]);
  const federalState = stringValue(value[schema.regionStatsFields.federalState]);
  const normalizedRegion = normalizeAnalyticsRegion(regionScope, federalState);
  if (normalizedRegion === undefined) {
    return [];
  }
  const metrics = activeRegionMetricMap(value[schema.regionStatsFields.metrics]);
  const viewCount = Array.from(metrics.values()).reduce(
    (total, metricValue) => total + metricValue,
    0
  );
  if (!hasActiveRegionAnalytics(viewCount, 0)) {
    return [];
  }
  metrics.set(schema.dailyStatsFields.totalViews, viewCount);

  return [{
    regionScope: normalizedRegion.regionScope,
    federalState: normalizedRegion.federalState,
    viewCount,
    metrics,
  }];
}

function rankedTopContentItems(items: RollupTopContentItem[]): DocumentData[] {
  return items.map((item) => {
    const data: DocumentData = {
      [schema.topContentFields.contentID]: item.contentID,
      [schema.topContentFields.contentType]: item.contentType,
      [schema.topContentFields.title]: item.title,
      [schema.topContentFields.viewCount]: item.viewCount,
      [schema.topContentFields.rank]: item.rank,
    };

    if (item.category !== undefined) {
      data[schema.topContentFields.category] = item.category;
    }

    if (item.organizationID !== undefined) {
      data[schema.topContentFields.organizationID] = item.organizationID;
    }

    if (item.organizationName !== undefined) {
      data[schema.topContentFields.organizationName] = item.organizationName;
    }

    if (item.regionScope !== undefined) {
      data[schema.topContentFields.regionScope] = item.regionScope;
    }

    if (item.federalState !== undefined) {
      data[schema.topContentFields.federalState] = item.federalState;
    }

    return data;
  });
}

function topContentMap(items: RollupTopContentItem[]): DocumentData {
  return Object.fromEntries(items.map((item) => [
    contentRollupKey(item.contentType, item.contentID),
    rankedTopContentItems([item])[0],
  ]));
}

function rankedRegionStats(items: RollupRegionStatsItem[]): DocumentData[] {
  return items.map(regionStatsData);
}

function regionStatsMap(items: RollupRegionStatsItem[]): DocumentData {
  return Object.fromEntries(items.map((item) => [
    regionRollupKey(item.regionScope, item.federalState),
    regionStatsData(item),
  ]));
}

function regionStatsData(item: RollupRegionStatsItem): DocumentData {
  const data: DocumentData = {
    [schema.regionStatsFields.regionScope]: item.regionScope,
    [schema.regionStatsFields.viewCount]: item.viewCount,
    [schema.regionStatsFields.metrics]: Object.fromEntries(item.metrics),
  };

  if (item.federalState !== undefined) {
    data[schema.regionStatsFields.federalState] = item.federalState;
  }

  return data;
}

function requiredSafeID(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (!/^[A-Za-z0-9._:-]{1,128}$/.test(trimmedValue)) {
    throw new HttpsError("invalid-argument", `${field} is not valid.`);
  }

  return trimmedValue;
}

function optionalSafeID(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  return requiredSafeID(value, field);
}

function optionalSlug(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.trim();
  if (trimmedValue.length === 0) {
    return undefined;
  }

  if (!/^[A-Za-z0-9_-]{1,64}$/.test(trimmedValue)) {
    throw new HttpsError("invalid-argument", `${field} is not valid.`);
  }

  return trimmedValue;
}

function optionalFederalState(value: unknown): string | undefined {
  const federalState = optionalSlug(value, "federal_state");
  if (federalState !== undefined && !federalStates.has(federalState)) {
    throw new HttpsError("invalid-argument", "federal_state is not supported.");
  }

  return federalState;
}

function optionalRegionScope(value: unknown): string | undefined {
  const regionScope = optionalSlug(value, "region_scope");
  if (regionScope !== undefined && !regionScopes.has(regionScope)) {
    throw new HttpsError("invalid-argument", "region_scope is not supported.");
  }

  return regionScope;
}

function optionalSafeTitle(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }

  const trimmedValue = value.replace(/\s+/g, " ").trim();
  if (trimmedValue.length === 0) {
    return undefined;
  }

  if (
    trimmedValue.length > 120
    || /@/.test(trimmedValue)
    || /https?:\/\//i.test(trimmedValue)
    || /\b\d{4,}\b/.test(trimmedValue)
  ) {
    return undefined;
  }

  return trimmedValue;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : undefined;
}

function positiveInteger(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : 0;
}

function requiredLifecycleBaselineCount(
  value: unknown,
  analyticsDay: string,
  field: string
): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new Error(
      `Analytics lifecycle baseline ${analyticsDay}.${field} is malformed.`
    );
  }
  return value;
}

function analyticsContentType(value: unknown): AnalyticsContentType | undefined {
  switch (value) {
    case "news":
    case "event":
    case "organization":
      return value;
    default:
      return undefined;
  }
}

function activeRegionMetricMap(value: unknown): Map<string, number> {
  if (!isRecord(value)) {
    return new Map();
  }

  return new Map(activeRegionViewMetricFields
    .map((field) => [field, positiveInteger(value[field])] as const)
    .filter(([, metricValue]) => metricValue > 0));
}

function combinedMetrics(
  left: Map<string, number>,
  right: Map<string, number>
): Map<string, number> {
  const metrics = new Map(left);

  for (const [key, value] of right) {
    metrics.set(key, (metrics.get(key) ?? 0) + value);
  }

  return metrics;
}

function isRestrictedUser(user: DocumentData): boolean {
  const accountStatus = stringValue(user.accountStatus);
  const blockState = stringValue(user.blockState);
  return isDeactivatedUser(user)
    || accountStatus === "suspendedUntil"
    || accountStatus === "bannedPermanent"
    || accountStatus === "temporarilyBanned"
    || accountStatus === "permanentlyBanned"
    || blockState === "suspendedUntil"
    || blockState === "bannedPermanent"
    || blockState === "blocked";
}

function isDeactivatedUser(user: DocumentData): boolean {
  return stringValue(user.accountStatus) === "deactivated"
    || stringValue(user.blockState) === "deactivated";
}

function dateValue(value: unknown): Date | undefined {
  if (value instanceof Timestamp) {
    return value.toDate();
  }

  if (value instanceof Date) {
    return value;
  }

  return undefined;
}

function analyticsRegionKey(analyticsEvent: SanitizedAnalyticsEvent): string | undefined {
  const normalizedRegion = normalizeAnalyticsRegion(
    analyticsEvent.regionScope,
    analyticsEvent.federalState
  );
  if (normalizedRegion === undefined) {
    return undefined;
  }

  return [
    normalizedRegion.regionScope,
    normalizedRegion.federalState ?? "all",
  ].join("_");
}

export function normalizeAnalyticsRegion(
  regionScope: string | undefined,
  federalState: string | undefined
): NormalizedAnalyticsRegion | undefined {
  if (regionScope === "austria") {
    return {regionScope: "austria"};
  }

  // City-level analytics intentionally does not retain a city name. Fold it
  // into its federal state instead of presenting a fake city bucket or
  // counting the same state twice under two scopes.
  if ((regionScope === "federalState" || regionScope === "city")
    && federalState !== undefined
    && federalStates.has(federalState)) {
    return {regionScope: "federalState", federalState};
  }

  return undefined;
}

function contentMapKey(analyticsEvent: SanitizedAnalyticsEvent): string {
  return contentRollupKey(analyticsEvent.contentType, analyticsEvent.contentID);
}

function contentRollupKey(
  contentType: AnalyticsContentType,
  contentID: string
): string {
  return [
    contentType,
    contentID
      .replace(/_/g, "__")
      .replace(/\./g, "_d")
      .replace(/:/g, "_c")
      .replace(/-/g, "_h"),
  ].join("_");
}

function regionRollupKey(
  regionScope: string,
  federalState: string | undefined
): string {
  return [regionScope, federalState ?? "all"].join("_");
}
