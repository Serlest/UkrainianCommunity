import {createHash} from "node:crypto";

export const analyticsSchemaVersion = 2;
export const analyticsSchemaStatePath = "analyticsSchemaState/current";
export const analyticsSchemaArchiveCollection = "analyticsSchemaCutoverArchives";

const safeGenerationPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{7,119}$/;
const commitPattern = /^[a-f0-9]{40}$/i;

export function assertSafeAnalyticsCutoverGeneration(generation) {
  if (typeof generation !== "string" || !safeGenerationPattern.test(generation)) {
    throw new Error(
      "generation must be 8-120 characters using letters, digits, dot, underscore, or hyphen"
    );
  }
  return generation;
}

export function assertDeployedCommit(commit) {
  if (typeof commit !== "string" || !commitPattern.test(commit)) {
    throw new Error("deployed-commit must be the full 40-character Git SHA");
  }
  return commit.toLowerCase();
}

export function analyticsCutoverDayID(date) {
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) {
    throw new Error("cutover date must be valid");
  }
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

export function analyticsCutoverWindowDayIDs(dayCount, date) {
  if (!Number.isInteger(dayCount) || dayCount < 0 || dayCount > 60) {
    throw new Error("cutover day count must be an integer between 0 and 60");
  }
  const dayID = analyticsCutoverDayID(date);
  const [year, month, day] = dayID.split("-").map(Number);
  const anchor = new Date(Date.UTC(year, month - 1, day, 12));
  return Array.from({length: dayCount}, (_, offset) => {
    const candidate = new Date(anchor);
    candidate.setUTCDate(anchor.getUTCDate() - offset);
    return analyticsCutoverDayID(candidate);
  });
}

export function normalizedAnalyticsSchemaState(data) {
  if (data?.schemaVersion !== analyticsSchemaVersion ||
    !["prepared", "finalizing", "complete", "aborted"].includes(data?.status) ||
    typeof data?.generation !== "string" ||
    data.generation.trim().length === 0 ||
    typeof data?.cutoverDay !== "string") {
    return undefined;
  }
  return {
    schemaVersion: analyticsSchemaVersion,
    status: data.status,
    generation: data.generation.trim(),
    cutoverDay: data.cutoverDay,
  };
}

export function isValidAnalyticsDetailCoverage(
  data,
  expectedPeriodDocumentID,
  expectedSourceCount,
  expectedCoverageStartDay
) {
  if (data?.periodId !== expectedPeriodDocumentID ||
    !Number.isInteger(expectedSourceCount) ||
    expectedSourceCount < 1 ||
    typeof expectedCoverageStartDay !== "string") {
    return false;
  }

  const sourceDocumentIDs = data.sourceDocumentIDs;
  const coveredSourceDocumentIDs = data.coveredSourceDocumentIDs;
  if (!Array.isArray(sourceDocumentIDs) ||
    sourceDocumentIDs.length !== expectedSourceCount ||
    new Set(sourceDocumentIDs).size !== sourceDocumentIDs.length ||
    !Array.isArray(coveredSourceDocumentIDs) ||
    data.coverageStartDay !== expectedCoverageStartDay ||
    typeof data.isPartialCoverage !== "boolean") {
    return false;
  }

  const firstDay = sourceDocumentIDs[0];
  if (typeof firstDay !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(firstDay)) {
    return false;
  }
  const expectedSourceDocumentIDs = analyticsCutoverWindowDayIDs(
    expectedSourceCount,
    new Date(`${firstDay}T12:00:00.000Z`)
  );
  if (!sameStringArray(sourceDocumentIDs, expectedSourceDocumentIDs)) {
    return false;
  }

  const expectedCoveredDocumentIDs = sourceDocumentIDs.filter(
    (documentID) => documentID >= expectedCoverageStartDay
  );
  return sameStringArray(coveredSourceDocumentIDs, expectedCoveredDocumentIDs) &&
    data.isPartialCoverage ===
      (expectedCoveredDocumentIDs.length < sourceDocumentIDs.length);
}

function sameStringArray(left, right) {
  return left.length === right.length &&
    left.every((value, index) => value === right[index]);
}

export function datedLegacySnapshotData(data, cutoverDay, generation, updatedAt) {
  const source = data === undefined ? {} : structuredCloneCompatible(data);
  delete source.sourceDocumentIDs;
  return {
    ...source,
    dateDocumentID: cutoverDay,
    sourceDocumentID: "today",
    snapshotDocumentID: cutoverDay,
    schemaVersion: analyticsSchemaVersion,
    cutoverGeneration: generation,
    updatedAt,
  };
}

export function analyticsCutoverDigest(records) {
  const hash = createHash("sha256");
  for (const record of [...records].sort((left, right) =>
    left.path.localeCompare(right.path)
  )) {
    hash.update(record.path);
    hash.update("\0");
    hash.update(stableJSONString(record.data));
    hash.update("\n");
  }
  return hash.digest("hex");
}

export function isDrainWindowSatisfied(now, deployedAt, minimumDrainSeconds) {
  return now.getTime() - deployedAt.getTime() >= minimumDrainSeconds * 1_000;
}

/**
 * v1 accidentally copied the lifetime-to-date deleted-account total into each
 * dated document. Convert an oldest-to-newest cumulative sequence into the
 * true per-day increments. A decrease is ambiguous corruption/reset and must
 * stop the migration instead of silently inventing data.
 */
export function analyticsDailyDeltasFromCumulative(countsOldestFirst) {
  if (!Array.isArray(countsOldestFirst) || countsOldestFirst.length < 2) {
    throw new Error("cumulative analytics series needs a predecessor and one day");
  }
  for (const count of countsOldestFirst) {
    if (!Number.isSafeInteger(count) || count < 0) {
      throw new Error("cumulative analytics values must be non-negative safe integers");
    }
  }

  return countsOldestFirst.slice(1).map((count, index) => {
    const previous = countsOldestFirst[index];
    if (count < previous) {
      throw new Error("cumulative deleted-account series decreased");
    }
    return count - previous;
  });
}

export function stableJSONString(value) {
  return JSON.stringify(canonicalValue(value));
}

function canonicalValue(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new Error("analytics cutover data contains a non-finite number");
    }
    return value;
  }
  if (typeof value === "bigint") {
    return {__bigint: value.toString()};
  }
  if (value instanceof Date) {
    return {__date: value.toISOString()};
  }
  if (Array.isArray(value)) {
    return value.map(canonicalValue);
  }
  if (typeof value?.seconds === "number" &&
    typeof value?.nanoseconds === "number" &&
    typeof value?.toDate === "function") {
    return {
      __timestampSeconds: value.seconds,
      __timestampNanoseconds: value.nanoseconds,
    };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return {__bytes: Buffer.from(value).toString("base64")};
  }
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalValue(value[key])])
    );
  }
  throw new Error(`analytics cutover data contains unsupported ${typeof value}`);
}

function structuredCloneCompatible(value) {
  if (Array.isArray(value)) {
    return value.map(structuredCloneCompatible);
  }
  if (value !== null && typeof value === "object") {
    // Preserve Firestore Timestamp/GeoPoint/DocumentReference instances. They
    // are immutable value objects and can safely be reused in a replacement
    // document; cloning them as plain objects would change their wire type.
    if (typeof value.toDate === "function" ||
      typeof value.isEqual === "function" ||
      Buffer.isBuffer(value) ||
      value instanceof Uint8Array) {
      return value;
    }
    return Object.fromEntries(
      Object.entries(value).map(([key, nested]) => [key, structuredCloneCompatible(nested)])
    );
  }
  return value;
}
