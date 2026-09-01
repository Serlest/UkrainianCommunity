export const contentPlanningReceiptRetentionMonths = 6;

const expectationKeys = [
  "expect-updates",
  "expect-active",
  "expect-linked",
  "expect-unresolved",
  "expect-archived",
  "expect-invalid",
];

const terminalMediaStatuses = new Set([
  "alreadyMissing",
  "deletedArchivedCopy",
  "deletedRedundantCopy",
  "noMedia",
  "pending",
  "retainInvalidPath",
  "retainLiveReference",
  "retainMissingLiveContent",
  "retainMissingLiveImage",
  "retainUnresolved",
]);

export function classifyContentPlanningRetentionDraft(draft) {
  const data = draft?.data ?? {};
  if (data.state !== "completed" && data.state !== "archived") {
    return {status: "active"};
  }
  const baseMilliseconds = retentionBaseMilliseconds(data);
  if (baseMilliseconds === undefined) {
    return {status: "invalid", reason: "missing-retention-base"};
  }
  const retentionExpiresAtMilliseconds = addUtcCalendarMonths(
    baseMilliseconds,
    contentPlanningReceiptRetentionMonths
  );
  const existingRetentionMilliseconds = timestampMilliseconds(data.retentionExpiresAt);
  const existingMediaStatus = nonEmptyString(data.draftMediaCleanupStatus);
  if (existingMediaStatus && !terminalMediaStatuses.has(existingMediaStatus)) {
    return {status: "invalid", reason: "invalid-media-cleanup-status"};
  }

  let category;
  if (data.state === "archived") {
    category = "archived";
  } else if (nonEmptyString(data.publishedContentId) &&
      ["news", "event"].includes(data.publishedContentKind)) {
    category = "linked";
  } else {
    category = "unresolved";
  }

  const generatedImage = recordValue(data.generatedImage);
  const hasGeneratedImage = Boolean(
    nonEmptyString(generatedImage?.url) && nonEmptyString(generatedImage?.storagePath)
  );
  const nextMediaStatus = existingMediaStatus ?? (hasGeneratedImage ? "pending" : "noMedia");
  const needsRetentionUpdate = existingRetentionMilliseconds !== retentionExpiresAtMilliseconds;
  const needsMediaStatusUpdate = existingMediaStatus === undefined;

  return {
    status: needsRetentionUpdate || needsMediaStatusUpdate ? "update" : "alreadyPrepared",
    category,
    retentionExpiresAtMilliseconds,
    mediaCleanupStatus: nextMediaStatus,
    requestsMediaCleanup: nextMediaStatus === "pending" && existingMediaStatus !== "pending",
  };
}

export function summarizeContentPlanningRetention(classifications) {
  const summary = {
    total: classifications.length,
    updates: 0,
    alreadyPrepared: 0,
    active: 0,
    linked: 0,
    unresolved: 0,
    archived: 0,
    invalid: 0,
  };
  for (const item of classifications) {
    const result = item.result;
    if (result.status === "active" || result.status === "invalid" ||
        result.status === "alreadyPrepared") {
      summary[result.status] += 1;
    } else if (result.status === "update") {
      summary.updates += 1;
    }
    if (result.category === "linked" || result.category === "unresolved" ||
        result.category === "archived") {
      summary[result.category] += 1;
    }
  }
  return summary;
}

export function parseContentPlanningRetentionBackfillOptions(argumentsList) {
  const values = new Map();
  let apply = false;
  for (const argument of argumentsList) {
    if (argument === "--apply") apply = true;
    else if (argument.startsWith("--") && argument.includes("=")) {
      const separator = argument.indexOf("=");
      values.set(argument.slice(2, separator), argument.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }

  const projectId = requiredOption(values.get("project"), "--project");
  if (apply && values.get("confirm-project") !== projectId) {
    throw new Error("--apply requires --confirm-project to exactly match --project.");
  }
  const providedExpectations = expectationKeys.filter((key) => values.has(key));
  if (providedExpectations.length !== 0 && providedExpectations.length !== expectationKeys.length) {
    throw new Error(`Provide all retention expectations together: ${expectationKeys.join(", ")}.`);
  }
  if (apply && providedExpectations.length !== expectationKeys.length) {
    throw new Error("--apply requires every expectation from a fresh production dry-run.");
  }
  const expectations = providedExpectations.length === expectationKeys.length
    ? Object.fromEntries(expectationKeys.map((key) => [
      expectationName(key),
      nonNegativeInteger(values.get(key), `--${key}`),
    ]))
    : undefined;

  return {projectId, apply, expectations};
}

export function assertContentPlanningRetentionExpectations(summary, expectations) {
  if (!expectations) return;
  for (const key of ["updates", "active", "linked", "unresolved", "archived", "invalid"]) {
    if (summary[key] !== expectations[key]) {
      throw new Error(
        `Retention preflight mismatch for ${key}: expected ${expectations[key]}, ` +
        `received ${summary[key]}. No writes were made.`
      );
    }
  }
}

export function addUtcCalendarMonths(milliseconds, months) {
  const date = new Date(milliseconds);
  if (!Number.isFinite(date.getTime())) throw new Error("Retention base date is invalid.");
  const originalDay = date.getUTCDate();
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth() + 1,
    0
  )).getUTCDate();
  date.setUTCDate(Math.min(originalDay, lastDay));
  return date.getTime();
}

function retentionBaseMilliseconds(data) {
  const candidates = data.state === "completed"
    ? [data.completedAt, data.updatedAt, data.historyBackfilledAt]
    : [data.archivedAt, data.updatedAt];
  return candidates.map(timestampMilliseconds).find((value) => value !== undefined);
}

function timestampMilliseconds(value) {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toMillis === "function") {
    const milliseconds = value.toMillis();
    return Number.isFinite(milliseconds) ? milliseconds : undefined;
  }
  if (typeof value === "string") {
    const milliseconds = Date.parse(value);
    return Number.isFinite(milliseconds) ? milliseconds : undefined;
  }
  return undefined;
}

function expectationName(key) {
  return key.slice("expect-".length).replace(/-([a-z])/g, (_match, value) => value.toUpperCase());
}

function requiredOption(value, name) {
  const normalized = nonEmptyString(value);
  if (!normalized) throw new Error(`${name} is required.`);
  return normalized;
}

function nonNegativeInteger(value, name) {
  if (!/^\d+$/.test(value ?? "")) throw new Error(`${name} must be a non-negative integer.`);
  return Number(value);
}

function nonEmptyString(value) {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function recordValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : undefined;
}
