import {createHash} from "node:crypto";

import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {onDocumentCreated, onDocumentDeleted} from "firebase-functions/v2/firestore";

import {db} from "../firebase/admin";

type CounterCollection = "events" | "news" | "organizations";
type CounterField =
  | "commentCount"
  | "likeCount"
  | "registeredCount"
  | "subscriberCount"
  | "viewCount";
export type CounterTransitionDelta = -1 | 0 | 1;

export interface CounterTarget {
  collection: CounterCollection;
  documentId: string;
  field: CounterField;
}

interface CounterTriggerEventMetadata {
  eventId: string;
  eventTime: string;
  sourcePath: string;
}

interface CounterTransitionOptions {
  counterManagedAtomically?: boolean;
  initialCounterContribution?: boolean;
}

interface StoredCounterSourceState {
  counterContributionApplied: boolean;
  target: CounterTarget;
  transition: CounterSourceTransitionState;
}

export interface CounterSourceTransitionState {
  isActive: boolean;
  eventId: string;
  eventTimeNanoseconds: number;
  eventTimeSeconds: number;
}

export interface CounterSourceTransitionDecision {
  counterDelta: CounterTransitionDelta;
  eventOrder: "conflict" | "duplicate" | "newer" | "older";
  nextState: CounterSourceTransitionState;
  shouldPersistState: boolean;
}

export interface CounterContributionDecision {
  counterDelta: CounterTransitionDelta;
  nextContributionApplied: boolean;
  shouldWriteCounter: boolean;
}

export const counterAggregationSourceStateCollection =
  "counterAggregationSourceStates";
export const counterAggregationBaselineCollection =
  "counterAggregationBaselines";
export const counterAggregationDeadLetterCollection =
  "counterAggregationDeadLetters";

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
  retry: true,
};

async function counterAggregationEnabled(): Promise<boolean> {
  const snapshot = await db.collection("appRuntimeConfig").doc("counterAggregation").get();
  return snapshot.data()?.enabled === true;
}

function stringField(data: Record<string, unknown>, field: string): string | undefined {
  const value = data[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function eventParam(params: Record<string, string>, field: string): string | undefined {
  const value = params[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function normalizedSourcePath(sourcePath: string): string {
  const normalized = sourcePath.trim().replace(/^\/+|\/+$/g, "");
  if (normalized.length === 0) {
    throw new Error("Counter aggregation source path is empty.");
  }
  return normalized;
}

export function counterSourceStateDocumentId(sourcePath: string): string {
  return createHash("sha256")
    .update(normalizedSourcePath(sourcePath), "utf8")
    .digest("hex");
}

export function counterTargetBaselineDocumentId(
  collection: CounterCollection,
  documentId: string,
  field: CounterField
): string {
  const normalizedDocumentId = documentId.trim();
  if (normalizedDocumentId.length === 0 || normalizedDocumentId.includes("/")) {
    throw new Error("Counter baseline target must be a Firestore document ID.");
  }
  return createHash("sha256")
    .update(`${collection}/${normalizedDocumentId}#${field}`, "utf8")
    .digest("hex");
}

export function lifetimeViewLegacyBaseline(
  sourceViewCountAtCutover: number,
  activeMarkerCountAtCutover: number
): number {
  if (
    !Number.isSafeInteger(sourceViewCountAtCutover) ||
    sourceViewCountAtCutover < 0 ||
    !Number.isSafeInteger(activeMarkerCountAtCutover) ||
    activeMarkerCountAtCutover < 0
  ) {
    throw new Error("Lifetime view baseline inputs must be non-negative integers.");
  }

  const legacyCount = sourceViewCountAtCutover - activeMarkerCountAtCutover;
  if (legacyCount < 0) {
    throw new Error("Active view markers exceed the captured lifetime view count.");
  }
  return legacyCount;
}

export function decideCounterSourceTransition(
  currentState: CounterSourceTransitionState | undefined,
  incomingState: CounterSourceTransitionState,
  initialIsActive = false
): CounterSourceTransitionDecision {
  if (currentState !== undefined) {
    const comparison = compareTransitionTime(incomingState, currentState);
    if (incomingState.eventId === currentState.eventId) {
      return {
        counterDelta: 0,
        eventOrder: comparison === 0 ? "duplicate" : "conflict",
        nextState: currentState,
        shouldPersistState: false,
      };
    }
    if (comparison < 0) {
      return {
        counterDelta: 0,
        eventOrder: "older",
        nextState: currentState,
        shouldPersistState: false,
      };
    }
    if (comparison === 0) {
      return {
        counterDelta: 0,
        eventOrder: "conflict",
        nextState: currentState,
        shouldPersistState: false,
      };
    }
  }

  const wasActive = (currentState?.isActive ?? false) || initialIsActive;
  const counterDelta: CounterTransitionDelta = incomingState.isActive === wasActive ?
    0 :
    incomingState.isActive ? 1 : -1;
  return {
    counterDelta,
    eventOrder: "newer",
    nextState: incomingState,
    shouldPersistState: true,
  };
}

function compareTransitionTime(
  left: CounterSourceTransitionState,
  right: CounterSourceTransitionState
): number {
  if (left.eventTimeSeconds !== right.eventTimeSeconds) {
    return left.eventTimeSeconds < right.eventTimeSeconds ? -1 : 1;
  }
  if (left.eventTimeNanoseconds === right.eventTimeNanoseconds) {
    return 0;
  }
  return left.eventTimeNanoseconds < right.eventTimeNanoseconds ? -1 : 1;
}

export function counterEventTimestamp(eventTime: string): {
  nanoseconds: number;
  seconds: number;
} {
  const match = eventTime.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/
  );
  if (match === null) {
    throw new Error("Counter aggregation event time is not RFC3339.");
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = match[8] === "Z" ? 0 : Number(match[10]);
  const offsetMinute = match[8] === "Z" ? 0 : Number(match[11]);
  const daysInMonth = month === 2 ?
    (year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28) :
    [4, 6, 9, 11].includes(month) ? 30 : 31;
  if (
    month < 1 || month > 12 ||
    day < 1 || day > daysInMonth ||
    hour > 23 || minute > 59 || second > 59 ||
    offsetHour > 23 || offsetMinute > 59
  ) {
    throw new Error("Counter aggregation event time is invalid.");
  }

  const utcDate = new Date(0);
  utcDate.setUTCFullYear(year, month - 1, day);
  utcDate.setUTCHours(hour, minute, second, 0);
  const offsetDirection = match[9] === "-" ? -1 : 1;
  const offsetSeconds = offsetDirection *
    (offsetHour * 60 * 60 + offsetMinute * 60);
  const seconds = Math.floor(utcDate.getTime() / 1_000) - offsetSeconds;
  const nanoseconds = Number((match[7] ?? "").padEnd(9, "0"));
  // Constructor validation also enforces Firestore's supported timestamp range.
  new Timestamp(seconds, nanoseconds);
  return {nanoseconds, seconds};
}

function incomingTransitionState(
  isActive: boolean,
  metadata: CounterTriggerEventMetadata
): CounterSourceTransitionState {
  const eventId = metadata.eventId.trim();
  if (eventId.length === 0) {
    throw new Error("Counter aggregation event ID is empty.");
  }
  const eventTime = counterEventTimestamp(metadata.eventTime);
  return {
    isActive,
    eventId,
    eventTimeNanoseconds: eventTime.nanoseconds,
    eventTimeSeconds: eventTime.seconds,
  };
}

function storedCounterSourceState(
  data: DocumentData | undefined
): StoredCounterSourceState | undefined {
  if (data === undefined) {
    return undefined;
  }

  const lastEventTime = data.lastEventTime;
  if (
    data.schemaVersion !== 2 ||
    typeof data.sourcePathHash !== "string" ||
    typeof data.isActive !== "boolean" ||
    typeof data.lastEventId !== "string" ||
    data.lastEventId.length === 0 ||
    !(lastEventTime instanceof Timestamp) ||
    !Number.isSafeInteger(data.lastEventTimeSeconds) ||
    !Number.isInteger(data.lastEventTimeNanoseconds) ||
    data.lastEventTimeNanoseconds < 0 ||
    data.lastEventTimeNanoseconds > 999_999_999 ||
    typeof data.counterContributionApplied !== "boolean" ||
    typeof data.counterManagedAtomically !== "boolean" ||
    !isCounterCollection(data.targetCollection) ||
    typeof data.targetDocumentId !== "string" ||
    data.targetDocumentId.length === 0 ||
    !isCounterField(data.counterField)
  ) {
    throw new Error("Counter aggregation source state is malformed.");
  }
  return {
    counterContributionApplied: data.counterContributionApplied,
    target: {
      collection: data.targetCollection,
      documentId: data.targetDocumentId,
      field: data.counterField,
    },
    transition: {
      isActive: data.isActive,
      eventId: data.lastEventId,
      eventTimeNanoseconds: data.lastEventTimeNanoseconds,
      eventTimeSeconds: data.lastEventTimeSeconds,
    },
  };
}

function isCounterCollection(value: unknown): value is CounterCollection {
  return value === "events" || value === "news" || value === "organizations";
}

function isCounterField(value: unknown): value is CounterField {
  return value === "commentCount" ||
    value === "likeCount" ||
    value === "registeredCount" ||
    value === "subscriberCount" ||
    value === "viewCount";
}

function counterTargetsMatch(left: CounterTarget, right: CounterTarget): boolean {
  return left.collection === right.collection &&
    left.documentId === right.documentId &&
    left.field === right.field;
}

function normalizedCounterValue(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.trunc(value));
}

export function counterValueAfterTransition(
  value: unknown,
  delta: CounterTransitionDelta
): number {
  return Math.max(0, normalizedCounterValue(value) + delta);
}

export function decideCounterContribution(
  currentContributionApplied: boolean,
  incomingIsActive: boolean,
  targetExists: boolean,
  counterManagedAtomically: boolean
): CounterContributionDecision {
  const nextContributionApplied = counterManagedAtomically ?
    incomingIsActive :
    incomingIsActive && targetExists;
  const counterDelta: CounterTransitionDelta =
    nextContributionApplied === currentContributionApplied ?
      0 :
      nextContributionApplied ? 1 : -1;
  return {
    counterDelta,
    nextContributionApplied,
    shouldWriteCounter: !counterManagedAtomically &&
      targetExists &&
      counterDelta !== 0,
  };
}

export function duplicateNeedsContributionRecovery(
  transition: CounterSourceTransitionDecision,
  counterContributionApplied: boolean
): boolean {
  return transition.eventOrder === "duplicate" &&
    transition.nextState.isActive &&
    !counterContributionApplied;
}

type CounterInvariantReason =
  | "eventIdentityConflict"
  | "eventTimestampConflict"
  | "inconsistentSourceHash"
  | "invalidEventMetadata"
  | "invalidSourceData"
  | "malformedSourceState"
  | "sourceTargetChanged";

type CounterAggregationOutcome =
  | {kind: "applied" | "ignored" | "recovered"}
  | {deadLetterId: string; kind: "quarantined"; reason: CounterInvariantReason};

function counterDeadLetterDocumentId(sourcePathHash: string, eventId: string): string {
  return createHash("sha256")
    .update(`${sourcePathHash}\u0000${eventId}`, "utf8")
    .digest("hex");
}

function counterDeadLetterData(
  sourcePathHash: string,
  incomingState: CounterSourceTransitionState,
  target: CounterTarget,
  reason: CounterInvariantReason
): DocumentData {
  return {
    schemaVersion: 2,
    sourcePathHash,
    eventId: incomingState.eventId,
    eventTime: new Timestamp(
      incomingState.eventTimeSeconds,
      incomingState.eventTimeNanoseconds
    ),
    eventTimeSeconds: incomingState.eventTimeSeconds,
    eventTimeNanoseconds: incomingState.eventTimeNanoseconds,
    incomingIsActive: incomingState.isActive,
    targetCollection: target.collection,
    targetDocumentId: target.documentId,
    counterField: target.field,
    reason,
    resolutionStatus: "unresolved",
    quarantinedAt: FieldValue.serverTimestamp(),
  };
}

async function quarantineInvalidCounterSourceEvent(
  isActive: boolean,
  metadata: CounterTriggerEventMetadata
): Promise<void> {
  const normalizedPath = (() => {
    try {
      return normalizedSourcePath(metadata.sourcePath);
    } catch {
      return String(metadata.sourcePath);
    }
  })();
  const sourcePathHash = createHash("sha256")
    .update(normalizedPath, "utf8")
    .digest("hex");
  const eventId = metadata.eventId.trim() || "missing-event-id";
  const deadLetterId = counterDeadLetterDocumentId(sourcePathHash, eventId);
  let eventTimeData: DocumentData;
  try {
    const eventTime = counterEventTimestamp(metadata.eventTime);
    eventTimeData = {
      eventTime: new Timestamp(eventTime.seconds, eventTime.nanoseconds),
      eventTimeSeconds: eventTime.seconds,
      eventTimeNanoseconds: eventTime.nanoseconds,
    };
  } catch {
    eventTimeData = {rawEventTime: metadata.eventTime.slice(0, 128)};
  }
  await db.collection(counterAggregationDeadLetterCollection).doc(deadLetterId).set({
    schemaVersion: 2,
    sourcePathHash,
    eventId,
    ...eventTimeData,
    incomingIsActive: isActive,
    reason: "invalidSourceData",
    resolutionStatus: "unresolved",
    quarantinedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  console.error("Counter aggregation source quarantined.", {
    deadLetterId,
    reason: "invalidSourceData",
    sourcePathHash,
  });
}

async function quarantineInvalidCounterEvent(
  target: CounterTarget,
  isActive: boolean,
  metadata: CounterTriggerEventMetadata
): Promise<void> {
  const sourcePathHash = createHash("sha256")
    .update(metadata.sourcePath, "utf8")
    .digest("hex");
  const eventId = metadata.eventId.trim() || "missing-event-id";
  const deadLetterId = counterDeadLetterDocumentId(sourcePathHash, eventId);
  await db.collection(counterAggregationDeadLetterCollection).doc(deadLetterId).set({
    schemaVersion: 2,
    sourcePathHash,
    eventId,
    rawEventTime: metadata.eventTime.slice(0, 128),
    incomingIsActive: isActive,
    targetCollection: target.collection,
    targetDocumentId: target.documentId,
    counterField: target.field,
    reason: "invalidEventMetadata",
    resolutionStatus: "unresolved",
    quarantinedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
  console.error("Counter aggregation event quarantined.", {
    deadLetterId,
    reason: "invalidEventMetadata",
    sourcePathHash,
  });
}

async function applyCounterSourceTransition(
  target: CounterTarget,
  isActive: boolean,
  metadata: CounterTriggerEventMetadata,
  options: CounterTransitionOptions = {}
): Promise<void> {
  let sourcePath: string;
  let incomingState: CounterSourceTransitionState;
  try {
    sourcePath = normalizedSourcePath(metadata.sourcePath);
    incomingState = incomingTransitionState(isActive, metadata);
  } catch {
    await quarantineInvalidCounterEvent(target, isActive, metadata);
    return;
  }

  const stateReference = db
    .collection(counterAggregationSourceStateCollection)
    .doc(counterSourceStateDocumentId(sourcePath));
  const targetReference = db.collection(target.collection).doc(target.documentId);
  const deadLetterId = counterDeadLetterDocumentId(
    stateReference.id,
    incomingState.eventId
  );
  const deadLetterReference = db
    .collection(counterAggregationDeadLetterCollection)
    .doc(deadLetterId);

  const outcome = await db.runTransaction(async (transaction): Promise<CounterAggregationOutcome> => {
    const stateSnapshot = await transaction.get(stateReference);
    const quarantine = (reason: CounterInvariantReason): CounterAggregationOutcome => {
      transaction.set(
        deadLetterReference,
        counterDeadLetterData(stateReference.id, incomingState, target, reason),
        {merge: true}
      );
      return {deadLetterId, kind: "quarantined", reason};
    };

    let storedState: StoredCounterSourceState | undefined;
    try {
      storedState = storedCounterSourceState(stateSnapshot.data());
    } catch {
      return quarantine("malformedSourceState");
    }

    const initialCounterContribution = options.initialCounterContribution === true;
    const decision = decideCounterSourceTransition(
      storedState?.transition,
      incomingState,
      initialCounterContribution
    );
    if (decision.eventOrder === "older") {
      return {kind: "ignored"};
    }
    if (decision.eventOrder === "conflict") {
      return quarantine(
        storedState?.transition.eventId === incomingState.eventId ?
          "eventIdentityConflict" :
          "eventTimestampConflict"
      );
    }

    if (
      storedState !== undefined &&
      stateSnapshot.data()?.sourcePathHash !== stateReference.id
    ) {
      return quarantine("inconsistentSourceHash");
    }
    if (storedState !== undefined && !counterTargetsMatch(storedState.target, target)) {
      return quarantine("sourceTargetChanged");
    }

    if (decision.eventOrder === "duplicate") {
      if (storedState?.transition.isActive !== incomingState.isActive) {
        return quarantine("eventIdentityConflict");
      }
      if (!duplicateNeedsContributionRecovery(
        decision,
        storedState.counterContributionApplied
      )) {
        return {kind: "ignored"};
      }

      if (options.counterManagedAtomically === true) {
        transaction.update(stateReference, {
          counterContributionApplied: true,
          counterManagedAtomically: true,
          recoveredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {kind: "recovered"};
      }

      const recoveryTargetSnapshot = await transaction.get(targetReference);
      if (!recoveryTargetSnapshot.exists) {
        return {kind: "ignored"};
      }
      transaction.update(targetReference, {
        [target.field]: counterValueAfterTransition(
          recoveryTargetSnapshot.get(target.field),
          1
        ),
      });
      transaction.update(stateReference, {
        counterContributionApplied: true,
        recoveredAt: FieldValue.serverTimestamp(),
        targetMissingAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {kind: "recovered"};
    }

    const currentContribution = storedState?.counterContributionApplied === true ||
      initialCounterContribution;
    const shouldReadTarget = options.counterManagedAtomically !== true &&
      (incomingState.isActive || currentContribution);
    const targetSnapshot = shouldReadTarget ?
      await transaction.get(targetReference) :
      undefined;
    const contribution = decideCounterContribution(
      currentContribution,
      incomingState.isActive,
      targetSnapshot?.exists === true,
      options.counterManagedAtomically === true
    );

    const stateData: DocumentData = {
      schemaVersion: 2,
      sourcePathHash: stateReference.id,
      targetCollection: target.collection,
      targetDocumentId: target.documentId,
      counterField: target.field,
      isActive: decision.nextState.isActive,
      lastEventId: decision.nextState.eventId,
      lastEventTime: new Timestamp(
        decision.nextState.eventTimeSeconds,
        decision.nextState.eventTimeNanoseconds
      ),
      lastEventTimeSeconds: decision.nextState.eventTimeSeconds,
      lastEventTimeNanoseconds: decision.nextState.eventTimeNanoseconds,
      counterContributionApplied: contribution.nextContributionApplied,
      counterManagedAtomically: options.counterManagedAtomically === true,
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (
      incomingState.isActive &&
      options.counterManagedAtomically !== true &&
      targetSnapshot?.exists !== true
    ) {
      stateData.targetMissingAt = FieldValue.serverTimestamp();
    }
    transaction.set(stateReference, stateData);

    if (targetSnapshot?.exists === true && contribution.shouldWriteCounter) {
      transaction.update(targetReference, {
        [target.field]: counterValueAfterTransition(
          targetSnapshot.get(target.field),
          contribution.counterDelta
        ),
      });
    }
    return {kind: "applied"};
  });

  if (outcome.kind === "quarantined") {
    console.error("Counter aggregation invariant violation quarantined.", {
      deadLetterId: outcome.deadLetterId,
      reason: outcome.reason,
      sourcePathHash: stateReference.id,
    });
  }
}

function counterTarget(
  collection: CounterCollection,
  documentId: string | undefined,
  field: CounterField
): CounterTarget | undefined {
  return documentId === undefined ? undefined : {collection, documentId, field};
}

async function updateLikeCounter(
  data: Record<string, unknown> | undefined,
  isActive: boolean,
  metadata: CounterTriggerEventMetadata
): Promise<void> {
  if (data === undefined || !(await counterAggregationEnabled())) {
    return;
  }

  let target: CounterTarget;
  try {
    target = counterLikeTarget(data);
  } catch {
    await quarantineInvalidCounterSourceEvent(isActive, metadata);
    return;
  }
  await applyCounterSourceTransition(target, isActive, metadata);
}

export function counterLikeTarget(
  data: Record<string, unknown>
): CounterTarget {
  const definitions: Array<{
    collection: CounterCollection;
    counterField: CounterField;
    dataField: string;
  }> = [
    {dataField: "newsId", collection: "news", counterField: "likeCount"},
    {dataField: "eventId", collection: "events", counterField: "likeCount"},
    {
      dataField: "organizationId",
      collection: "organizations",
      counterField: "likeCount",
    },
    {
      dataField: "subscribedOrganizationId",
      collection: "organizations",
      counterField: "subscriberCount",
    },
  ];
  const present = definitions.filter(({dataField}) => dataField in data);
  if (present.length !== 1) {
    throw new Error("Like must contain exactly one canonical target field.");
  }
  const definition = present[0];
  const documentId = stringField(data, definition.dataField);
  if (documentId === undefined || documentId.includes("/")) {
    throw new Error("Like target must be a Firestore document ID.");
  }
  return {
    collection: definition.collection,
    documentId,
    field: definition.counterField,
  };
}

async function updateRegistrationCounter(
  data: Record<string, unknown> | undefined,
  isActive: boolean,
  metadata: CounterTriggerEventMetadata,
  registrationId?: string
): Promise<void> {
  if (data === undefined || !(await counterAggregationEnabled())) {
    return;
  }

  let counterManagedAtomically = isActive && data.counterManagedAtomically === true;
  if (!isActive) {
    const operationId = registrationCounterDedupeOperationId(data, registrationId);
    if (operationId !== undefined) {
      const operation = await db
        .collection("eventRegistrationCounterOperations")
        .doc(operationId)
        .get();
      counterManagedAtomically = operation.data()?.operation === "unregister";
    }
  }

  const target = counterTarget(
    "events",
    stringField(data, "eventId"),
    "registeredCount"
  );
  if (target !== undefined) {
    await applyCounterSourceTransition(
      target,
      isActive,
      metadata,
      {
        counterManagedAtomically,
        // A server-managed registration proves that its create callable already
        // contributed +1, even if the create trigger state has not arrived yet.
        initialCounterContribution: !isActive &&
          data.counterManagedAtomically === true,
      }
    );
  }
}

export function registrationCounterDedupeOperationId(
  data: Record<string, unknown> | undefined,
  registrationId?: string
): string | undefined {
  return data === undefined ?
    registrationId :
    stringField(data, "counterOperationId") ?? registrationId;
}

async function updateCounterFromParam(
  collection: CounterCollection,
  documentId: string | undefined,
  field: CounterField,
  isActive: boolean,
  metadata: CounterTriggerEventMetadata
): Promise<void> {
  if (!(await counterAggregationEnabled())) {
    return;
  }

  const target = counterTarget(collection, documentId, field);
  if (target !== undefined) {
    await applyCounterSourceTransition(target, isActive, metadata);
  }
}

export const aggregateLikeCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "likes/{likeId}"},
  async (event) => {
    await updateLikeCounter(event.data?.data(), true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateLikeCounterOnDelete = onDocumentDeleted(
  {...triggerOptions, document: "likes/{likeId}"},
  async (event) => {
    await updateLikeCounter(event.data?.data(), false, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateRegistrationCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "registrations/{registrationId}"},
  async (event) => {
    await updateRegistrationCounter(event.data?.data(), true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    }, event.params.registrationId);
  }
);

export const aggregateRegistrationCounterOnDelete = onDocumentDeleted(
  {...triggerOptions, document: "registrations/{registrationId}"},
  async (event) => {
    await updateRegistrationCounter(event.data?.data(), false, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    }, event.params.registrationId);
  }
);

export const aggregateNewsCommentCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "news/{newsId}/comments/{commentId}"},
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "commentCount", true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateNewsCommentCounterOnDelete = onDocumentDeleted(
  {...triggerOptions, document: "news/{newsId}/comments/{commentId}"},
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "commentCount", false, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateEventCommentCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "events/{eventId}/comments/{commentId}"},
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "commentCount", true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateEventCommentCounterOnDelete = onDocumentDeleted(
  {...triggerOptions, document: "events/{eventId}/comments/{commentId}"},
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "commentCount", false, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateNewsViewCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "users/{uid}/newsViews/{newsId}"},
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "viewCount", true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);

export const aggregateEventViewCounterOnCreate = onDocumentCreated(
  {...triggerOptions, document: "users/{uid}/eventViews/{eventId}"},
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "viewCount", true, {
      eventId: event.id,
      eventTime: event.time,
      sourcePath: event.document,
    });
  }
);
