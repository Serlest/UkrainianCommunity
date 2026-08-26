import {Timestamp} from "firebase-admin/firestore";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stableValue(value: unknown): unknown {
  if (value instanceof Timestamp) {
    return value.toMillis();
  }
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (isRecord(value)) {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, stableValue(value[key])])
    );
  }
  return value ?? null;
}

export function eventPublishingFieldChanged(
  before: Record<string, unknown>,
  after: Record<string, unknown>
): boolean {
  const fields = [
    "title", "localizations", "startDate", "endDate", "occurrences",
    "venue", "address", "locationNote", "latitude", "longitude", "city",
    "participationMode", "externalAction", "price", "pricing", "capacity",
    "moderationStatus", "registrationState",
  ];
  return fields.some((field) =>
    JSON.stringify(stableValue(before[field])) !== JSON.stringify(stableValue(after[field]))
  );
}

export function nextEventStartMillis(
  data: Record<string, unknown> | undefined,
  nowMillis: number
): number | undefined {
  const occurrenceStarts = Array.isArray(data?.occurrences)
    ? data.occurrences.flatMap((value) => {
      if (!isRecord(value) || value.status === "cancelled") return [];
      const startDate = value.startDate;
      return startDate instanceof Timestamp && startDate.toMillis() >= nowMillis
        ? [startDate.toMillis()]
        : [];
    })
    : [];
  if (occurrenceStarts.length > 0) {
    return Math.min(...occurrenceStarts);
  }

  const startDate = data?.startDate;
  return startDate instanceof Timestamp ? startDate.toMillis() : undefined;
}
