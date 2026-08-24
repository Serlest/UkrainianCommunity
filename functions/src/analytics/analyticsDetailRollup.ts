import {randomUUID} from "node:crypto";

import {
  FieldPath,
  FieldValue,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";

import {datedAnalyticsDocumentIDs} from "./analyticsDate";

interface AnalyticsDetailRollupPeriod {
  documentID: "today" | "seven_days" | "thirty_days";
  dayCount: number;
}

interface DetailCollectionDescriptor {
  rootCollection: "analyticsContentStats" | "analyticsOrganizationStats";
  childCollection: "items" | "organizations";
}

const detailCollections: DetailCollectionDescriptor[] = [
  {
    rootCollection: "analyticsContentStats",
    childCollection: "items",
  },
  {
    rootCollection: "analyticsOrganizationStats",
    childCollection: "organizations",
  },
];

const scalarMetadataFields = [
  "contentID",
  "contentType",
  "contentTitle",
  "organizationID",
  "organizationName",
  "category",
  "regionScope",
  "federalState",
] as const;

const nestedMetricFields = ["regionsByKey", "topNews", "topEvents"] as const;
const maximumNestedItems = 50;
const detailRollupPageSize = 100;
const maximumConcurrentSourceReads = 5;
const rollupGenerationField = "rollupGeneration";
const rollupInProgressGenerationField = "rollupInProgressGeneration";

class StaleAnalyticsDetailRollupGenerationError extends Error {
  constructor() {
    super("Analytics detail rollup generation is no longer current");
    this.name = "StaleAnalyticsDetailRollupGenerationError";
  }
}

export interface AnalyticsDetailPageDocument {
  itemID: string;
  data: DocumentData;
}

export interface AnalyticsDetailPageSource {
  sourceDocumentID: string;
  documents: readonly AnalyticsDetailPageDocument[];
  hasMore: boolean;
}

export interface AnalyticsDetailPageSelection {
  itemIDs: string[];
  documentsByItemID: Map<string, Array<{
    sourceDocumentID: string;
    data: DocumentData;
  }>>;
  consumedDocumentCounts: number[];
  requiresRefill: boolean;
}

interface DetailSourceState {
  sourceDocumentID: string;
  documents: AnalyticsDetailPageDocument[];
  cursor?: string;
  exhausted: boolean;
}

interface DetailRollupPage {
  itemIDs: string[];
  documentsByItemID: AnalyticsDetailPageSelection["documentsByItemID"];
}

interface DetailRollupPeriodContext {
  period: AnalyticsDetailRollupPeriod;
  sourceDocumentIDs: string[];
  sourceDocumentIDSet: Set<string>;
  coverageStartDay: string;
  coveredSourceDocumentIDs: string[];
  isPartialCoverage: boolean;
}

export interface AnalyticsDetailCoverage {
  coverageStartDay: string;
  coveredSourceDocumentIDs: string[];
  isPartialCoverage: boolean;
}

export async function rollupAnalyticsDetailPeriods(
  database: Firestore,
  periods: AnalyticsDetailRollupPeriod[],
  now: Date,
  coverageStartDay: string
): Promise<void> {
  if (periods.length === 0) {
    return;
  }

  const maximumDayCount = Math.max(...periods.map((period) => period.dayCount), 0);
  const sourceDocumentIDs = datedAnalyticsDocumentIDs(maximumDayCount, now);
  const periodContexts = periods.map((period): DetailRollupPeriodContext => {
    const periodSourceDocumentIDs = sourceDocumentIDs.slice(0, period.dayCount);
    const coverage = analyticsDetailCoverage(
      periodSourceDocumentIDs,
      coverageStartDay
    );
    return {
      period,
      sourceDocumentIDs: periodSourceDocumentIDs,
      ...coverage,
      sourceDocumentIDSet: new Set(coverage.coveredSourceDocumentIDs),
    };
  });

  // Descriptors are intentionally sequential. Each one keeps at most one
  // bounded page per dated source plus one bounded merged output page in memory.
  for (const descriptor of detailCollections) {
    const generation = `${now.toISOString()}-${randomUUID()}`;
    const sourceStates = sourceDocumentIDs
      .filter((sourceDocumentID) => sourceDocumentID >= coverageStartDay)
      .map((sourceDocumentID): DetailSourceState => ({
      sourceDocumentID,
      documents: [],
      exhausted: false,
      }));

    await markDetailRollupStarted(
      database,
      descriptor,
      periodContexts,
      generation
    );

    while (true) {
      const page = await loadNextDetailRollupPage(
        database,
        descriptor,
        sourceStates
      );
      if (page.itemIDs.length === 0) {
        break;
      }

      await writeDetailRollupPage(
        database,
        descriptor,
        periodContexts,
        generation,
        page
      );
    }

    for (const context of periodContexts) {
      await deleteStaleDetailRollupDocuments(
        database,
        descriptor,
        context.period,
        generation
      );
    }

    await markDetailRollupCompleted(
      database,
      descriptor,
      periodContexts,
      generation
    );
  }
}

export function analyticsDetailCoverage(
  sourceDocumentIDs: readonly string[],
  coverageStartDay: string
): AnalyticsDetailCoverage {
  const dayPattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!dayPattern.test(coverageStartDay) ||
    sourceDocumentIDs.some((documentID) => !dayPattern.test(documentID))) {
    throw new Error("analytics detail coverage requires dated document IDs");
  }

  const coveredSourceDocumentIDs = sourceDocumentIDs.filter(
    (documentID) => documentID >= coverageStartDay
  );
  return {
    coverageStartDay,
    coveredSourceDocumentIDs,
    isPartialCoverage: coveredSourceDocumentIDs.length < sourceDocumentIDs.length,
  };
}

/**
 * Selects a deterministic prefix from already sorted source buffers.
 *
 * The function stops before choosing another item whenever a non-exhausted
 * source needs a refill. That boundary is essential: an unseen document from
 * that source could sort before the visible heads of the other sources.
 */
export function selectAnalyticsDetailPage(
  sources: readonly AnalyticsDetailPageSource[],
  maximumItemCount: number
): AnalyticsDetailPageSelection {
  if (!Number.isInteger(maximumItemCount) || maximumItemCount < 1) {
    throw new Error("maximumItemCount must be a positive integer");
  }

  const consumedDocumentCounts = sources.map(() => 0);
  const itemIDs: string[] = [];
  const documentsByItemID: AnalyticsDetailPageSelection["documentsByItemID"] =
    new Map();

  while (itemIDs.length < maximumItemCount) {
    const requiresRefill = sources.some((source, index) =>
      consumedDocumentCounts[index] >= source.documents.length && source.hasMore
    );
    if (requiresRefill) {
      return {
        itemIDs,
        documentsByItemID,
        consumedDocumentCounts,
        requiresRefill: true,
      };
    }

    const visibleHeads = sources.flatMap((source, index) => {
      const document = source.documents[consumedDocumentCounts[index]];
      return document === undefined ? [] : [{index, document}];
    });
    if (visibleHeads.length === 0) {
      return {
        itemIDs,
        documentsByItemID,
        consumedDocumentCounts,
        requiresRefill: false,
      };
    }

    const itemID = visibleHeads.reduce((lowest, candidate) =>
      compareDocumentIDs(candidate.document.itemID, lowest) < 0
        ? candidate.document.itemID
        : lowest,
    visibleHeads[0].document.itemID);
    const documents: Array<{sourceDocumentID: string; data: DocumentData}> = [];

    for (const {index, document} of visibleHeads) {
      if (document.itemID !== itemID) {
        continue;
      }

      documents.push({
        sourceDocumentID: sources[index].sourceDocumentID,
        data: document.data,
      });
      consumedDocumentCounts[index] += 1;
    }

    itemIDs.push(itemID);
    documentsByItemID.set(itemID, documents);
  }

  return {
    itemIDs,
    documentsByItemID,
    consumedDocumentCounts,
    requiresRefill: false,
  };
}

export function staleAnalyticsDetailDocumentIDs(
  documents: ReadonlyArray<{
    documentID: string;
    rollupGeneration: unknown;
  }>,
  currentGeneration: string
): string[] {
  return documents
    .filter((document) => document.rollupGeneration !== currentGeneration)
    .map((document) => document.documentID);
}

export function mergeAnalyticsDetailDocuments(
  documents: DocumentData[],
  periodID: string
): DocumentData | undefined {
  if (documents.length === 0) {
    return undefined;
  }

  const result: DocumentData = {periodId: periodID};
  const metrics: DocumentData = {};
  const nestedValues = Object.fromEntries(
    nestedMetricFields.map((field) => [field, {} as DocumentData])
  ) as Record<(typeof nestedMetricFields)[number], DocumentData>;

  for (const document of documents) {
    for (const field of scalarMetadataFields) {
      if (result[field] === undefined && document[field] !== undefined) {
        result[field] = document[field];
      }
    }

    mergeMetricMap(metrics, document.metrics);
    for (const field of nestedMetricFields) {
      mergeNestedMetricMap(nestedValues[field], document[field]);
    }
  }

  if (Object.keys(metrics).length > 0) {
    result.metrics = metrics;
  }
  for (const field of nestedMetricFields) {
    if (Object.keys(nestedValues[field]).length > 0) {
      result[field] = limitedNestedMetricMap(nestedValues[field]);
    }
  }

  return result;
}

function limitedNestedMetricMap(value: DocumentData): DocumentData {
  return Object.fromEntries(Object.entries(value)
    .sort((left, right) => {
      const countDifference = viewMetricCount(right[1]) - viewMetricCount(left[1]);
      return countDifference === 0
        ? left[0].localeCompare(right[0])
        : countDifference;
    })
    .slice(0, maximumNestedItems));
}

function viewMetricCount(value: unknown): number {
  if (!isRecord(value) || !isRecord(value.metrics)) {
    return 0;
  }

  return ["views", "profileViews", "newsViews", "eventViews"]
    .reduce((total, field) => total + nonNegativeNumber(value.metrics[field]), 0);
}

async function loadNextDetailRollupPage(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  sourceStates: DetailSourceState[]
): Promise<DetailRollupPage> {
  const itemIDs: string[] = [];
  const documentsByItemID: DetailRollupPage["documentsByItemID"] = new Map();

  while (itemIDs.length < detailRollupPageSize) {
    await refillEmptyDetailSources(database, descriptor, sourceStates);
    const selection = selectAnalyticsDetailPage(
      sourceStates.map((state) => ({
        sourceDocumentID: state.sourceDocumentID,
        documents: state.documents,
        hasMore: !state.exhausted,
      })),
      detailRollupPageSize - itemIDs.length
    );

    selection.consumedDocumentCounts.forEach((count, index) => {
      if (count > 0) {
        sourceStates[index].documents.splice(0, count);
      }
    });
    for (const itemID of selection.itemIDs) {
      itemIDs.push(itemID);
      const documents = selection.documentsByItemID.get(itemID);
      if (documents !== undefined) {
        documentsByItemID.set(itemID, documents);
      }
    }

    if (itemIDs.length >= detailRollupPageSize) {
      break;
    }
    if (!selection.requiresRefill) {
      break;
    }
  }

  return {itemIDs, documentsByItemID};
}

async function refillEmptyDetailSources(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  sourceStates: DetailSourceState[]
): Promise<void> {
  const statesToRefill = sourceStates.filter((state) =>
    state.documents.length === 0 && !state.exhausted
  );

  for (
    let start = 0;
    start < statesToRefill.length;
    start += maximumConcurrentSourceReads
  ) {
    const batch = statesToRefill.slice(start, start + maximumConcurrentSourceReads);
    await Promise.all(batch.map(async (state) => {
      let query = database
        .collection(descriptor.rootCollection)
        .doc(state.sourceDocumentID)
        .collection(descriptor.childCollection)
        .orderBy(FieldPath.documentId())
        .limit(detailRollupPageSize);
      if (state.cursor !== undefined) {
        query = query.startAfter(state.cursor);
      }

      const snapshot = await query.get();
      state.documents = snapshot.docs.map((document) => ({
        itemID: document.id,
        data: document.data(),
      }));
      state.exhausted = snapshot.size < detailRollupPageSize;
      const lastDocument = snapshot.docs.at(-1);
      if (lastDocument !== undefined) {
        state.cursor = lastDocument.id;
      }
    }));
  }
}

async function markDetailRollupStarted(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  contexts: DetailRollupPeriodContext[],
  generation: string
): Promise<void> {
  const batch = database.batch();
  for (const context of contexts) {
    batch.set(
      database.collection(descriptor.rootCollection).doc(context.period.documentID),
      {
        [rollupInProgressGenerationField]: generation,
        rollupStartedAt: FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  }
  await batch.commit();
}

async function writeDetailRollupPage(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  contexts: DetailRollupPeriodContext[],
  generation: string,
  page: DetailRollupPage
): Promise<void> {
  for (const context of contexts) {
    const rootReference = database
      .collection(descriptor.rootCollection)
      .doc(context.period.documentID);
    const destination = database
      .collection(descriptor.rootCollection)
      .doc(context.period.documentID)
      .collection(descriptor.childCollection);

    // The parent marker is read in the same transaction as the page writes.
    // If a newer runner claimed the rollup, Firestore retries this transaction
    // and the stale runner exits without writing an old generation over it.
    await database.runTransaction(async (transaction) => {
      const rootSnapshot = await transaction.get(rootReference);
      assertDetailRollupGenerationCurrent(rootSnapshot.data(), generation);

      for (const itemID of page.itemIDs) {
        const sourceDocuments = page.documentsByItemID.get(itemID) ?? [];
        const documents = sourceDocuments
          .filter((document) => context.sourceDocumentIDSet.has(
            document.sourceDocumentID
          ))
          .map((document) => document.data);
        const merged = mergeAnalyticsDetailDocuments(
          documents,
          context.period.documentID
        );
        if (merged === undefined) {
          continue;
        }

        transaction.set(destination.doc(itemID), {
          ...merged,
          [rollupGenerationField]: generation,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
  }
}

async function deleteStaleDetailRollupDocuments(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  period: AnalyticsDetailRollupPeriod,
  generation: string
): Promise<void> {
  const rootReference = database
    .collection(descriptor.rootCollection)
    .doc(period.documentID);
  const destination = database
    .collection(descriptor.rootCollection)
    .doc(period.documentID)
    .collection(descriptor.childCollection);
  let cursor: string | undefined;

  while (true) {
    let query = destination
      .orderBy(FieldPath.documentId())
      .select(rollupGenerationField)
      .limit(detailRollupPageSize);
    if (cursor !== undefined) {
      query = query.startAfter(cursor);
    }

    // Read the ownership marker and prune the page atomically. A concurrent
    // claim changes the parent version, forcing a retry that then fails closed
    // before documents from the newer generation can be removed.
    const page = await database.runTransaction(async (transaction) => {
      const rootSnapshot = await transaction.get(rootReference);
      assertDetailRollupGenerationCurrent(rootSnapshot.data(), generation);
      const snapshot = await transaction.get(query);
      if (snapshot.empty) {
        return {size: 0, cursor: undefined};
      }

      const staleDocumentIDs = new Set(staleAnalyticsDetailDocumentIDs(
        snapshot.docs.map((document) => ({
          documentID: document.id,
          rollupGeneration: document.data()[rollupGenerationField],
        })),
        generation
      ));
      for (const document of snapshot.docs) {
        if (staleDocumentIDs.has(document.id)) {
          transaction.delete(document.ref);
        }
      }

      return {
        size: snapshot.size,
        cursor: snapshot.docs.at(-1)?.id,
      };
    });

    if (page.size === 0) {
      return;
    }

    cursor = page.cursor;
    if (page.size < detailRollupPageSize || cursor === undefined) {
      return;
    }
  }
}

async function markDetailRollupCompleted(
  database: Firestore,
  descriptor: DetailCollectionDescriptor,
  contexts: DetailRollupPeriodContext[],
  generation: string
): Promise<void> {
  await database.runTransaction(async (transaction) => {
    const completionTargets = [];
    for (const context of contexts) {
      const reference = database
        .collection(descriptor.rootCollection)
        .doc(context.period.documentID);
      const snapshot = await transaction.get(reference);
      assertDetailRollupGenerationCurrent(snapshot.data(), generation);
      completionTargets.push({context, reference});
    }

    for (const target of completionTargets) {
      transaction.set(target.reference, {
        periodId: target.context.period.documentID,
        sourceDocumentIDs: target.context.sourceDocumentIDs,
        coverageStartDay: target.context.coverageStartDay,
        coveredSourceDocumentIDs: target.context.coveredSourceDocumentIDs,
        isPartialCoverage: target.context.isPartialCoverage,
        [rollupGenerationField]: generation,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}

export function isAnalyticsDetailRollupGenerationCurrent(
  rootData: DocumentData | undefined,
  expectedGeneration: string
): boolean {
  return rootData?.[rollupInProgressGenerationField] === expectedGeneration;
}

function assertDetailRollupGenerationCurrent(
  rootData: DocumentData | undefined,
  expectedGeneration: string
): void {
  if (!isAnalyticsDetailRollupGenerationCurrent(rootData, expectedGeneration)) {
    throw new StaleAnalyticsDetailRollupGenerationError();
  }
}

function compareDocumentIDs(left: string, right: string): number {
  // Analytics keys are canonical ASCII IDs, so this matches Firestore's
  // document-ID ordering without allocating buffers in the hot merge loop.
  return left < right ? -1 : left > right ? 1 : 0;
}

function mergeMetricMap(target: DocumentData, value: unknown): void {
  if (!isRecord(value)) {
    return;
  }

  for (const [key, rawValue] of Object.entries(value)) {
    const metricValue = nonNegativeNumber(rawValue);
    if (metricValue > 0) {
      target[key] = nonNegativeNumber(target[key]) + metricValue;
    }
  }
}

function mergeNestedMetricMap(target: DocumentData, value: unknown): void {
  if (!isRecord(value)) {
    return;
  }

  for (const [key, rawNestedValue] of Object.entries(value)) {
    if (!isRecord(rawNestedValue)) {
      continue;
    }

    const existing = isRecord(target[key]) ? target[key] : {};
    for (const [field, fieldValue] of Object.entries(rawNestedValue)) {
      if (field === "metrics") {
        const metrics = isRecord(existing.metrics) ? existing.metrics : {};
        mergeMetricMap(metrics, fieldValue);
        if (Object.keys(metrics).length > 0) {
          existing.metrics = metrics;
        }
      } else if (existing[field] === undefined && fieldValue !== undefined) {
        existing[field] = fieldValue;
      }
    }
    target[key] = existing;
  }
}

function nonNegativeNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.floor(value)
    : 0;
}

function isRecord(value: unknown): value is DocumentData {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
