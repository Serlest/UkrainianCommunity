export function normalizeSourceURL(value) {
  if (typeof value !== "string" || !value.trim()) return undefined;
  try {
    const url = new URL(value.trim());
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) {
      if (key.toLowerCase().startsWith("utm_")) url.searchParams.delete(key);
    }
    url.hostname = url.hostname.toLowerCase();
    url.pathname = url.pathname.replace(/\/+$/, "") || "/";
    return url.toString();
  } catch {
    return undefined;
  }
}

export function contentSourceURLs(kind, data) {
  const candidates = kind === "news"
    ? [data.sourceURL]
    : [data.externalAction?.url];
  return new Set(candidates.map(normalizeSourceURL).filter(Boolean));
}

export function draftSourceURLs(data) {
  const sources = Array.isArray(data.sources) ? data.sources : [];
  return new Set(sources.map((source) => normalizeSourceURL(source?.url)).filter(Boolean));
}

export function classifyPlanningHistoryDraft(draft, liveContent) {
  const kind = draft.data.kind;
  if (kind !== "news" && kind !== "event") {
    return {status: "invalid", reason: "unsupported-kind"};
  }

  const collection = kind === "news" ? "news" : "events";
  const existingContentID = nonEmptyString(draft.data.publishedContentId);
  if (existingContentID) {
    const existing = liveContent.find((item) =>
      item.collection === collection && item.id === existingContentID
    );
    if (!existing) return {status: "invalid", reason: "linked-content-missing"};
    return hasCompleteReceipt(draft.data, existing)
      ? {status: "alreadyLinked", content: existing}
      : {status: "matched", content: existing};
  }

  const sourceURLs = draftSourceURLs(draft.data);
  if (sourceURLs.size === 0) return unresolvedResult(draft.data, "no-source-url");
  const strongMatches = liveContent.filter((item) => {
    if (item.collection !== collection) return false;
    const candidateURLs = contentSourceURLs(kind, item.data);
    return [...sourceURLs].some((url) => candidateURLs.has(url));
  });
  if (strongMatches.length > 1) {
    if (kind === "event") {
      const identityMatches = strongMatches.filter((item) =>
        hasExactEventIdentity(draft.data, item.data)
      );
      if (identityMatches.length === 1) {
        return {status: "matched", content: identityMatches[0]};
      }
      if (identityMatches.length > 1) {
        return {
          status: "ambiguous",
          reason: "multiple-exact-url-identity-matches",
          matches: identityMatches,
        };
      }
    }
    return {status: "ambiguous", reason: "multiple-exact-url-matches", matches: strongMatches};
  }
  if (strongMatches.length === 1) return {status: "matched", content: strongMatches[0]};

  if (kind === "event") {
    const contextualMatches = liveContent.filter((item) => {
      if (item.collection !== collection || !hasExactEventIdentity(draft.data, item.data)) return false;
      const candidateURLs = new Set(
        [item.data.organizerURL, item.data.contactURL]
          .map(normalizeSourceURL)
          .filter(Boolean)
      );
      return [...sourceURLs].some((url) => candidateURLs.has(url));
    });
    if (contextualMatches.length > 1) {
      return {
        status: "ambiguous",
        reason: "multiple-contextual-event-matches",
        matches: contextualMatches,
      };
    }
    if (contextualMatches.length === 1) {
      return {status: "matched", content: contextualMatches[0]};
    }
  }
  return unresolvedResult(draft.data, "no-exact-url-match");
}

export function publicationOutcomeForContent(data) {
  if (data.moderationStatus === "approved") return "approved";
  if (data.moderationStatus === "pendingReview") return "pendingReview";
  if (data.moderationStatus === "draft" && data.scheduledAt) return "scheduled";
  return "unresolved";
}

export function summarizeHistoryClassifications(classifications) {
  const summary = {
    total: classifications.length,
    matched: 0,
    alreadyLinked: 0,
    unresolved: 0,
    alreadyUnresolved: 0,
    ambiguous: 0,
    invalid: 0,
  };
  for (const item of classifications) summary[item.result.status] += 1;
  summary.safeResolved = summary.matched + summary.alreadyLinked;
  summary.totalUnresolved = summary.unresolved + summary.alreadyUnresolved;
  return summary;
}

export function parseContentPlanningHistoryBackfillOptions(argumentsList) {
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

  const expectationKeys = ["expect-matched", "expect-unresolved", "expect-ambiguous"];
  const providedExpectationKeys = expectationKeys.filter((key) => values.has(key));
  if (providedExpectationKeys.length !== 0 &&
      providedExpectationKeys.length !== expectationKeys.length) {
    throw new Error(
      "Provide --expect-matched, --expect-unresolved and --expect-ambiguous together."
    );
  }
  if (apply && providedExpectationKeys.length !== expectationKeys.length) {
    throw new Error(
      "--apply requires explicit expectations from a fresh dry-run: " +
      "--expect-matched, --expect-unresolved and --expect-ambiguous."
    );
  }

  const hasExpectations = providedExpectationKeys.length === expectationKeys.length;
  return {
    projectId,
    apply,
    expectedMatched: hasExpectations
      ? nonNegativeOption(values.get("expect-matched"), "--expect-matched")
      : undefined,
    expectedUnresolved: hasExpectations
      ? nonNegativeOption(values.get("expect-unresolved"), "--expect-unresolved")
      : undefined,
    expectedAmbiguous: hasExpectations
      ? nonNegativeOption(values.get("expect-ambiguous"), "--expect-ambiguous")
      : undefined,
  };
}

function unresolvedResult(data, reason) {
  if (data.schemaVersion === 3 &&
      data.historyBackfillStatus === "unresolved" &&
      data.publicationOutcome === "unresolved" &&
      Boolean(data.historyBackfilledAt)) {
    return {status: "alreadyUnresolved", reason};
  }
  return {status: "unresolved", reason};
}

function hasCompleteReceipt(data, content) {
  return data.schemaVersion === 3 &&
    data.publishedContentKind === (content.collection === "news" ? "news" : "event") &&
    (data.publishedOrganizationId ?? null) === (content.data.organizationId ?? null) &&
    (data.publishedOrganizationName ?? null) === (content.data.organizationName ?? null) &&
    data.publicationOutcome === publicationOutcomeForContent(content.data) &&
    data.historyBackfillStatus === "matched" &&
    Boolean(data.historyBackfilledAt);
}

function hasExactEventIdentity(draftData, contentData) {
  const draftPayload = draftData.payload && typeof draftData.payload === "object"
    ? draftData.payload
    : {};
  const draftTitle = normalizeText(draftData.title ?? draftPayload.title);
  const contentTitle = normalizeText(contentData.title);
  const draftStart = timestampMilliseconds(draftPayload.startDate);
  const contentStart = timestampMilliseconds(contentData.startDate);
  return Boolean(draftTitle) && draftTitle === contentTitle &&
    draftStart !== undefined && draftStart === contentStart;
}

function normalizeText(value) {
  return typeof value === "string"
    ? value.trim().toLocaleLowerCase("uk-UA").replace(/\s+/g, " ")
    : "";
}

function timestampMilliseconds(value) {
  if (value instanceof Date) return value.getTime();
  if (value && typeof value.toMillis === "function") return value.toMillis();
  if (value && Number.isFinite(value.seconds)) {
    return value.seconds * 1000 + Math.floor((value.nanoseconds ?? 0) / 1_000_000);
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function requiredOption(value, flag) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`${flag} is required.`);
  return value.trim();
}

function nonNegativeOption(value, flag) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${flag} must be a non-negative integer.`);
  }
  return parsed;
}
