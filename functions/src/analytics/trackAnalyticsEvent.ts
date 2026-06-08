import {
  FieldValue,
  Timestamp,
  type DocumentData,
} from "firebase-admin/firestore";
import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { requireAuth } from "../auth/context";
import { db } from "../firebase/admin";

type AnalyticsEventName =
  | "news_view"
  | "news_like"
  | "news_bookmark"
  | "event_view"
  | "event_register"
  | "event_cancel_registration"
  | "event_bookmark"
  | "organization_view"
  | "organization_follow"
  | "organization_unfollow"
  | "organization_bookmark"
  | "guide_article_view";

type AnalyticsContentType =
  | "news"
  | "event"
  | "organization"
  | "guideArticle";
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
  documentID: "seven_days" | "thirty_days";
  dayCount: number;
}

interface RollupTopContentItem {
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
  contentKeys: Set<string>;
  metrics: Map<string, number>;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const analyticsRollupScheduleOptions = {
  schedule: "every 1 hours",
  timeZone: "Europe/Vienna",
  region: "europe-west3",
  maxInstances: 1,
};

const schema = {
  collections: {
    dailyStats: "analyticsDailyStats",
    topContent: "analyticsTopContent",
    regionStats: "analyticsRegionStats",
    contentStats: "analyticsContentStats",
    organizationStats: "analyticsOrganizationStats",
    userStats: "analyticsUserStats",
    rollupState: "analyticsRollupState",
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
  event_cancel_registration: {
    contentType: "event",
    metricField: "eventCancelledRegistrations",
    eventKind: "action",
    contentMetricField: "cancelledRegistrations",
    compatibilityMetricFields: ["cancelledEventRegistrations"],
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
  organization_unfollow: {
    contentType: "organization",
    metricField: "organizationUnfollows",
    eventKind: "action",
    contentMetricField: "unfollows",
    organizationMetricField: "unfollows",
  },
  organization_bookmark: {
    contentType: "organization",
    metricField: "organizationBookmarks",
    eventKind: "action",
    contentMetricField: "bookmarks",
    organizationMetricField: "bookmarks",
    compatibilityMetricFields: ["totalBookmarks"],
  },
  guide_article_view: {
    contentType: "guideArticle",
    metricField: "guideArticleViews",
    eventKind: "view",
    contentMetricField: "views",
  },
};

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
  async (request): Promise<{ tracked: true }> => {
    requireAuth(request);

    const analyticsEvent = sanitizeAnalyticsEvent(parseRequest(request.data));
    const dailyDocumentID = dailyDocumentIDFor(new Date());

    const writes: Promise<void>[] = [
      updateDailyStats(dailyDocumentID, analyticsEvent),
      updateContentDetailStats(analyticsEvent),
    ];

    if (analyticsEvent.organizationID !== undefined) {
      writes.push(updateOrganizationDetailStats(analyticsEvent));
    }

    if (analyticsEvent.eventKind === "view") {
      writes.push(updateTopContent(analyticsEvent));
      writes.push(updateRegionStats(analyticsEvent));
    }

    await Promise.all(writes);

    return { tracked: true };
  }
);

export const rollupAnalyticsPeriods = onSchedule(
  analyticsRollupScheduleOptions,
  async () => {
    await materializeTodayAnalyticsSnapshots();
    await Promise.all(rollupPeriods.map(rollupAnalyticsPeriod));
  }
);

export const rollupUserAnalyticsStats = onSchedule(
  analyticsRollupScheduleOptions,
  async () => {
    await materializeUserAnalyticsStats();
  }
);

export const trackDeletedUserAnalyticsAggregate = onDocumentDeleted(
  {
    document: "users/{userID}",
    region: "europe-west3",
    maxInstances: 10,
  },
  async () => {
    const todayDocumentID = schema.periodDocumentIDs[0];
    const datedDocumentID = dailyDocumentIDFor(new Date());
    const deletionUpdate = {
      [schema.userStatsFields.metrics]: {
        [schema.userStatsFields.deletedAccounts]: FieldValue.increment(1),
      },
      updatedAt: FieldValue.serverTimestamp(),
    };

    await Promise.all([
      db.collection(schema.collections.userStats).doc(todayDocumentID).set(deletionUpdate, { merge: true }),
      db.collection(schema.collections.userStats).doc(datedDocumentID).set(deletionUpdate, { merge: true }),
    ]);
  }
);

function parseRequest(data: unknown): TrackAnalyticsEventRequest {
  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  const name = parseEventName(data.name ?? data.eventName);
  const parameters = data.parameters;
  if (!isRecord(parameters)) {
    throw new HttpsError("invalid-argument", "parameters must be an object.");
  }

  return {
    name,
    parameters,
  };
}

function sanitizeAnalyticsEvent(request: TrackAnalyticsEventRequest): SanitizedAnalyticsEvent {
  validateAllowedParameterNames(request.parameters);
  const config = eventConfigs[request.name];
  const contentID = requiredSafeID(request.parameters.content_id, "content_id");
  validateOptionalContentType(request.parameters.content_type, config.contentType);
  const category = optionalSlug(request.parameters.category, "category");
  const organizationID = optionalSafeID(request.parameters.organization_id, "organization_id");
  const federalState = optionalFederalState(request.parameters.federal_state);
  const regionScope = optionalRegionScope(request.parameters.region_scope);
  validateOptionalGuestFlag(request.parameters.is_guest);
  optionalSlug(request.parameters.account_state, "account_state");
  const contentTitle = optionalSafeTitle(request.parameters.content_title, "content_title");
  const organizationName = optionalSafeTitle(
    request.parameters.organization_name,
    "organization_name"
  );
  const title = contentTitle ?? organizationName ?? contentID;

  return {
    contentID,
    contentType: config.contentType,
    category,
    organizationID,
    organizationName,
    federalState,
    regionScope,
    title,
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

async function updateDailyStats(
  dailyDocumentID: string,
  analyticsEvent: SanitizedAnalyticsEvent
): Promise<void> {
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
    [schema.dailyStatsFields.date]: Timestamp.now(),
    updatedAt: FieldValue.serverTimestamp(),
    [schema.dailyStatsFields.metrics]: metrics,
  };
  const regionKey = analyticsRegionKey(analyticsEvent);

  if (analyticsEvent.eventKind === "view" && regionKey !== undefined) {
    data.activeRegionKeys = {
      [regionKey]: true,
    };
  }

  await dailyStatsReference.set(data, { merge: true });
}

async function updateContentDetailStats(
  analyticsEvent: SanitizedAnalyticsEvent
): Promise<void> {
  const reference = db
    .collection(schema.collections.contentStats)
    .doc(schema.periodDocumentIDs[0])
    .collection(schema.detailStatsFields.items)
    .doc(contentMapKey(analyticsEvent));
  const data: DocumentData = {
    [schema.detailStatsFields.periodID]: schema.periodDocumentIDs[0],
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

  await reference.set(data, { merge: true });
}

async function updateOrganizationDetailStats(
  analyticsEvent: SanitizedAnalyticsEvent
): Promise<void> {
  if (analyticsEvent.organizationID === undefined) {
    return;
  }

  const organizationMetricField = analyticsEvent.organizationMetricField;
  const reference = db
    .collection(schema.collections.organizationStats)
    .doc(schema.periodDocumentIDs[0])
    .collection(schema.detailStatsFields.organizations)
    .doc(analyticsEvent.organizationID);
  const data: DocumentData = {
    [schema.detailStatsFields.periodID]: schema.periodDocumentIDs[0],
    [schema.detailStatsFields.organizationID]: analyticsEvent.organizationID,
    [schema.detailStatsFields.updatedAt]: FieldValue.serverTimestamp(),
  };

  if (analyticsEvent.organizationName !== undefined) {
    data[schema.detailStatsFields.organizationName] = analyticsEvent.organizationName;
  }

  if (analyticsEvent.regionScope !== undefined) {
    data[schema.detailStatsFields.regionScope] = analyticsEvent.regionScope;
  }

  if (analyticsEvent.federalState !== undefined) {
    data[schema.detailStatsFields.federalState] = analyticsEvent.federalState;
  }

  if (organizationMetricField !== undefined) {
    data[schema.detailStatsFields.metrics] = {
      [organizationMetricField]: FieldValue.increment(1),
    };
    addRegionDetailMetrics(data, organizationMetricField, analyticsEvent);
  }

  addOrganizationTopContent(data, analyticsEvent);

  await reference.set(data, { merge: true });
}

function addOptionalDetailMetadata(
  data: DocumentData,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  if (analyticsEvent.category !== undefined) {
    data[schema.detailStatsFields.category] = analyticsEvent.category;
  }

  if (analyticsEvent.organizationID !== undefined) {
    data[schema.detailStatsFields.organizationID] = analyticsEvent.organizationID;
  }

  if (analyticsEvent.organizationName !== undefined) {
    data[schema.detailStatsFields.organizationName] = analyticsEvent.organizationName;
  }

  if (analyticsEvent.regionScope !== undefined) {
    data[schema.detailStatsFields.regionScope] = analyticsEvent.regionScope;
  }

  if (analyticsEvent.federalState !== undefined) {
    data[schema.detailStatsFields.federalState] = analyticsEvent.federalState;
  }
}

function addRegionDetailMetrics(
  data: DocumentData,
  metricField: string,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  const regionKey = analyticsRegionKey(analyticsEvent);
  if (analyticsEvent.regionScope === undefined || regionKey === undefined) {
    return;
  }

  const region: DocumentData = {
    [schema.detailStatsFields.regionScope]: analyticsEvent.regionScope,
    [schema.detailStatsFields.metrics]: {
      [metricField]: FieldValue.increment(1),
    },
  };

  if (analyticsEvent.federalState !== undefined) {
    region[schema.detailStatsFields.federalState] = analyticsEvent.federalState;
  }

  data[schema.detailStatsFields.regionsByKey] = {
    [regionKey]: region,
  };
}

function addOrganizationTopContent(
  data: DocumentData,
  analyticsEvent: SanitizedAnalyticsEvent
): void {
  if (analyticsEvent.contentType !== "news" && analyticsEvent.contentType !== "event") {
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

  if (analyticsEvent.category !== undefined) {
    item[schema.detailStatsFields.category] = analyticsEvent.category;
  }

  if (analyticsEvent.regionScope !== undefined) {
    item[schema.detailStatsFields.regionScope] = analyticsEvent.regionScope;
  }

  if (analyticsEvent.federalState !== undefined) {
    item[schema.detailStatsFields.federalState] = analyticsEvent.federalState;
  }

  data[field] = {
    [contentMapKey(analyticsEvent)]: item,
  };
}

async function updateTopContent(analyticsEvent: SanitizedAnalyticsEvent): Promise<void> {
  const dailyDocumentID = dailyDocumentIDFor(new Date());
  const reference = db
    .collection(schema.collections.topContent)
    .doc(schema.periodDocumentIDs[0]);
  const item: DocumentData = {
    [schema.topContentFields.contentID]: analyticsEvent.contentID,
    [schema.topContentFields.contentType]: analyticsEvent.contentType,
    [schema.topContentFields.title]: analyticsEvent.title,
    [schema.topContentFields.viewCount]: FieldValue.increment(1),
  };

  if (analyticsEvent.category !== undefined) {
    item[schema.topContentFields.category] = analyticsEvent.category;
  }

  if (analyticsEvent.organizationID !== undefined) {
    item[schema.topContentFields.organizationID] = analyticsEvent.organizationID;
  }

  if (analyticsEvent.organizationName !== undefined) {
    item[schema.topContentFields.organizationName] = analyticsEvent.organizationName;
  }

  if (analyticsEvent.regionScope !== undefined) {
    item[schema.topContentFields.regionScope] = analyticsEvent.regionScope;
  }

  if (analyticsEvent.federalState !== undefined) {
    item[schema.topContentFields.federalState] = analyticsEvent.federalState;
  }

  await reference.set({
    [schema.rollupStateFields.dateDocumentID]: dailyDocumentID,
    [schema.topContentFields.itemsByKey]: {
      [contentMapKey(analyticsEvent)]: item,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function updateRegionStats(analyticsEvent: SanitizedAnalyticsEvent): Promise<void> {
  const dailyDocumentID = dailyDocumentIDFor(new Date());
  const regionScope = analyticsEvent.regionScope;
  const regionKey = analyticsRegionKey(analyticsEvent);
  if (regionScope === undefined || regionKey === undefined) {
    return;
  }

  const reference = db
    .collection(schema.collections.regionStats)
    .doc(schema.periodDocumentIDs[0]);
  const region: DocumentData = {
    [schema.regionStatsFields.regionScope]: regionScope,
    [schema.regionStatsFields.viewCount]: FieldValue.increment(1),
    [schema.regionStatsFields.contentKeys]: {
      [contentMapKey(analyticsEvent)]: true,
    },
    [schema.regionStatsFields.metrics]: {
      [schema.dailyStatsFields.totalViews]: FieldValue.increment(1),
      [analyticsEvent.metricField]: FieldValue.increment(1),
    },
  };

  if (analyticsEvent.federalState !== undefined) {
    region[schema.regionStatsFields.federalState] = analyticsEvent.federalState;
  }

  await reference.set({
    [schema.rollupStateFields.dateDocumentID]: dailyDocumentID,
    [schema.regionStatsFields.regionsByKey]: {
      [regionKey]: region,
    },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function materializeTodayAnalyticsSnapshots(): Promise<void> {
  const todayDocumentID = schema.periodDocumentIDs[0];
  const currentDatedDocumentID = dailyDocumentIDFor(new Date());
  const stateReference = db
    .collection(schema.collections.rollupState)
    .doc(todayDocumentID);
  const [stateSnapshot, topContentSnapshot, regionStatsSnapshot] = await Promise.all([
    stateReference.get(),
    db.collection(schema.collections.topContent).doc(todayDocumentID).get(),
    db.collection(schema.collections.regionStats).doc(todayDocumentID).get(),
  ]);
  const previousDatedDocumentID = stringValue(
    stateSnapshot.data()?.[schema.rollupStateFields.dateDocumentID]
  );
  const snapshotDatedDocumentID = previousDatedDocumentID ?? currentDatedDocumentID;
  const isNewDay = previousDatedDocumentID !== undefined
    && previousDatedDocumentID !== currentDatedDocumentID;
  const batch = db.batch();
  let hasWrites = false;

  // The live "today" docs are cheap per-view write targets. The dated docs are
  // stable daily snapshots used later by seven-day and thirty-day rollups.
  const topContentData = topContentSnapshot.data();
  if (topContentData !== undefined) {
    batch.set(
      db.collection(schema.collections.topContent).doc(snapshotDatedDocumentID),
      dailySnapshotData(topContentData, todayDocumentID, snapshotDatedDocumentID)
    );
    hasWrites = true;
  }

  const regionStatsData = regionStatsSnapshot.data();
  if (regionStatsData !== undefined) {
    batch.set(
      db.collection(schema.collections.regionStats).doc(snapshotDatedDocumentID),
      dailySnapshotData(regionStatsData, todayDocumentID, snapshotDatedDocumentID)
    );
    hasWrites = true;
  }

  if (isNewDay) {
    batch.set(
      db.collection(schema.collections.topContent).doc(todayDocumentID),
      emptyTopContentData(currentDatedDocumentID)
    );
    batch.set(
      db.collection(schema.collections.regionStats).doc(todayDocumentID),
      emptyRegionStatsData(currentDatedDocumentID)
    );
    hasWrites = true;
  }

  batch.set(stateReference, {
    [schema.rollupStateFields.dateDocumentID]: currentDatedDocumentID,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  hasWrites = true;

  if (hasWrites) {
    await batch.commit();
  }
}

function dailySnapshotData(
  sourceData: DocumentData,
  sourceDocumentID: string,
  snapshotDocumentID: string
): DocumentData {
  return {
    ...sourceData,
    sourceDocumentID,
    snapshotDocumentID,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function emptyTopContentData(datedDocumentID: string): DocumentData {
  return {
    [schema.rollupStateFields.dateDocumentID]: datedDocumentID,
    [schema.topContentFields.items]: [],
    [schema.topContentFields.itemsByKey]: {},
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function emptyRegionStatsData(datedDocumentID: string): DocumentData {
  return {
    [schema.rollupStateFields.dateDocumentID]: datedDocumentID,
    [schema.regionStatsFields.regions]: [],
    [schema.regionStatsFields.regionsByKey]: {},
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function rollupAnalyticsPeriod(period: RollupPeriod): Promise<void> {
  const sourceDocumentIDs = rollupSourceDocumentIDs(period.dayCount);
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
    },
    { merge: true }
  );

  batch.set(
    db.collection(schema.collections.regionStats).doc(period.documentID),
    {
      [schema.regionStatsFields.regions]: rankedRegionStats(regionStats),
      [schema.regionStatsFields.regionsByKey]: regionStatsMap(regionStats),
      sourceDocumentIDs,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await batch.commit();
}

async function materializeUserAnalyticsStats(): Promise<void> {
  const now = new Date();
  const currentDatedDocumentID = dailyDocumentIDFor(now);
  const todayDocumentID = schema.periodDocumentIDs[0];
  const [usersSnapshot, existingTodaySnapshot, existingDatedSnapshot] = await Promise.all([
    db.collection("users")
      .select("createdAt", "updatedAt", "accountStatus", "blockState", "selectedFederalState")
      .get(),
    db.collection(schema.collections.userStats).doc(todayDocumentID).get(),
    db.collection(schema.collections.userStats).doc(currentDatedDocumentID).get(),
  ]);
  const users = usersSnapshot.docs.map((document) => document.data());
  const existingTodayDeletedAccounts = deletedAccountsFromData(existingTodaySnapshot.data());
  const existingDatedDeletedAccounts = deletedAccountsFromData(existingDatedSnapshot.data());
  const todayDeletedAccounts = Math.max(
    existingTodayDeletedAccounts,
    existingDatedDeletedAccounts
  );
  const baseStats = userAnalyticsBaseStats(users, now);
  const todayStats = userAnalyticsPeriodStats(baseStats, users, 1, todayDeletedAccounts, now);
  const sevenDaySourceDocumentIDs = userStatsSourceDocumentIDs(7, now);
  const thirtyDaySourceDocumentIDs = userStatsSourceDocumentIDs(30, now);
  const [sevenDayDeletedAccounts, thirtyDayDeletedAccounts] = await Promise.all([
    deletedAccountsForSourceDocuments(sevenDaySourceDocumentIDs, currentDatedDocumentID, todayDeletedAccounts),
    deletedAccountsForSourceDocuments(thirtyDaySourceDocumentIDs, currentDatedDocumentID, todayDeletedAccounts),
  ]);
  const sevenDayStats = userAnalyticsPeriodStats(baseStats, users, 7, sevenDayDeletedAccounts, now);
  const thirtyDayStats = userAnalyticsPeriodStats(baseStats, users, 30, thirtyDayDeletedAccounts, now);
  const batch = db.batch();

  batch.set(
    db.collection(schema.collections.userStats).doc(todayDocumentID),
    userAnalyticsDocumentData("today", todayStats, [currentDatedDocumentID])
  );
  batch.set(
    db.collection(schema.collections.userStats).doc(currentDatedDocumentID),
    userAnalyticsDocumentData(currentDatedDocumentID, todayStats, [currentDatedDocumentID])
  );
  batch.set(
    db.collection(schema.collections.userStats).doc("seven_days"),
    userAnalyticsDocumentData("seven_days", sevenDayStats, sevenDaySourceDocumentIDs)
  );
  batch.set(
    db.collection(schema.collections.userStats).doc("thirty_days"),
    userAnalyticsDocumentData("thirty_days", thirtyDayStats, thirtyDaySourceDocumentIDs)
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

function userAnalyticsBaseStats(users: DocumentData[], now: Date): UserAnalyticsBaseStats {
  const usersByFederalState: Record<string, number> = {};
  let blockedUsers = 0;
  let deactivatedUsers = 0;
  let activeUsersToday = 0;
  let activeUsersSevenDays = 0;
  let activeUsersThirtyDays = 0;

  for (const user of users) {
    const federalState = stringValue(user.selectedFederalState);
    if (federalState !== undefined && federalStates.has(federalState)) {
      usersByFederalState[federalState] = (usersByFederalState[federalState] ?? 0) + 1;
    }

    const restricted = isRestrictedUser(user);
    if (isDeactivatedUser(user)) {
      deactivatedUsers += 1;
    } else if (restricted) {
      blockedUsers += 1;
    }

    const updatedAt = dateValue(user.updatedAt);
    if (updatedAt !== undefined && !restricted) {
      if (isSameAnalyticsDay(updatedAt, now)) {
        activeUsersToday += 1;
      }

      if (isWithinTrailingDays(updatedAt, now, 7)) {
        activeUsersSevenDays += 1;
      }

      if (isWithinTrailingDays(updatedAt, now, 30)) {
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
  users: DocumentData[],
  dayCount: number,
  deletedAccounts: number,
  now: Date
): UserAnalyticsStats {
  const newRegistrations = users
    .map((user) => dateValue(user.createdAt))
    .filter((createdAt): createdAt is Date => createdAt !== undefined)
    .filter((createdAt) => dayCount === 1
      ? isSameAnalyticsDay(createdAt, now)
      : isWithinTrailingDays(createdAt, now, dayCount))
    .length;

  return {
    ...baseStats,
    newRegistrations,
    deletedAccounts,
  };
}

function userAnalyticsDocumentData(
  period: string,
  stats: UserAnalyticsStats,
  sourceDocumentIDs: string[]
): DocumentData {
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
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function deletedAccountsForSourceDocuments(
  sourceDocumentIDs: string[],
  currentDatedDocumentID: string,
  todayDeletedAccounts: number
): Promise<number> {
  const historicalDocumentIDs = sourceDocumentIDs.filter(
    (documentID) => documentID !== currentDatedDocumentID
  );
  const snapshots = await Promise.all(historicalDocumentIDs.map((documentID) =>
    db.collection(schema.collections.userStats).doc(documentID).get()
  ));

  return snapshots.reduce(
    (total, snapshot) => total + deletedAccountsFromData(snapshot.data()),
    todayDeletedAccounts
  );
}

async function loadTopContentRollup(
  sourceDocumentIDs: string[]
): Promise<RollupTopContentItem[]> {
  const snapshots = await Promise.all(sourceDocumentIDs.map((documentID) =>
    db.collection(schema.collections.topContent).doc(documentID).get()
  ));
  const itemsByKey = new Map<string, RollupTopContentItem>();

  for (const snapshot of snapshots) {
    const data = snapshot.data();
    if (data === undefined) {
      continue;
    }

    for (const item of topContentItemsFromData(data)) {
      const key = contentRollupKey(item.contentType, item.contentID);
      const current = itemsByKey.get(key);
      if (current === undefined) {
        itemsByKey.set(key, item);
        continue;
      }

      itemsByKey.set(key, {
        ...current,
        title: current.title || item.title,
        category: current.category ?? item.category,
        organizationID: current.organizationID ?? item.organizationID,
        organizationName: current.organizationName ?? item.organizationName,
        federalState: current.federalState ?? item.federalState,
        regionScope: current.regionScope ?? item.regionScope,
        viewCount: current.viewCount + item.viewCount,
      });
    }
  }

  return Array.from(itemsByKey.values())
    .sort((left, right) => right.viewCount - left.viewCount)
    .slice(0, 20)
    .map((item, index) => ({
      ...item,
      rank: index + 1,
    }));
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
        contentKeys: new Set([...current.contentKeys, ...region.contentKeys]),
        metrics: combinedMetrics(current.metrics, region.metrics),
      });
    }
  }

  return Array.from(regionsByKey.values())
    .sort((left, right) => right.viewCount - left.viewCount)
    .slice(0, 50);
}

function topContentItemsFromData(data: DocumentData): RollupTopContentItem[] {
  const itemsByKey = data[schema.topContentFields.itemsByKey];
  if (isRecord(itemsByKey)) {
    return Object.values(itemsByKey).flatMap(topContentItemFromUnknown);
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
  if (contentID === undefined || contentType === undefined) {
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
    viewCount: positiveInteger(value[schema.topContentFields.viewCount]),
    rank: positiveInteger(value[schema.topContentFields.rank]),
  }];
}

function regionStatsItemsFromData(data: DocumentData): RollupRegionStatsItem[] {
  const regionsByKey = data[schema.regionStatsFields.regionsByKey];
  if (isRecord(regionsByKey)) {
    return Object.values(regionsByKey).flatMap(regionStatsItemFromUnknown);
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
  if (regionScope === undefined || !regionScopes.has(regionScope)) {
    return [];
  }

  const federalState = stringValue(value[schema.regionStatsFields.federalState]);
  const contentKeys = recordKeys(value[schema.regionStatsFields.contentKeys]);
  const contentCount = positiveInteger(value[schema.regionStatsFields.contentCount]);
  const metrics = metricMap(value[schema.regionStatsFields.metrics]);

  return [{
    regionScope,
    federalState,
    viewCount: positiveInteger(value[schema.regionStatsFields.viewCount]),
    contentKeys: contentKeys.length > 0
      ? new Set(contentKeys)
      : fallbackContentKeys(contentCount, regionScope, federalState),
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
    [schema.regionStatsFields.contentCount]: item.contentKeys.size,
    [schema.regionStatsFields.contentKeys]: Object.fromEntries(
      Array.from(item.contentKeys).map((key) => [key, true])
    ),
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

function analyticsContentType(value: unknown): AnalyticsContentType | undefined {
  switch (value) {
    case "news":
    case "event":
    case "organization":
    case "guideArticle":
      return value;
    case "guide_article":
      return "guideArticle";
    default:
      return undefined;
  }
}

function recordKeys(value: unknown): string[] {
  return isRecord(value)
    ? Object.keys(value).filter((key) => key.length > 0)
    : [];
}

function metricMap(value: unknown): Map<string, number> {
  if (!isRecord(value)) {
    return new Map();
  }

  return new Map(Object.entries(value)
    .map(([key, metricValue]) => [key, positiveInteger(metricValue)] as const)
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

function fallbackContentKeys(
  contentCount: number,
  regionScope: string,
  federalState: string | undefined
): Set<string> {
  return new Set(Array.from({ length: contentCount }, (_, index) =>
    ["legacy", regionScope, federalState ?? "all", index.toString()].join("_")
  ));
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

function deletedAccountsFromData(data: DocumentData | undefined): number {
  if (data === undefined) {
    return 0;
  }

  const metrics = data[schema.userStatsFields.metrics];
  if (isRecord(metrics)) {
    return positiveInteger(metrics[schema.userStatsFields.deletedAccounts]);
  }

  return positiveInteger(data[schema.userStatsFields.deletedAccounts]);
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

function isSameAnalyticsDay(date: Date, now: Date): boolean {
  return dailyDocumentIDFor(date) === dailyDocumentIDFor(now);
}

function isWithinTrailingDays(date: Date, now: Date, dayCount: number): boolean {
  const start = new Date(now);
  start.setUTCDate(now.getUTCDate() - Math.max(0, dayCount - 1));
  start.setUTCHours(0, 0, 0, 0);
  return date.getTime() >= start.getTime() && date.getTime() <= now.getTime();
}

function dailyDocumentIDFor(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = datePart(parts, "year");
  const month = datePart(parts, "month");
  const day = datePart(parts, "day");
  return `${year}-${month}-${day}`;
}

function datePart(parts: Intl.DateTimeFormatPart[], type: string): string {
  return parts.find((part) => part.type === type)?.value ?? "00";
}

function analyticsRegionKey(analyticsEvent: SanitizedAnalyticsEvent): string | undefined {
  if (analyticsEvent.regionScope === undefined) {
    return undefined;
  }

  return [
    analyticsEvent.regionScope,
    analyticsEvent.federalState ?? "all",
  ].join("_");
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

function rollupSourceDocumentIDs(dayCount: number): string[] {
  const today = new Date();
  // Rollups combine the live "today" aggregate with prior dated documents if
  // those documents exist. They do not read or create per-user analytics data.
  const priorDayCount = Math.max(0, dayCount - 1);
  const documentIDs = Array.from({ length: priorDayCount }, (_, offset) => {
    const date = new Date(today);
    date.setUTCDate(today.getUTCDate() - offset - 1);
    return dailyDocumentIDFor(date);
  });

  return [schema.periodDocumentIDs[0], ...documentIDs];
}

function userStatsSourceDocumentIDs(dayCount: number, now: Date): string[] {
  return Array.from({ length: dayCount }, (_, offset) => {
    const date = new Date(now);
    date.setUTCDate(now.getUTCDate() - offset);
    return dailyDocumentIDFor(date);
  });
}
