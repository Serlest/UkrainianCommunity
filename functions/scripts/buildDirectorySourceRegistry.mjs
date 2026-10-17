#!/usr/bin/env node
import {writeFileSync} from "node:fs";
import {contentAutomationAccessToken, decodeSuccessfulJSON} from "./contentAutomationCredential.mjs";

const projectId = "ukrainiancommunity-dbd5f";
const base = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;

function authorityHint(rawURL) {
  let url;
  try { url = new URL(rawURL); } catch { return "invalid_url"; }
  if (url.protocol !== "https:") return "invalid_url";
  const host = url.hostname.toLowerCase();
  if (host.endsWith(".gv.at") || host === "gv.at") return "austrian_public_authority_candidate";
  if (host.endsWith(".gov.ua") || host === "gov.ua") return "ukrainian_public_authority_candidate";
  if (host === "eur-lex.europa.eu" || host.endsWith(".europa.eu")) return "eu_institution_candidate";
  if (["ams.at", "www.ams.at", "oegk.at", "www.oegk.at", "rtr.at", "www.rtr.at"]
    .includes(host)) return "austrian_public_body_candidate";
  return "competence_unverified";
}

function addSource(registry, source, target) {
  if (!source || typeof source.url !== "string" || !source.url.trim()) return;
  const existing = registry.get(source.url) ?? {
    url: source.url, names: new Set(), authorityHint: authorityHint(source.url), targets: [],
    verification: "not_checked",
  };
  if (typeof source.name === "string") existing.names.add(source.name);
  existing.targets.push(target);
  registry.set(source.url, existing);
}

export function registryFromCategories(categories) {
  const registry = new Map();
  const topics = [];
  for (const category of categories) {
    for (const topic of category.topics ?? []) {
      const target = {categoryId: category.id, topicId: topic.id};
      topics.push(target);
      for (const source of topic.sources ?? []) addSource(registry, source, {...target, location: "topic-source"});
      for (const section of topic.sections ?? []) {
        addSource(registry, section.source, {...target, location: "section", sectionId: section.id});
      }
      for (const [federalState, sections] of Object.entries(topic.regionalSections ?? {})) {
        for (const section of sections) {
          addSource(registry, section.source,
            {...target, location: "regional-section", federalState, sectionId: section.id});
        }
      }
    }
  }
  const sources = [...registry.values()].map((entry) => ({...entry, names: [...entry.names].sort(),
    targets: entry.targets.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)))}))
    .sort((a, b) => a.url.localeCompare(b.url));
  return {topicCount: topics.length, sources,
    topicsWithoutAuthorityCandidate: topics.filter((topic) => !sources.some((source) =>
      source.authorityHint !== "competence_unverified" && source.authorityHint !== "invalid_url" &&
      source.targets.some((target) => target.categoryId === topic.categoryId && target.topicId === topic.topicId))),
  };
}

export async function buildDirectorySourceRegistry({outputPath, getAccessToken = contentAutomationAccessToken,
  fetchImpl = fetch} = {}) {
  if (!outputPath) throw new Error("Pass --output FILE for an immutable registry snapshot.");
  const token = await getAccessToken();
  const categories = [];
  const revisions = [];
  let pageToken;
  do {
    const url = `${base}/directoryCategories?pageSize=100${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ""}`;
    const data = await decodeSuccessfulJSON(await fetchImpl(url, {
      headers: {Authorization: `Bearer ${token}`},
    }), "Read published directory catalog");
    for (const document of data.documents ?? []) {
      const payload = document.fields?.payload?.stringValue;
      if (!payload || document.fields?.isDeleted?.booleanValue === true) continue;
      const category = JSON.parse(payload);
      categories.push(category);
      revisions.push({categoryId: category.id, revision: Number(document.fields?.revision?.integerValue ?? 0),
        updateTime: document.updateTime});
    }
    pageToken = data.nextPageToken;
  } while (pageToken);
  const catalogMarker = await decodeSuccessfulJSON(await fetchImpl(`${base}/appConfig/directoryCatalog`, {
    headers: {Authorization: `Bearer ${token}`},
  }), "Read directory migration marker");
  if (catalogMarker.fields?.migrationComplete?.booleanValue !== true ||
      catalogMarker.fields?.source?.stringValue !== "firestore") {
    throw new Error("Published catalog migration is not complete.");
  }
  const registry = registryFromCategories(categories);
  const snapshot = {schemaVersion: 1, capturedAt: new Date().toISOString(), projectId,
    categoryCount: categories.length, topicCount: registry.topicCount,
    revisions: revisions.sort((a, b) => a.categoryId.localeCompare(b.categoryId)),
    sourceCount: registry.sources.length,
    sources: registry.sources, topicsWithoutAuthorityCandidate: registry.topicsWithoutAuthorityCandidate};
  writeFileSync(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`, {flag: "wx", mode: 0o600});
  return {categoryCount: snapshot.categoryCount, topicCount: snapshot.topicCount,
    sourceCount: snapshot.sourceCount,
    topicsWithoutAuthorityCandidate: snapshot.topicsWithoutAuthorityCandidate.length,
    outputPath};
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  if (args.length !== 2 || args[0] !== "--output") {
    console.error("Usage: node buildDirectorySourceRegistry.mjs --output FILE");
    process.exitCode = 2;
  } else {
    buildDirectorySourceRegistry({outputPath: args[1]}).then((result) => console.log(JSON.stringify(result)))
      .catch((error) => { console.error(error.message); process.exitCode = 1; });
  }
}
