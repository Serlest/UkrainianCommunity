const analyticsTimeZone = "Europe/Vienna";

// Constructing Intl formatters repeatedly is measurably more expensive than
// formatting with a cached instance. Cloud Functions handles requests in a
// long-lived JavaScript isolate, so one immutable formatter is safe to reuse.
const analyticsDateFormatter = new Intl.DateTimeFormat("en-CA", {
  timeZone: analyticsTimeZone,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

export function dailyDocumentIDFor(date: Date): string {
  const parts = analyticsDateParts(date);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function datedAnalyticsDocumentIDs(
  dayCount: number,
  now: Date = new Date()
): string[] {
  const count = Math.max(0, Math.floor(dayCount));
  if (count === 0) {
    return [];
  }

  const parts = analyticsDateParts(now);
  const anchor = new Date(Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    12
  ));

  return Array.from({length: count}, (_, offset) => {
    const date = new Date(anchor);
    date.setUTCDate(anchor.getUTCDate() - offset);
    return dailyDocumentIDFor(date);
  });
}

function analyticsDateParts(date: Date): {
  year: string;
  month: string;
  day: string;
} {
  const parts = analyticsDateFormatter.formatToParts(date);

  return {
    year: datePart(parts, "year"),
    month: datePart(parts, "month"),
    day: datePart(parts, "day"),
  };
}

function datePart(parts: Intl.DateTimeFormatPart[], type: string): string {
  return parts.find((part) => part.type === type)?.value ?? "00";
}
