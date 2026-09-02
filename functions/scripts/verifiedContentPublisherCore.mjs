import {createHash} from "node:crypto";

import {
  buildContentPlanningSummary,
  canonicalizeURL,
  normalizeDedupeText,
} from "./contentPlanningBridgeSummary.mjs";

export const EXPECTED_OWNER_ID = "4jk3piOYIWMNsBf5gUAaOMpaQc83";

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
const newsCategories = new Set([
  "news", "event", "lawAndDocuments", "benefitsAndSupport",
  "financeTaxesAndConsumerRights", "health", "safetyAndEmergencies",
  "work", "education", "housing", "transport",
  "communityAndIntegration", "culture", "other",
]);
const eventCategories = new Set([
  "meetups", "training", "culture", "education", "childrenAndFamily",
  "sportsAndWellness", "excursionsAndNature", "music", "nightlifeAndParties",
  "foodAndMarket", "festivalsAndFairs", "businessAndNetworking",
  "volunteering", "supportAndIntegration", "celebration", "saleAndPromotion", "other",
]);
const eventAudiences = new Set(["everyone", "families", "children", "teens", "adults", "seniors"]);
const participationModes = new Set(["none", "inAppRegistration", "externalRegistration", "externalTickets"]);
const verificationRoles = new Set([
  "officialPrimary", "organizer", "venue", "municipalCalendar", "ticketing", "independent",
]);
const semanticallyMutableFields = new Set([
  "createdAt", "updatedAt", "imageURL", "organizationName", "organizationImageURL",
  "likeCount", "likeState", "viewCount", "commentCount", "registeredCount", "registrationState",
]);

export function deterministicContentId(kind, organizationId, canonicalURL) {
  const normalizedCanonicalURL = canonicalizeURL(
    requiredString(canonicalURL, "canonicalURL", 2048)
  );
  if (!normalizedCanonicalURL) throw new Error("canonicalURL is required.");
  return createHash("sha1")
    .update(`${kind}:${organizationId}:${normalizedCanonicalURL}`)
    .digest("hex");
}

export function validateFederalState(value) {
  if (!federalStates.has(value)) {
    throw new Error(`Unsupported federal state: ${String(value)}.`);
  }
  return value;
}

export function normalizePublicationTarget(value) {
  if (value === "austria" || value === "country") {
    return {regionScope: "austria", federalState: undefined};
  }
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const regionScope = value.regionScope === "country" ? "austria" : value.regionScope;
    if (regionScope === "austria" && value.federalState == null) {
      return {regionScope: "austria", federalState: undefined};
    }
    if (regionScope === "federalState") {
      return {regionScope, federalState: validateFederalState(value.federalState)};
    }
    throw new Error("Publication target is invalid.");
  }
  return {regionScope: "federalState", federalState: validateFederalState(value)};
}

export function validateOrganization(organization, organizationId, targetValue) {
  const target = normalizePublicationTarget(targetValue);
  if (!organization || typeof organization !== "object" || Array.isArray(organization)) {
    throw new Error(`Organization ${organizationId} does not exist.`);
  }
  if (organization.id !== organizationId) {
    throw new Error(`Organization ${organizationId} has a mismatched document id field.`);
  }
  if (organization.moderationStatus !== "approved") {
    throw new Error(`Organization ${organizationId} is not approved.`);
  }
  if (organization.ownerId !== EXPECTED_OWNER_ID) {
    throw new Error(`Organization ${organizationId} is not owned by the expected UAC owner.`);
  }
  if (organization.regionScope !== target.regionScope) {
    throw new Error(`Organization ${organizationId} must use regionScope=${target.regionScope}.`);
  }
  if (target.regionScope === "federalState" && organization.federalState !== target.federalState) {
    throw new Error(`Organization ${organizationId} does not belong to ${target.federalState}.`);
  }
  if (target.regionScope === "austria" && organization.federalState != null) {
    throw new Error(`Nationwide organization ${organizationId} must not have federalState.`);
  }
  requiredString(organization.name, "organization.name", 180);
  httpsURL(organization.logoURL, "organization.logoURL");
  return organization;
}

export function normalizeAndValidateManifestItem(rawItem, targetValue) {
  const target = normalizePublicationTarget(targetValue);
  if (!rawItem || typeof rawItem !== "object" || Array.isArray(rawItem)) {
    throw new Error("Every manifest item must be an object.");
  }
  const rawPayload = recordValue(rawItem.payload);
  const providedStates = [rawItem.state, rawPayload.state].filter((value) => value !== undefined);
  if (providedStates.length === 0 || providedStates.some((state) => state !== "approved")) {
    throw new Error(`Every provided manifest state must be explicitly approved for live publication (states=${providedStates.map(String).join(",") || "missing"}).`);
  }
  const providedMissingFields = [rawItem.missingFields, rawPayload.missingFields]
    .filter((value) => value !== undefined);
  if (providedMissingFields.length === 0 || providedMissingFields.some((value) => !Array.isArray(value))) {
    throw new Error("missingFields must be an explicit empty array for live publication.");
  }
  if (providedMissingFields.some((value) => value.length > 0)) {
    throw new Error("Manifest item still has missingFields and cannot be published live.");
  }

  const item = flattenManifestItem(rawItem);
  const kind = enumValue(item.kind, "kind", new Set(["news", "event"]));
  const sources = validateSources(item.sources, kind);
  const primarySource = sources.find((source) => source.isPrimary);
  if (item.canonicalURL != null) {
    const providedCanonicalURL = canonicalizeURL(webURL(item.canonicalURL, "canonicalURL"));
    if (!sources.some((source) => canonicalizeURL(source.url) === providedCanonicalURL)) {
      throw new Error("Provided canonicalURL must be one of the verified source URLs.");
    }
  }
  const canonicalURL = canonicalizeURL(primarySource.url);
  if (!canonicalURL) throw new Error("Primary source URL cannot be canonicalized.");
  const categorySet = kind === "news" ? newsCategories : eventCategories;
  const category = enumValue(item.category, "category", categorySet);
  const additionalCategories = distinctStringArray(
    item.additionalCategories ?? [],
    "additionalCategories",
    categorySet,
    2
  );
  if (additionalCategories.includes(category)) {
    throw new Error("Primary and additional categories must be distinct.");
  }
  const tags = distinctStringArray(item.tags ?? [], "tags", undefined, 12);
  const imagePath = requiredString(item.imagePath, "imagePath", 4096);
  const imageAlternativeText = requiredString(item.imageAlternativeText ?? item.title, "imageAlternativeText", 500);

  const shared = {
    kind,
    canonicalURL,
    imagePath,
    imageAlternativeText,
    imageCredit: optionalString(item.imageCredit, "imageCredit", 240) ?? "Зображення створене ШІ",
    category,
    additionalCategories,
    tags,
    sources,
  };

  return kind === "news"
    ? normalizeNews(item, shared, target)
    : normalizeEvent(item, shared, target);
}

export function buildEventOccurrences(rawOccurrences, contentId) {
  if (!Array.isArray(rawOccurrences) || rawOccurrences.length === 0) {
    throw new Error("Event requires at least one occurrence.");
  }
  const occurrences = rawOccurrences.map((raw, index) => {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
      throw new Error(`occurrences[${index}] must be an object.`);
    }
    const startDate = timestamp(raw.startDate, `occurrences[${index}].startDate`);
    const hasExplicitEndDate = raw.hasExplicitEndDate ?? raw.endDate != null;
    if (typeof hasExplicitEndDate !== "boolean") {
      throw new Error(`occurrences[${index}].hasExplicitEndDate must be a boolean.`);
    }
    const endDate = hasExplicitEndDate
      ? timestamp(raw.endDate, `occurrences[${index}].endDate`)
      : startDate;
    if (endDate.getTime() < startDate.getTime()) {
      throw new Error(`occurrences[${index}].endDate cannot be earlier than startDate.`);
    }
    return {
      id: `${contentId}-occurrence-${index + 1}`,
      startDate,
      endDate,
      hasExplicitEndDate,
      isAllDay: booleanValue(raw.isAllDay ?? false, `occurrences[${index}].isAllDay`),
      status: enumValue(raw.status ?? "scheduled", `occurrences[${index}].status`, new Set(["scheduled", "cancelled"])),
    };
  });
  occurrences.sort((left, right) => left.startDate.getTime() - right.startDate.getTime());
  return occurrences.map((occurrence, index) => ({
    ...occurrence,
    id: `${contentId}-occurrence-${index + 1}`,
  }));
}

export function buildContentDocument(item, organization, organizationId, imageURL, now = new Date()) {
  const id = deterministicContentId(item.kind, organizationId, item.canonicalURL);
  const common = {
    id,
    schemaVersion: 2,
    title: item.title,
    regionScope: item.regionScope,
    federalState: item.federalState,
    category: item.category,
    additionalCategories: item.additionalCategories,
    tags: item.tags,
    sourceType: "organization",
    organizationId,
    organizationName: organization.name,
    organizationImageURL: organization.logoURL,
    imageURL,
    authorId: EXPECTED_OWNER_ID,
    authorName: organization.name,
    createdAt: new Date(now),
    updatedAt: new Date(now),
    moderationStatus: "approved",
    likeCount: 0,
    likeState: "notLiked",
    viewCount: 0,
    commentCount: 0,
  };

  if (item.kind === "news") {
    return compactObject({
      ...common,
      subtitle: item.subtitle,
      summary: item.subtitle,
      body: item.body,
      city: item.city,
      sourceName: item.sourceName,
      sourceURL: item.canonicalURL,
      publishedAt: item.publishedAt,
      localizations: {
        uk: {title: item.title, subtitle: item.subtitle, body: item.body},
        de: {title: item.deTitle, subtitle: item.deSubtitle, body: item.deBody},
      },
      mediaMetadata: {
        alternativeText: item.imageAlternativeText,
        credit: item.imageCredit,
      },
      externalAction: item.externalAction,
    });
  }

  const normalizedOccurrences = buildEventOccurrences(item.occurrences, id);
  const occurrences = normalizedOccurrences.map(({hasExplicitEndDate: _omitted, ...occurrence}) => occurrence);
  const startDate = occurrences[0].startDate;
  const endDate = new Date(Math.max(...occurrences.map((occurrence) => occurrence.endDate.getTime())));
  return compactObject({
    ...common,
    summary: item.summary,
    details: item.details,
    localizations: {
      uk: {title: item.title, summary: item.summary, details: item.details},
      de: {title: item.deTitle, summary: item.deSummary, details: item.deDetails},
    },
    city: item.city,
    venue: item.venue,
    address: item.address,
    locationNote: item.locationNote,
    latitude: item.latitude,
    longitude: item.longitude,
    organizerName: item.organizerName,
    organizerURL: item.organizerURL,
    contactPhone: item.contactPhone,
    contactEmail: item.contactEmail,
    contactURL: item.contactURL,
    startDate,
    endDate,
    occurrences,
    requiresRegistration: item.requiresRegistration,
    participationMode: item.participationMode,
    externalAction: item.externalAction,
    price: item.price,
    pricing: item.pricing,
    capacity: item.capacity,
    registeredCount: 0,
    registrationState: "notRegistered",
    audience: item.audience,
    minimumAge: item.minimumAge,
    maximumAge: item.maximumAge,
    visibility: "public",
    isAllDay: occurrences.every((occurrence) => occurrence.isAllDay),
  });
}

export function documentsSemanticallyMatch(existing, expected) {
  return stableStringify(semanticProjection(existing)) === stableStringify(semanticProjection(expected));
}

export function buildManifestDuplicateSummary(item) {
  const occurrences = item.kind === "event"
    ? buildEventOccurrences(item.occurrences, "duplicate-preflight")
      .map((occurrence) => ({
        startDate: occurrence.startDate.toISOString(),
        endDate: occurrence.endDate.toISOString(),
        isAllDay: occurrence.isAllDay,
        status: occurrence.status,
      }))
    : undefined;
  const summary = buildContentPlanningSummary({
    id: "manifest",
    defaultKind: item.kind,
    fields: compactObject({
      kind: item.kind,
      title: item.title,
      sourceURL: item.canonicalURL,
      localizations: {
        uk: {title: item.title},
        de: {title: item.deTitle},
      },
      occurrences,
      organizerName: item.organizerName,
      venue: item.venue,
      address: item.address,
      city: item.city,
      federalState: item.federalState,
      regionScope: item.regionScope,
    }),
  });
  return {...summary, primaryCanonicalURL: canonicalizeURL(item.canonicalURL)};
}

export function contentIdentityLockClaims(item) {
  const summary = buildManifestDuplicateSummary(item);
  const claims = [];
  if (item.kind === "news") {
    claims.push(identityLockClaim("newsPrimaryURL", summary.primaryCanonicalURL));
    claims.push(identityLockClaim("newsSemanticContent", JSON.stringify([
      normalizeDedupeText(item.title),
      normalizeDedupeText(item.body),
      item.publishedAt.toISOString().slice(0, 10),
      item.category,
      item.regionScope,
      item.federalState ?? null,
    ])));
  } else {
    const occurrenceSignature = summary.occurrenceStartDates.join("|");
    claims.push(identityLockClaim(
      "eventPrimaryURLAndOccurrences",
      JSON.stringify([summary.primaryCanonicalURL, occurrenceSignature])
    ));
    for (const eventCompositeKey of summary.eventCompositeKeys ?? []) {
      claims.push(identityLockClaim("eventComposite", eventCompositeKey));
    }
    for (const normalizedTitle of summary.normalizedTitles ?? []) {
      claims.push(identityLockClaim(
        "eventPrimaryURLAndTitle",
        JSON.stringify([summary.primaryCanonicalURL, normalizedTitle])
      ));
    }
  }
  return [...new Map(claims.map((claim) => [claim.id, claim])).values()];
}

function identityLockClaim(type, value) {
  const key = JSON.stringify(["uacContentIdentity", 1, type, value]);
  return {
    id: createHash("sha256").update(key).digest("hex"),
    type,
    key,
  };
}

export function classifyLegacyDuplicate({item, expectedDocument, existingRecords}) {
  if (!Array.isArray(existingRecords)) throw new Error("existingRecords must be an array.");
  const manifestSummary = buildManifestDuplicateSummary(item);
  const candidates = existingRecords.flatMap((record) => {
    if (!record || typeof record !== "object" || record.summary?.kind !== item.kind) return [];
    if (isExplicitlyHiddenLiveRecord(record)) return [];
    const samePrimarySource = Boolean(
      manifestSummary.primaryCanonicalURL
      && manifestSummary.primaryCanonicalURL === record.summary.primaryCanonicalURL
    );
    const sameOccurrenceStarts = item.kind === "event" && arraysEqual(
      manifestSummary.occurrenceStartDates,
      record.summary.occurrenceStartDates
    );
    const sameNormalizedTitle = valuesOverlap(
      manifestSummary.normalizedTitles,
      record.summary.normalizedTitles
    );
    const canonicalMatch = item.kind === "news"
      ? samePrimarySource
      : samePrimarySource && sameOccurrenceStarts;
    const eventCompositeMatch = item.kind === "event" && valuesOverlap(
      manifestSummary.eventCompositeKeys,
      record.summary.eventCompositeKeys
    );
    const possibleReschedule = item.kind === "event"
      && samePrimarySource
      && !sameOccurrenceStarts
      && sameNormalizedTitle;
    if (!canonicalMatch && !eventCompositeMatch && !possibleReschedule) return [];
    const exact = record.collection === "drafts"
      ? draftDocumentsSemanticallyMatch(
        item.kind,
        manifestSummary,
        record,
        expectedDocument
      )
      : legacyDocumentsSemanticallyMatch(item.kind, record.fields, expectedDocument);
    return [{
      ...record,
      canonicalMatch,
      eventCompositeMatch,
      possibleReschedule,
      exact,
    }];
  });
  if (candidates.length === 0) return {status: "new"};

  const liveCandidates = candidates.filter((candidate) => (
    candidate.collection === "news" || candidate.collection === "events"
  ));
  const prioritizedCandidates = liveCandidates.length > 0 ? liveCandidates : candidates;
  const exactCandidates = prioritizedCandidates.filter((candidate) => candidate.exact);
  if (exactCandidates.length === 0) return duplicateConflict(prioritizedCandidates);

  const exact = [...exactCandidates].sort((left, right) => left.id.localeCompare(right.id))[0];
  return {
    status: "skippedExisting",
    existingId: exact.id,
    existingCollection: exact.collection,
    matchedBy: duplicateMatchReason(exact),
  };
}

function isExplicitlyHiddenLiveRecord(record) {
  if (record.collection !== "news" && record.collection !== "events") return false;
  const fields = recordValue(record.fields);
  if (fields.moderationStatus != null && fields.moderationStatus !== "approved") return true;
  if (fields.archived === true || fields.isArchived === true) return true;
  return ["hidden", "private", "archived"].includes(fields.visibility);
}

function duplicateConflict(candidates) {
  return {
    status: "needsAttention",
    existingIds: candidates.map((candidate) => candidate.id),
    conflicts: candidates.map(duplicateCandidateSummary),
  };
}

export function legacyDocumentsSemanticallyMatch(kind, existing, expected) {
  return stableStringify(legacyPublicationProjection(kind, existing))
    === stableStringify(legacyPublicationProjection(kind, expected));
}

function duplicateCandidateSummary(candidate) {
  return {
    existingId: candidate.id,
    existingCollection: candidate.collection,
    matchedBy: duplicateMatchReason(candidate),
  };
}

function duplicateMatchReason(candidate) {
  if (candidate.eventCompositeMatch) return "eventComposite";
  if (candidate.possibleReschedule) return "possibleReschedule";
  return candidate.summary.kind === "event" ? "primaryURLAndOccurrences" : "canonicalPrimaryURL";
}

function draftDocumentsSemanticallyMatch(kind, manifest, existingRecord, expectedDocument) {
  const existingFields = recordValue(existingRecord.fields);
  if (existingRecord.summary.state === "needsAttention") return false;
  if (existingFields.missingFields !== undefined
    && (!Array.isArray(existingFields.missingFields) || existingFields.missingFields.length > 0)) {
    return false;
  }
  const existing = existingRecord.summary;
  const manifestTitles = (manifest.titles ?? []).map(normalizeDedupeText).filter(Boolean);
  const existingTitles = (existing.titles ?? []).map(normalizeDedupeText).filter(Boolean);
  if (!valuesOverlap(manifestTitles, existingTitles)) return false;
  if (kind === "news") {
    if (!(
      manifest.primaryCanonicalURL
      && manifest.primaryCanonicalURL === existing.primaryCanonicalURL
    )) return false;
  } else if (!valuesOverlap(manifest.eventCompositeKeys, existing.eventCompositeKeys)) {
    return false;
  }
  const draftProjection = draftPublicationProjection(kind, existingFields);
  const expectedProjection = draftPublicationProjection(kind, expectedDocument);
  return stableStringify(draftProjection) === stableStringify(expectedProjection);
}

function draftPublicationProjection(kind, document) {
  const projection = legacyPublicationProjection(kind, document);
  if (kind === "news") {
    const {
      publishedAt: _publishedAt,
      sourceName: _sourceName,
      city: _city,
      ...draftProjection
    } = projection;
    return draftProjection;
  }
  const {regionScope: _regionScope, ...draftProjection} = projection;
  const value = {...recordValue(document.payload), ...recordValue(document)};
  return {
    ...draftProjection,
    // Planning drafts derive this flag from the mode and need not store the
    // live-only compatibility field explicitly.
    requiresRegistration: value.participationMode === "inAppRegistration",
  };
}

function valuesOverlap(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length === 0 || right.length === 0) {
    return false;
  }
  const rightValues = new Set(right);
  return left.some((value) => rightValues.has(value));
}

function arraysEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right) || left.length !== right.length || left.length === 0) {
    return false;
  }
  return left.every((value, index) => value === right[index]);
}

function legacyPublicationProjection(kind, document) {
  const outer = recordValue(document);
  const value = {...recordValue(outer.payload), ...outer};
  const localizations = recordValue(value.localizations);
  const uk = recordValue(localizations.uk);
  const de = recordValue(localizations.de);
  const common = {
    title: semanticAliasedText(value.title, uk.title),
    deTitle: semanticAliasedText(value.deTitle, value.germanTitle, de.title),
    regionScope: semanticText(value.regionScope),
    federalState: semanticText(value.federalState),
    category: semanticText(value.category),
    additionalCategories: semanticStringArray(value.additionalCategories),
    tags: semanticStringArray(value.tags),
  };
  if (kind === "news") {
    return compactObject({
      ...common,
      subtitle: semanticAliasedText(value.subtitle, value.summary, uk.subtitle),
      body: semanticAliasedText(value.body, uk.body),
      deSubtitle: semanticAliasedText(
        value.deSubtitle,
        value.deSummary,
        value.germanSubtitle,
        value.germanSummary,
        de.subtitle
      ),
      deBody: semanticAliasedText(value.deBody, value.germanBody, de.body),
      publishedAt: semanticTimestamp(value.publishedAt),
      city: semanticText(value.city),
      sourceName: semanticText(value.sourceName),
      externalAction: semanticExternalAction(value),
    });
  }
  if (kind !== "event") throw new Error(`Unsupported duplicate kind: ${String(kind)}.`);
  return compactObject({
    ...common,
    summary: semanticAliasedText(value.summary, uk.summary),
    details: semanticAliasedText(value.details, uk.details),
    deSummary: semanticAliasedText(value.deSummary, value.germanSummary, de.summary),
    deDetails: semanticAliasedText(value.deDetails, value.germanDetails, de.details),
    city: semanticText(value.city),
    venue: semanticText(value.venue),
    address: semanticText(value.address),
    locationNote: semanticText(value.locationNote),
    latitude: value.latitude,
    longitude: value.longitude,
    organizerName: semanticText(firstDefined(value.organizerName, value.eventOrganizerName)),
    organizerURL: semanticURL(value.organizerURL),
    contactPhone: semanticText(value.contactPhone),
    contactEmail: semanticText(value.contactEmail),
    contactURL: semanticURL(value.contactURL),
    occurrences: semanticOccurrences(value),
    participationMode: semanticText(value.participationMode),
    requiresRegistration: semanticRequiresRegistration(value),
    externalAction: semanticExternalAction(value),
    pricing: semanticPricing(value.pricing ?? legacyDraftPricing(value)),
    capacity: value.capacity,
    audience: semanticText(value.audience),
    minimumAge: value.minimumAge,
    maximumAge: value.maximumAge,
  });
}

function semanticOccurrences(value) {
  const occurrences = Array.isArray(value.occurrences)
    ? value.occurrences
    : [
      ...(value.startDate ? [{
        startDate: value.startDate,
        endDate: value.endDate,
        isAllDay: value.isAllDay,
      }] : []),
      ...(Array.isArray(value.additionalOccurrences) ? value.additionalOccurrences : []),
    ];
  return occurrences.map((rawOccurrence) => {
    const occurrence = recordValue(rawOccurrence);
    const startDate = semanticTimestamp(occurrence.startDate);
    return compactObject({
      startDate,
      endDate: semanticTimestamp(firstDefined(occurrence.endDate, occurrence.startDate)),
      isAllDay: firstDefined(occurrence.isAllDay, false),
      status: semanticText(firstDefined(occurrence.status, "scheduled")),
    });
  }).sort((left, right) => String(left.startDate).localeCompare(String(right.startDate)));
}

function semanticPricing(rawPricing) {
  const pricing = recordValue(rawPricing);
  if (Object.keys(pricing).length === 0) return undefined;
  const aliases = {fixed: "exact", from: "startingFrom", mixed: "unspecified"};
  const kind = aliases[pricing.kind] ?? pricing.kind;
  const amount = kind === "free" ? 0 : kind === "unspecified" ? undefined : pricing.amount;
  const maximumAmount = ["free", "unspecified"].includes(kind)
    ? undefined
    : pricing.maximumAmount;
  return compactObject({
    kind: semanticText(kind),
    amount,
    maximumAmount,
    currencyCode: semanticText(pricing.currencyCode ?? "EUR"),
    note: semanticText(pricing.note),
  });
}

function legacyDraftPricing(value) {
  if (value.priceKind == null) return undefined;
  return {
    kind: value.priceKind,
    amount: firstDefined(value.price, value.priceAmount),
    maximumAmount: firstDefined(value.maximumPrice, value.maximumPriceAmount),
    currencyCode: value.currencyCode ?? "EUR",
    note: value.priceNote,
  };
}

function semanticRequiresRegistration(value) {
  if (value.participationMode !== "inAppRegistration") return false;
  return value.requiresRegistration === true;
}

function semanticExternalAction(value) {
  const externalAction = recordValue(value.externalAction);
  const title = firstDefined(value.externalActionTitle, externalAction.title);
  const url = firstDefined(value.externalActionURL, externalAction.url);
  if (title == null && url == null) return undefined;
  return compactObject({title: semanticText(title), url: semanticURL(url)});
}

function semanticURL(value) {
  if (typeof value !== "string" || !value.trim()) return undefined;
  return canonicalizeURL(value) ?? value.trim();
}

function semanticTimestamp(value) {
  if (value instanceof Date) return value.toISOString();
  if (typeof value !== "string" || !value.trim()) return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value.trim() : date.toISOString();
}

function semanticText(value) {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function semanticAliasedText(...values) {
  const normalized = [...new Set(values.map(semanticText).filter(Boolean))].sort();
  if (normalized.length === 0) return undefined;
  if (normalized.length === 1) return normalized[0];
  return {conflictingAliases: normalized};
}

function semanticStringArray(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(semanticText).filter(Boolean))].sort();
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null);
}

function recordValue(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function flattenManifestItem(rawItem) {
  const payload = rawItem.payload && typeof rawItem.payload === "object" && !Array.isArray(rawItem.payload)
    ? rawItem.payload
    : rawItem;
  const firstOccurrence = payload.startDate ? [{
    startDate: payload.startDate,
    endDate: payload.endDate,
    hasExplicitEndDate: payload.hasExplicitEndDate,
    isAllDay: payload.isAllDay,
  }] : [];
  const occurrences = payload.occurrences
    ?? (firstOccurrence.length > 0 ? firstOccurrence.concat(payload.additionalOccurrences ?? []) : undefined);
  const pricing = payload.pricing ?? (payload.priceKind ? {
    kind: payload.priceKind,
    amount: payload.price ?? payload.priceAmount,
    maximumAmount: payload.maximumPrice ?? payload.maximumPriceAmount,
    currencyCode: payload.currencyCode,
    note: payload.priceNote,
  } : undefined);
  return {
    ...payload,
    kind: rawItem.kind ?? payload.kind,
    canonicalURL: rawItem.canonicalURL ?? payload.canonicalURL,
    imagePath: rawItem.imagePath ?? payload.imagePath,
    imageAlternativeText: rawItem.imageAlternativeText ?? payload.imageAlternativeText,
    imageCredit: rawItem.imageCredit ?? payload.imageCredit,
    sources: rawItem.sources ?? payload.sources,
    deTitle: payload.deTitle ?? payload.germanTitle,
    deSubtitle: payload.deSubtitle ?? payload.deSummary ?? payload.germanSubtitle ?? payload.germanSummary,
    deBody: payload.deBody ?? payload.germanBody,
    deSummary: payload.deSummary ?? payload.germanSummary,
    deDetails: payload.deDetails ?? payload.germanDetails,
    organizerName: payload.organizerName ?? payload.eventOrganizerName,
    occurrences,
    pricing,
  };
}

function normalizeNews(item, shared, target) {
  validateManifestTarget(item, target);
  const title = requiredString(item.title, "title", 180);
  const subtitle = requiredString(item.subtitle ?? item.summary, "subtitle", 500);
  const body = requiredString(item.body, "body", 50_000);
  const deTitle = requiredString(item.deTitle, "deTitle", 180);
  const deSubtitle = requiredString(item.deSubtitle, "deSubtitle", 500);
  const deBody = requiredString(item.deBody, "deBody", 50_000);
  return compactObject({
    ...shared,
    regionScope: target.regionScope,
    federalState: target.federalState,
    title,
    subtitle,
    body,
    deTitle,
    deSubtitle,
    deBody,
    publishedAt: timestamp(item.publishedAt, "publishedAt"),
    city: optionalString(item.city, "city", 160),
    sourceName: optionalString(item.sourceName, "sourceName", 240)
      ?? shared.sources.find((source) => source.isPrimary).title,
    externalAction: normalizeExternalAction(item, shared.canonicalURL),
  });
}

function normalizeEvent(item, shared, target) {
  validateManifestTarget(item, target);
  const participationMode = enumValue(item.participationMode ?? "none", "participationMode", participationModes);
  if (item.requiresRegistration != null) booleanValue(item.requiresRegistration, "requiresRegistration");
  const requiresRegistration = participationMode === "inAppRegistration";
  const externalAction = normalizeExternalAction(item, item.contactURL ?? shared.canonicalURL);
  if (["externalRegistration", "externalTickets"].includes(participationMode) && !externalAction?.url) {
    throw new Error(`${participationMode} requires externalActionURL.`);
  }
  const minimumAge = optionalInteger(item.minimumAge, "minimumAge", 0, 120);
  const maximumAge = optionalInteger(item.maximumAge, "maximumAge", 0, 120);
  if (minimumAge != null && maximumAge != null && minimumAge > maximumAge) {
    throw new Error("minimumAge cannot be greater than maximumAge.");
  }
  const pricing = normalizePricing(item.pricing);
  return compactObject({
    ...shared,
    regionScope: target.regionScope,
    federalState: target.federalState,
    title: requiredString(item.title, "title", 180),
    summary: requiredString(item.summary, "summary", 500),
    details: requiredString(item.details, "details", 50_000),
    deTitle: requiredString(item.deTitle, "deTitle", 180),
    deSummary: requiredString(item.deSummary, "deSummary", 500),
    deDetails: requiredString(item.deDetails, "deDetails", 50_000),
    city: requiredString(item.city, "city", 160),
    venue: requiredString(item.venue, "venue", 240),
    address: optionalString(item.address, "address", 500),
    locationNote: optionalString(item.locationNote, "locationNote", 500),
    latitude: optionalNumber(item.latitude, "latitude", -90, 90),
    longitude: optionalNumber(item.longitude, "longitude", -180, 180),
    organizerName: optionalString(item.organizerName, "organizerName", 240),
    organizerURL: optionalWebOrEmailURL(item.organizerURL, "organizerURL"),
    contactPhone: optionalString(item.contactPhone, "contactPhone", 80),
    contactEmail: optionalEmail(item.contactEmail, "contactEmail"),
    contactURL: optionalWebOrEmailURL(item.contactURL, "contactURL") ?? shared.canonicalURL,
    occurrences: item.occurrences,
    participationMode,
    requiresRegistration,
    externalAction,
    pricing,
    price: pricing.amount ?? 0,
    capacity: optionalInteger(item.capacity, "capacity", 1, 1_000_000),
    audience: enumValue(item.audience ?? "everyone", "audience", eventAudiences),
    minimumAge,
    maximumAge,
  });
}

function validateManifestTarget(item, target) {
  const manifestScope = item.regionScope === "country" ? "austria" : item.regionScope;
  if (manifestScope != null && manifestScope !== target.regionScope) {
    throw new Error(`Manifest regionScope=${item.regionScope} does not match ${target.regionScope}.`);
  }
  if (target.regionScope === "federalState" && item.federalState != null && item.federalState !== target.federalState) {
    throw new Error(`Manifest federalState=${item.federalState} does not match ${target.federalState}.`);
  }
  if (target.regionScope === "austria" && item.federalState != null) {
    throw new Error("Nationwide manifest must not contain federalState.");
  }
}

function normalizePricing(rawPricing) {
  const pricing = rawPricing ?? {kind: "unspecified"};
  if (!pricing || typeof pricing !== "object" || Array.isArray(pricing)) {
    throw new Error("pricing must be an object.");
  }
  const aliases = {fixed: "exact", from: "startingFrom", mixed: "unspecified"};
  const kind = aliases[pricing.kind] ?? pricing.kind ?? "unspecified";
  enumValue(kind, "pricing.kind", new Set(["unspecified", "free", "exact", "startingFrom", "range"]));
  let amount = optionalNumber(pricing.amount, "pricing.amount", 0, 100_000_000);
  let maximumAmount = optionalNumber(pricing.maximumAmount, "pricing.maximumAmount", 0, 100_000_000);
  if (["exact", "startingFrom", "range"].includes(kind) && amount == null) {
    throw new Error(`pricing.amount is required for ${kind}.`);
  }
  if (kind === "range" && maximumAmount == null) {
    throw new Error("pricing.maximumAmount is required for range.");
  }
  if (amount != null && maximumAmount != null && maximumAmount < amount) {
    throw new Error("pricing.maximumAmount cannot be smaller than pricing.amount.");
  }
  if (kind === "free") {
    amount = 0;
    maximumAmount = undefined;
  }
  if (kind === "unspecified") {
    amount = undefined;
    maximumAmount = undefined;
  }
  const currencyCode = requiredString(pricing.currencyCode ?? "EUR", "pricing.currencyCode", 3).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currencyCode)) throw new Error("pricing.currencyCode must be a three-letter code.");
  return compactObject({
    kind,
    amount,
    maximumAmount,
    currencyCode,
    note: optionalString(pricing.note, "pricing.note", 500),
  });
}

function normalizeExternalAction(item, fallbackURL) {
  const rawURL = item.externalActionURL ?? item.externalAction?.url ?? fallbackURL;
  if (!rawURL) return undefined;
  return compactObject({
    title: optionalString(item.externalActionTitle ?? item.externalAction?.title, "externalActionTitle", 160),
    url: httpsURL(rawURL, "externalActionURL"),
  });
}

function validateSources(rawSources, kind) {
  if (!Array.isArray(rawSources) || rawSources.length < 2) {
    throw new Error("Live publication requires at least two verified sources.");
  }
  const sources = rawSources.map((source, index) => {
    if (!source || typeof source !== "object" || Array.isArray(source)) {
      throw new Error(`sources[${index}] must be an object.`);
    }
    return {
      url: webURL(source.url, `sources[${index}].url`),
      title: requiredString(source.title, `sources[${index}].title`, 300),
      isPrimary: booleanValue(source.isPrimary ?? false, `sources[${index}].isPrimary`),
      verificationRole: enumValue(
        source.verificationRole,
        `sources[${index}].verificationRole`,
        verificationRoles
      ),
    };
  });
  if (sources.filter((source) => source.isPrimary).length !== 1) {
    throw new Error("sources must contain exactly one primary source.");
  }
  const primary = sources.find((source) => source.isPrimary);
  if (primary.verificationRole !== "officialPrimary") {
    throw new Error("The primary source must use verificationRole=officialPrimary.");
  }
  if (sources.some((source) => !source.isPrimary && source.verificationRole === "officialPrimary")) {
    throw new Error("Only the primary source may use verificationRole=officialPrimary.");
  }
  const uniqueCanonicalURLs = new Set(sources.map((source) => canonicalizeURL(source.url)));
  if (uniqueCanonicalURLs.size < 2) {
    throw new Error("Live publication requires at least two unique canonical source URLs.");
  }
  if (kind === "news") {
    const independent = sources.filter((source) => source.verificationRole === "independent");
    if (independent.length === 0) {
      throw new Error("Verified news requires an independent secondary source.");
    }
    const primaryHost = new URL(primary.url).hostname.toLowerCase();
    if (!independent.some((source) => new URL(source.url).hostname.toLowerCase() !== primaryHost)) {
      throw new Error("The independent news source must be hosted on a different site.");
    }
  }
  return sources;
}

function semanticProjection(document) {
  if (!document || typeof document !== "object" || Array.isArray(document)) return document;
  const result = {};
  for (const [key, value] of Object.entries(document)) {
    if (semanticallyMutableFields.has(key)) continue;
    result[key] = semanticValue(value);
  }
  return result;
}

function semanticValue(value) {
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "string" && isTimestampString(value)) {
    return new Date(value).toISOString();
  }
  if (Array.isArray(value)) return value.map(semanticValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, nested]) => nested !== undefined)
        .map(([key, nested]) => [key, semanticValue(nested)])
    );
  }
  return value;
}

function isTimestampString(value) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return false;
  }
  return !Number.isNaN(new Date(value).getTime());
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}

function requiredString(value, field, maximumLength) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${field} is required.`);
  const result = value.trim();
  if (result.length > maximumLength) throw new Error(`${field} exceeds ${maximumLength} characters.`);
  return result;
}

function optionalString(value, field, maximumLength) {
  if (value == null) return undefined;
  return requiredString(value, field, maximumLength);
}

function enumValue(value, field, allowed) {
  if (typeof value !== "string" || !allowed.has(value)) throw new Error(`${field} is invalid.`);
  return value;
}

function distinctStringArray(value, field, allowed, maximumCount) {
  if (!Array.isArray(value) || value.length > maximumCount) {
    throw new Error(`${field} must contain at most ${maximumCount} values.`);
  }
  const normalized = value.map((candidate, index) => requiredString(candidate, `${field}[${index}]`, 120));
  if (new Set(normalized).size !== normalized.length) throw new Error(`${field} cannot contain duplicates.`);
  if (allowed && normalized.some((candidate) => !allowed.has(candidate))) throw new Error(`${field} contains an invalid value.`);
  return normalized;
}

function booleanValue(value, field) {
  if (typeof value !== "boolean") throw new Error(`${field} must be a boolean.`);
  return value;
}

function timestamp(value, field) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new Error(`${field} must be an ISO 8601 timestamp with a timezone.`);
  }
  const result = new Date(value);
  if (Number.isNaN(result.getTime())) throw new Error(`${field} is invalid.`);
  return result;
}

function httpsURL(value, field) {
  const raw = requiredString(value, field, 2048);
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`${field} must be a valid HTTPS URL.`);
  }
  if (parsed.protocol !== "https:" || !parsed.hostname) throw new Error(`${field} must be a valid HTTPS URL.`);
  return raw;
}

function webURL(value, field) {
  const raw = requiredString(value, field, 2048);
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(`${field} must be a valid HTTP(S) URL.`);
  }
  if (!["http:", "https:"].includes(parsed.protocol) || !parsed.hostname) {
    throw new Error(`${field} must be a valid HTTP(S) URL.`);
  }
  return raw;
}

function optionalWebOrEmailURL(value, field) {
  if (value == null) return undefined;
  const raw = requiredString(value, field, 2048);
  if (raw.startsWith("mailto:")) {
    if (!/^mailto:[^@\s]+@[^@\s]+\.[^@\s]+$/.test(raw)) throw new Error(`${field} contains an invalid email URL.`);
    return raw;
  }
  return httpsURL(raw, field);
}

function optionalEmail(value, field) {
  if (value == null) return undefined;
  const email = requiredString(value, field, 320);
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Error(`${field} is invalid.`);
  return email;
}

function optionalNumber(value, field, minimum, maximum) {
  if (value == null) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${field} must be between ${minimum} and ${maximum}.`);
  }
  return value;
}

function optionalInteger(value, field, minimum, maximum) {
  const number = optionalNumber(value, field, minimum, maximum);
  if (number != null && !Number.isInteger(number)) throw new Error(`${field} must be an integer.`);
  return number;
}
