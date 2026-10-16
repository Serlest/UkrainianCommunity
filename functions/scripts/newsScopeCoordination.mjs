import {mkdir, readFile, rename, rm, writeFile} from "node:fs/promises";
import {dirname, join} from "node:path";
import {randomUUID} from "node:crypto";
import {NEWS_DISCOVERY_POLICY_VERSION, NEWS_EDITORIAL_SOURCES} from "./newsEditorialSources.mjs";
import {viennaDate} from "./newsSourceEvidence.mjs";

export const NEWS_SCOPES = Object.freeze([
  "wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol",
  "vorarlberg", "steiermark", "kaernten", "burgenland", "austria",
]);

const scopeSet = new Set(NEWS_SCOPES);
const trackingKeys = new Set(["ref", "sessionid", "fbclid", "gclid", "dclid"]);

export function canonicalNewsURL(value) {
  const url = new URL(value);
  if (!new Set(["https:", "http:"]).has(url.protocol)) {
    throw new Error(`Unsupported source URL: ${value}`);
  }
  url.hash = "";
  url.hostname = url.hostname.toLowerCase();
  for (const key of [...url.searchParams.keys()]) {
    if (trackingKeys.has(key.toLowerCase()) || key.toLowerCase().startsWith("utm_")) {
      url.searchParams.delete(key);
    }
  }
  url.searchParams.sort();
  url.pathname = url.pathname.replace(/\/$/, "") || "/";
  return url.href;
}

export function buildNewsScopeLayout(legacyProgress, initializedAt = new Date().toISOString()) {
  if (!legacyProgress || typeof legacyProgress.sourceProgress !== "object") {
    throw new Error("A legacy sourceProgress registry is required.");
  }
  const sourcesByURL = new Map();
  const warnings = [];
  for (const [legacyKey, source] of Object.entries(legacyProgress.sourceProgress)) {
    const sourceId = source?.sourceId || legacyKey;
    const url = source?.url;
    if (!url) {
      warnings.push({sourceId, reason: "missing-url"});
      continue;
    }
    let identity;
    try {
      identity = canonicalNewsURL(url);
    } catch {
      warnings.push({sourceId, reason: "invalid-url"});
      continue;
    }
    const scopes = [...new Set(source.scopes || [])];
    const unknown = scopes.filter((scope) => !scopeSet.has(scope));
    if (unknown.length) {
      warnings.push({sourceId, reason: "unknown-scope", scopes: unknown});
    }
    const assigned = scopes.filter((scope) => scopeSet.has(scope));
    if (!assigned.length) {
      warnings.push({sourceId, reason: "unassigned-scope"});
    }
    const existing = sourcesByURL.get(identity);
    if (existing) {
      if (existing.type !== source.type) {
        throw new Error(`Conflicting source types for ${identity}`);
      }
      existing.legacyIds.push(sourceId);
      existing.scopes = [...new Set([...existing.scopes, ...assigned])];
      existing.active = existing.scopes.length > 0;
      continue;
    }
    sourcesByURL.set(identity, {
      sourceId,
      url: identity,
      type: source.type || "unclassified",
      scopes: assigned,
      legacyIds: [sourceId],
      active: assigned.length > 0,
    });
  }
  const sources = [...sourcesByURL.values()].sort((a, b) => a.sourceId.localeCompare(b.sourceId));
  const sharedSources = Object.fromEntries(sources.map((source) => [source.sourceId, {
    lastFetchAt: null,
    lastSnapshotId: null,
    etag: null,
    lastModified: null,
  }]));
  const scopeStates = Object.fromEntries(NEWS_SCOPES.map((scope) => [scope, {
    schemaVersion: 1,
    scope,
    status: "prepared_not_active",
    lastRun: null,
    sourceProgress: Object.fromEntries(sources
      .filter((source) => source.scopes.includes(scope))
      .map((source) => [source.sourceId, {processedThrough: null, nextPage: null, lastReviewedAt: null}])),
    candidateDecisions: {},
  }]));
  return {
    manifest: {
      schemaVersion: 1,
      status: "prepared_not_active",
      initializedAt,
      scopeCount: NEWS_SCOPES.length,
      sourceCount: sources.length,
      activeSourceCount: sources.filter((source) => source.active).length,
      sharedSourceCount: sources.filter((source) => source.scopes.length > 1).length,
      legacyPendingImported: 0,
      candidateDisposition: "terminal_same_pass_or_run_partial",
      publisher: "functions/scripts/contentPublishingLocalBridge.mjs",
      publisherNote: "Use the existing publisher and its Firestore identity locks under the shared content-work lock.",
      warnings,
    },
    registry: {schemaVersion: 1, initializedAt, sources},
    sharedState: {schemaVersion: 1, initializedAt, sources: sharedSources},
    scopeStates,
  };
}

export function planUniqueSourceFetches(registry, requestedScopes = NEWS_SCOPES) {
  const wanted = new Set(requestedScopes);
  if ([...wanted].some((scope) => !scopeSet.has(scope))) {
    throw new Error("Unknown news scope in fetch request.");
  }
  return registry.sources
    .filter((source) => source.active && source.scopes.some((scope) => wanted.has(scope)))
    .map(({sourceId, url, type, scopes, editorialMode, topics, primaryPolicy, publisherGroup}) => ({
      sourceId, url, type, editorialMode, topics, primaryPolicy, publisherGroup,
      recipients: scopes.filter((scope) => wanted.has(scope)),
    }));
}

export function applyNewsEditorialSources(registry, entries = NEWS_EDITORIAL_SOURCES) {
  const byURL = new Map();
  for (const entry of entries) {
    const identity = canonicalNewsURL(entry.url);
    if (byURL.has(identity)) throw new Error(`Duplicate editorial source: ${identity}`);
    if (!new Set(["scan", "discovery", "adapter", "reference"]).has(entry.mode)) {
      throw new Error(`Unknown editorial source mode: ${entry.mode}`);
    }
    if (!entry.scopes.length || entry.scopes.some((scope) => !scopeSet.has(scope))) {
      throw new Error(`Invalid editorial source scopes: ${identity}`);
    }
    byURL.set(identity, {...entry, url: identity});
  }
  const sources = registry.sources.map((source) => {
    const entry = byURL.get(canonicalNewsURL(source.url));
    if (entry) byURL.delete(entry.url);
    return entry ? {...source, scopes: [...entry.scopes], active: ["scan", "discovery"].includes(entry.mode),
      type: entry.mode === "discovery" ? "media" : source.type,
      primaryPolicy: entry.primaryPolicy, publisherGroup: entry.publisherGroup, note: entry.note,
      editorialMode: entry.mode, topics: [...entry.topics]} :
      {...source, active: false, editorialMode: "excluded", topics: []};
  });
  for (const entry of byURL.values()) {
    sources.push({sourceId: entry.url, url: entry.url, type: entry.mode === "discovery" ? "media" : "official",
      scopes: [...entry.scopes], legacyIds: [], active: ["scan", "discovery"].includes(entry.mode),
      editorialMode: entry.mode, topics: [...entry.topics], primaryPolicy: entry.primaryPolicy,
      publisherGroup: entry.publisherGroup, note: entry.note});
  }
  sources.sort((a, b) => a.sourceId.localeCompare(b.sourceId));
  return {...registry, editorialPolicyVersion: NEWS_DISCOVERY_POLICY_VERSION, sources};
}

export function routeNewsCandidate(candidate) {
  if (candidate?.regionScope === "austria" && !candidate.federalState) return "austria";
  if (candidate?.regionScope === "federalState" && scopeSet.has(candidate.federalState)
      && candidate.federalState !== "austria") return candidate.federalState;
  throw new Error("Candidate needs one explicit federal-state or Austria-wide territory.");
}

export function buildScopeDiscoveryBatch(registry, discoveryRows, scope) {
  if (!scopeSet.has(scope)) throw new Error(`Unknown news scope: ${scope}`);
  if (!Array.isArray(discoveryRows)) throw new Error("A shared discovery result array is required.");
  const allowed = new Set(registry.sources
    .filter((source) => source.active && source.scopes.includes(scope))
    .map((source) => source.sourceId));
  const seen = new Set();
  const results = [];
  for (const row of discoveryRows) {
    if (!allowed.has(row?.sourceId)) continue;
    if (seen.has(row.sourceId)) throw new Error(`Duplicate shared discovery result: ${row.sourceId}`);
    seen.add(row.sourceId);
    results.push(row);
  }
  return {
    schemaVersion: 1,
    scope,
    expectedSources: allowed.size,
    observedSources: results.length,
    missingSourceIds: [...allowed].filter((sourceId) => !seen.has(sourceId)),
    onDemandOfficialSources: registry.sources
      .filter((source) => source.editorialMode === "adapter" && source.scopes.includes(scope))
      .map(({sourceId, url, topics}) => ({sourceId, url, topics})),
    results,
  };
}

// RSS windows are short. Union the same day's immutable observations so an
// article which rolls off before the next editorial pass is still discoverable.
// Keep current source errors: an earlier success must never mask a failed scan.
export function mergeTodayDiscovery(currentRows, previousSnapshots, day) {
  return currentRows.map((current) => {
    const links = new Map();
    const add = (row) => {
      for (const link of row.links ?? []) {
        const key = canonicalNewsURL(link.url);
        const previous = links.get(key);
        links.set(key, {...link,
          firstSeenAt: previous?.firstSeenAt ?? row.checkedAt,
          lastSeenAt: row.checkedAt});
      }
    };
    const historical = previousSnapshots.flat().filter((row) => row.sourceId === current.sourceId &&
      (row.sourcePolicyVersion ?? 1) === (current.sourcePolicyVersion ?? 1) &&
      viennaDate(row.checkedAt) === day && row.checkedAt <= current.checkedAt)
      .sort((a, b) => a.checkedAt.localeCompare(b.checkedAt));
    for (const row of historical) add(row);
    add(current);
    return {...current, links: [...links.values()], discoveryWindow: "current_vienna_day"};
  });
}

export async function prepareNewsScopeLayout(legacyPath, outputPath, {write = false} = {}) {
  const legacy = JSON.parse(await readFile(legacyPath, "utf8"));
  const layout = buildNewsScopeLayout(legacy);
  if (!write) return layout.manifest;
  const parent = dirname(outputPath);
  await mkdir(parent, {recursive: true});
  const temporaryPath = `${outputPath}.tmp-${randomUUID()}`;
  try {
    await mkdir(join(temporaryPath, "scopes"), {recursive: true});
    await Promise.all([
      writeFile(join(temporaryPath, "manifest.json"), JSON.stringify(layout.manifest, null, 2) + "\n"),
      writeFile(join(temporaryPath, "source-registry.json"), JSON.stringify(layout.registry, null, 2) + "\n"),
      writeFile(join(temporaryPath, "shared-source-state.json"), JSON.stringify(layout.sharedState, null, 2) + "\n"),
      ...NEWS_SCOPES.map((scope) => writeFile(
        join(temporaryPath, "scopes", `${scope}.json`),
        JSON.stringify(layout.scopeStates[scope], null, 2) + "\n",
      )),
    ]);
    await rename(temporaryPath, outputPath);
  } catch (error) {
    await rm(temporaryPath, {recursive: true, force: true});
    throw error;
  }
  return layout.manifest;
}
