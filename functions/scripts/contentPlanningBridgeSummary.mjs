const trackingQueryParameters = new Set([
  "dclid",
  "fbclid",
  "gclid",
  "igshid",
  "mc_cid",
  "mc_eid",
]);

export function buildContentPlanningSummary({id, defaultKind, fields}) {
  const payload = record(fields.payload);
  const kind = firstString(fields.kind, defaultKind);
  const titleValues = uniqueStrings([
    fields.title,
    payload.title,
    payload.germanTitle,
    ...localizedTitles(fields.localizations),
  ]);
  const sources = array(fields.sources, payload.sources);
  const externalAction = record(fields.externalAction);
  const payloadExternalAction = record(payload.externalAction);
  const sourceURLs = uniqueStrings([
    fields.sourceURL,
    payload.sourceURL,
    payload.sourceInput,
    sources.find((source) => record(source).isPrimary === true)?.url,
    ...sources.map((source) => record(source).url),
  ]);
  const actionURLs = uniqueStrings([
    fields.externalActionURL,
    payload.externalActionURL,
    externalAction.url,
    payloadExternalAction.url,
  ]);
  const contextualURLs = uniqueStrings([
    fields.organizerURL,
    payload.organizerURL,
    fields.contactURL,
    payload.contactURL,
  ]);
  const startDate = firstString(fields.startDate, payload.startDate);
  const endDate = firstString(fields.endDate, payload.endDate);
  const occurrences = summarizedOccurrences(fields, payload, startDate, endDate);
  const organizerName = firstString(
    fields.organizerName,
    payload.eventOrganizerName,
    payload.organizerName,
    fields.organizationName,
    payload.organizationName
  );
  const venue = firstString(fields.venue, payload.venue);
  const address = firstString(fields.address, payload.address);
  const city = firstString(fields.city, payload.city);
  const place = uniqueStrings([venue, address, city]).join(" ");
  const normalizedTitles = uniqueStrings(titleValues.map(normalizeDedupeText));
  const normalizedOrganizerName = normalizeDedupeText(organizerName);
  const normalizedPlace = normalizeDedupeText(place);
  const canonicalURLs = uniqueStrings(sourceURLs.map(canonicalizeURL));
  const canonicalActionURLs = uniqueStrings(actionURLs.map(canonicalizeURL));
  const canonicalContextualURLs = uniqueStrings(contextualURLs.map(canonicalizeURL));
  const occurrenceStartDates = uniqueStrings(occurrences.map((occurrence) => occurrence.startDate));
  const eventCompositeKeys = buildEventCompositeKeys({
    kind,
    normalizedTitles,
    normalizedOrganizerName,
    normalizedPlace,
    occurrenceStartDates,
  });
  const actionCompositeKeys = buildActionCompositeKeys({
    kind,
    canonicalActionURLs,
    normalizedTitles,
    occurrenceStartDates,
  });

  return compactObject({
    id,
    kind,
    state: firstString(fields.state, fields.moderationStatus),
    title: titleValues[0],
    titles: titleValues,
    normalizedTitles,
    sourceURL: sourceURLs[0],
    sourceURLs,
    canonicalURLs,
    actionURLs,
    canonicalActionURLs,
    contextualURLs,
    canonicalContextualURLs,
    eventCompositeKeys,
    actionCompositeKeys,
    startDate,
    endDate,
    occurrences,
    occurrenceStartDates,
    organizerName,
    normalizedOrganizerName,
    organizationId: firstString(fields.organizationId, payload.organizationId),
    organizationName: firstString(fields.organizationName, payload.organizationName),
    venue,
    address,
    city,
    normalizedPlace,
    federalState: firstString(fields.federalState, payload.federalState),
    regionScope: firstString(fields.regionScope, payload.regionScope),
    publishedAt: firstString(fields.publishedAt, payload.publishedAt),
    scheduledAt: firstString(fields.scheduledAt, payload.scheduledAt),
    updatedAt: firstString(fields.updatedAt, payload.updatedAt),
  });
}

function buildEventCompositeKeys({
  kind,
  normalizedTitles,
  normalizedOrganizerName,
  normalizedPlace,
  occurrenceStartDates,
}) {
  if (kind !== "event" || occurrenceStartDates.length === 0 ||
      (!normalizedOrganizerName && !normalizedPlace)) return [];
  const occurrenceSignature = occurrenceStartDates.join("|");
  return normalizedTitles.map((title) => JSON.stringify([
    "event",
    title,
    occurrenceSignature,
    normalizedOrganizerName ?? "",
    normalizedPlace ?? "",
  ]));
}

function buildActionCompositeKeys({kind, canonicalActionURLs, normalizedTitles, occurrenceStartDates}) {
  if (kind !== "event" || normalizedTitles.length === 0 || occurrenceStartDates.length === 0) return [];
  const occurrenceSignature = occurrenceStartDates.join("|");
  return canonicalActionURLs.flatMap((url) => normalizedTitles.flatMap((title) => (
    [JSON.stringify(["eventAction", url, title, occurrenceSignature])]
  )));
}

export function canonicalizeURL(value) {
  const input = firstString(value);
  if (!input) return undefined;
  try {
    const url = new URL(input);
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) {
      if (key.toLowerCase().startsWith("utm_") || trackingQueryParameters.has(key.toLowerCase())) {
        url.searchParams.delete(key);
      }
    }
    url.searchParams.sort();
    if (url.pathname.length > 1) url.pathname = url.pathname.replace(/\/+$/, "");
    return url.toString();
  } catch {
    return input;
  }
}

export function normalizeDedupeText(value) {
  const input = firstString(value);
  if (!input) return undefined;
  return input
    .normalize("NFKC")
    .toLocaleLowerCase("de-AT")
    .replace(/[\p{P}\p{S}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim() || undefined;
}

function summarizedOccurrences(fields, payload, startDate, endDate) {
  const stored = array(fields.occurrences, payload.occurrences);
  const raw = stored.length > 0
    ? stored
    : [
      ...(startDate ? [{startDate, endDate}] : []),
      ...array(fields.additionalOccurrences, payload.additionalOccurrences),
    ];
  const seen = new Set();
  return raw.flatMap((value) => {
    const occurrence = record(value);
    const occurrenceStart = firstString(occurrence.startDate);
    if (!occurrenceStart) return [];
    const occurrenceEnd = firstString(occurrence.endDate);
    const key = `${occurrenceStart}\u0000${occurrenceEnd ?? ""}`;
    if (seen.has(key)) return [];
    seen.add(key);
    return [compactObject({
      startDate: occurrenceStart,
      endDate: occurrenceEnd,
      isAllDay: typeof occurrence.isAllDay === "boolean" ? occurrence.isAllDay : undefined,
      status: firstString(occurrence.status),
    })];
  });
}

function localizedTitles(value) {
  return Object.values(record(value)).map((localization) => record(localization).title);
}

function array(...values) {
  return values.find(Array.isArray) ?? [];
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => {
    if (item === undefined || item === null || item === "") return false;
    return !Array.isArray(item) || item.length > 0;
  }));
}

function firstString(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return undefined;
}

function record(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function uniqueStrings(values) {
  return [...new Set(values.filter((value) => typeof value === "string" && value.trim()).map((value) => value.trim()))];
}
