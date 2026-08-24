import {createHash} from "node:crypto";

export const counterTargetFields = Object.freeze({
  news: Object.freeze(["likeCount", "commentCount", "viewCount"]),
  events: Object.freeze([
    "likeCount",
    "commentCount",
    "registeredCount",
    "viewCount",
  ]),
  organizations: Object.freeze(["likeCount", "subscriberCount"]),
});

export function counterMigrationSourceStateID(sourcePath) {
  return createHash("sha256")
    .update(normalizedPathParts(sourcePath).join("/"), "utf8")
    .digest("hex");
}

export function counterMigrationBaselineID(collection, documentId, field) {
  const normalizedDocumentId = requiredDocumentID(documentId, "target document ID");
  counterTargetKey(collection, normalizedDocumentId, field);
  return createHash("sha256")
    .update(`${collection}/${normalizedDocumentId}#${field}`, "utf8")
    .digest("hex");
}

export function parseRfc3339TimestampParts(value) {
  if (typeof value !== "string") {
    throw new Error("Timestamp must be an RFC3339 string.");
  }
  const match = value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,9}))?(Z|([+-])(\d{2}):(\d{2}))$/
  );
  if (match === null) {
    throw new Error("Timestamp must be an RFC3339 string.");
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
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth ||
    hour > 23 || minute > 59 || second > 59 ||
    offsetHour > 23 || offsetMinute > 59) {
    throw new Error("Timestamp is not a valid calendar instant.");
  }
  const utcDate = new Date(0);
  utcDate.setUTCFullYear(year, month - 1, day);
  utcDate.setUTCHours(hour, minute, second, 0);
  const offsetDirection = match[9] === "-" ? -1 : 1;
  return {
    seconds: Math.floor(utcDate.getTime() / 1_000) - offsetDirection *
      (offsetHour * 60 * 60 + offsetMinute * 60),
    nanoseconds: Number((match[7] ?? "").padEnd(9, "0")),
  };
}

export function counterMigrationSourceDescriptor(sourcePath, data) {
  if (!isRecord(data)) {
    throw new Error("Source data is not an object.");
  }

  const parts = normalizedPathParts(sourcePath);
  if (parts.length === 2 && parts[0] === "likes") {
    return likeDescriptor(sourcePath, data);
  }
  if (parts.length === 2 && parts[0] === "registrations") {
    return descriptor(
      sourcePath,
      "events",
      requiredDocumentID(data.eventId, "registration.eventId"),
      "registeredCount",
      data.counterManagedAtomically === true
    );
  }
  if (parts.length === 4 && parts[2] === "comments") {
    if (parts[0] !== "news" && parts[0] !== "events") {
      return undefined;
    }
    const parentType = parts[0] === "news" ? "news" : "event";
    if (data.parentType !== parentType || data.parentId !== parts[1]) {
      throw new Error("Comment parent fields do not match its canonical path.");
    }
    return descriptor(
      sourcePath,
      parts[0],
      requiredDocumentID(parts[1], "comment parent ID"),
      "commentCount",
      false
    );
  }
  if (parts.length === 4 && parts[0] === "users") {
    if (parts[2] !== "newsViews" && parts[2] !== "eventViews") {
      return undefined;
    }
    const isNews = parts[2] === "newsViews";
    const field = isNews ? "newsId" : "eventId";
    const targetID = requiredDocumentID(parts[3], "view target ID");
    if ((field in data && data[field] !== targetID) ||
      ("userId" in data && data.userId !== parts[1])) {
      throw new Error("View marker fields do not match its canonical path.");
    }
    return descriptor(
      sourcePath,
      isNews ? "news" : "events",
      targetID,
      "viewCount",
      false
    );
  }

  throw new Error(`Unsupported counter source path: ${sourcePath}`);
}

export function counterTargetKey(collection, documentId, field) {
  if (!(collection in counterTargetFields) ||
    !counterTargetFields[collection].includes(field)) {
    throw new Error("Unsupported counter target tuple.");
  }
  const normalizedDocumentId = requiredDocumentID(
    documentId,
    "target document ID"
  );
  return JSON.stringify([
    collection,
    normalizedDocumentId,
    field,
  ]);
}

export function counterTargetFromKey(key) {
  let values;
  try {
    values = JSON.parse(key);
  } catch {
    throw new Error("Counter target key is not valid JSON.");
  }
  if (!Array.isArray(values) || values.length !== 3) {
    throw new Error("Counter target key has the wrong shape.");
  }
  const [collection, documentId, field] = values;
  counterTargetKey(collection, documentId, field);
  return {collection, documentId: documentId.trim(), field};
}

export function incrementCounterTargetCount(counts, target, maximumTargets) {
  const key = counterTargetKey(target.collection, target.documentId, target.field);
  if (!counts.has(key) && counts.size >= maximumTargets) {
    throw new Error(`Counter target limit ${maximumTargets} exceeded.`);
  }
  counts.set(key, (counts.get(key) ?? 0) + 1);
  return key;
}

export function normalizedMigrationCounter(value) {
  if (value === undefined) {
    return 0;
  }
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error("Public counter is not a non-negative safe integer.");
  }
  return value;
}

export function lifetimeViewBaselinePlan(sourceViewCount, activeMarkerCount) {
  const currentCount = normalizedMigrationCounter(sourceViewCount);
  if (!Number.isSafeInteger(activeMarkerCount) || activeMarkerCount < 0) {
    throw new Error("Active marker count is not a non-negative safe integer.");
  }
  const legacyCount = currentCount - activeMarkerCount;
  if (legacyCount < 0) {
    throw new Error("Active view markers exceed the captured lifetime view count.");
  }
  return {activeMarkerCount, legacyCount, sourceViewCount: currentCount};
}

export function classifyCounterBackfillState(existing, desired, cutover) {
  if (existing === undefined) {
    return {kind: "create"};
  }
  if (!isRecord(existing)) {
    return {kind: "conflict", reason: "malformed-state"};
  }

  const existingTime = timestampParts({
    seconds: existing.lastEventTimeSeconds,
    nanoseconds: existing.lastEventTimeNanoseconds,
  });
  if (existingTime === undefined || timestampParts(existing.lastEventTime) === undefined) {
    return {kind: "conflict", reason: "malformed-state-time"};
  }
  const order = compareTimestampParts(existingTime, cutover);
  if (order > 0) {
    return {kind: "conflict", reason: "state-newer-than-cutover"};
  }
  if (!sameStateTarget(existing, desired)) {
    return {kind: "conflict", reason: "state-target-mismatch"};
  }
  if (order === 0) {
    if (existing.lastEventId !== desired.lastEventId) {
      return {kind: "conflict", reason: "cutover-event-conflict"};
    }
    return sameBackfillState(existing, desired) ?
      {kind: "verified"} :
      {kind: "conflict", reason: "same-generation-state-mismatch"};
  }
  return {kind: "replace-older"};
}

export function classifyCounterBaseline(existing, desired) {
  if (existing === undefined) {
    return {kind: "create"};
  }
  if (!isRecord(existing)) {
    return {kind: "conflict", reason: "malformed-baseline"};
  }
  const existingCutover = timestampParts({
    seconds: existing.cutoverTimeSeconds,
    nanoseconds: existing.cutoverTimeNanoseconds,
  });
  const desiredCutover = timestampParts({
    seconds: desired.cutoverTimeSeconds,
    nanoseconds: desired.cutoverTimeNanoseconds,
  });
  if (existingCutover === undefined || desiredCutover === undefined ||
    timestampParts(existing.cutoverAt) === undefined) {
    return {kind: "conflict", reason: "malformed-baseline-cutover"};
  }
  const equal = existing.schemaVersion === desired.schemaVersion &&
    existing.targetCollection === desired.targetCollection &&
    existing.targetDocumentId === desired.targetDocumentId &&
    existing.counterField === desired.counterField &&
    existing.legacyCount === desired.legacyCount &&
    existing.sourceViewCountAtCutover === desired.sourceViewCountAtCutover &&
    existing.activeMarkerCountAtCutover === desired.activeMarkerCountAtCutover &&
    existing.migrationGeneration === desired.migrationGeneration &&
    compareTimestampParts(existingCutover, desiredCutover) === 0;
  return equal ?
    {kind: "verified"} :
    {kind: "conflict", reason: "immutable-baseline-mismatch"};
}

export function compareTimestampParts(left, right) {
  if (left.seconds !== right.seconds) {
    return left.seconds < right.seconds ? -1 : 1;
  }
  if (left.nanoseconds === right.nanoseconds) {
    return 0;
  }
  return left.nanoseconds < right.nanoseconds ? -1 : 1;
}

export function assertCounterCutoverNotFuture(
  cutover,
  nowMilliseconds = Date.now()
) {
  const normalizedCutover = timestampParts(cutover);
  if (normalizedCutover === undefined ||
    !Number.isSafeInteger(nowMilliseconds) || nowMilliseconds < 0) {
    throw new Error("Counter cutover time is invalid.");
  }
  const nowSeconds = Math.floor(nowMilliseconds / 1_000);
  const nowNanoseconds = (nowMilliseconds - nowSeconds * 1_000) * 1_000_000;
  if (compareTimestampParts(normalizedCutover, {
    seconds: nowSeconds,
    nanoseconds: nowNanoseconds,
  }) > 0) {
    throw new Error("Counter cutover time must not be in the future.");
  }
}

export function classifyCounterDeadLetter(data) {
  if (!isRecord(data)) {
    return {kind: "invalid", reason: "malformed-dead-letter"};
  }
  if (data.resolutionStatus === undefined ||
    data.resolutionStatus === "unresolved") {
    return {kind: "unresolved"};
  }
  if (data.resolutionStatus !== "resolved") {
    return {kind: "invalid", reason: "invalid-resolution-status"};
  }
  if (timestampParts(data.resolvedAt) === undefined ||
    !nonEmptyString(data.resolvedBy) ||
    !nonEmptyString(data.resolutionReason) ||
    !nonEmptyString(data.resolutionTicket)) {
    return {kind: "invalid", reason: "incomplete-resolution-evidence"};
  }
  return {kind: "resolved"};
}

export function timestampParts(value) {
  if (!isRecord(value) ||
    !Number.isSafeInteger(value.seconds) ||
    !Number.isInteger(value.nanoseconds) ||
    value.nanoseconds < 0 ||
    value.nanoseconds > 999_999_999) {
    return undefined;
  }
  return {seconds: value.seconds, nanoseconds: value.nanoseconds};
}

export function stableReportEnvelope(payload) {
  // Normalize exactly as JSON will be persisted so omitted undefined object
  // fields cannot produce a digest that differs from the signed report bytes.
  const jsonPayload = JSON.parse(JSON.stringify(payload));
  const canonicalPayload = stableStringify(jsonPayload);
  return {
    ...jsonPayload,
    reportDigestSha256: createHash("sha256")
      .update(canonicalPayload, "utf8")
      .digest("hex"),
  };
}

export function boundedChunks(items, size) {
  if (!Number.isInteger(size) || size <= 0) {
    throw new Error("Chunk size must be a positive integer.");
  }
  const chunks = [];
  for (let offset = 0; offset < items.length; offset += size) {
    chunks.push(items.slice(offset, offset + size));
  }
  return chunks;
}

function likeDescriptor(sourcePath, data) {
  const targets = [
    ["newsId", "news", "likeCount"],
    ["eventId", "events", "likeCount"],
    ["organizationId", "organizations", "likeCount"],
    ["subscribedOrganizationId", "organizations", "subscriberCount"],
  ].flatMap(([dataField, collection, counterField]) => {
    if (!(dataField in data)) {
      return [];
    }
    return [{
      collection,
      counterField,
      documentId: requiredDocumentID(data[dataField], `like.${dataField}`),
    }];
  });
  if (targets.length !== 1) {
    throw new Error("Like must contain exactly one canonical target field.");
  }
  const target = targets[0];
  return descriptor(
    sourcePath,
    target.collection,
    target.documentId,
    target.counterField,
    false
  );
}

function descriptor(
  sourcePath,
  collection,
  documentId,
  field,
  counterManagedAtomically
) {
  return {
    sourcePath: normalizedPathParts(sourcePath).join("/"),
    target: {collection, documentId, field},
    counterManagedAtomically,
  };
}

function normalizedPathParts(path) {
  if (typeof path !== "string") {
    throw new Error("Source path is not a string.");
  }
  const normalized = path.trim().replace(/^\/+|\/+$/g, "");
  const parts = normalized.split("/");
  if (normalized.length === 0 || parts.some((part) => part.length === 0)) {
    throw new Error("Source path is malformed.");
  }
  return parts;
}

function requiredDocumentID(value, label) {
  if (typeof value !== "string" ||
    value.trim().length === 0 ||
    value.includes("/")) {
    throw new Error(`${label} is not a Firestore document ID.`);
  }
  return value.trim();
}

function sameStateTarget(existing, desired) {
  return existing.sourcePathHash === desired.sourcePathHash &&
    existing.targetCollection === desired.targetCollection &&
    existing.targetDocumentId === desired.targetDocumentId &&
    existing.counterField === desired.counterField;
}

function sameBackfillState(existing, desired) {
  return existing.schemaVersion === desired.schemaVersion &&
    existing.isActive === true &&
    existing.counterContributionApplied === true &&
    existing.counterManagedAtomically === desired.counterManagedAtomically &&
    existing.migrationGeneration === desired.migrationGeneration;
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableStringify(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
