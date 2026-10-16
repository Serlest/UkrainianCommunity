#!/usr/bin/env node

import {createHash, randomUUID} from "node:crypto";
import {access, link, mkdir, readFile, rename, rmdir, unlink, writeFile} from "node:fs/promises";
import {join, resolve} from "node:path";
import {pathToFileURL} from "node:url";

import {planUniqueSourceFetches} from "./newsScopeCoordination.mjs";
import {extractORFFeedLinks, selectCoreOfficialArticles} from "./newsSourceEvidence.mjs";

const maximumSourceBytes = 8_000_000;
const maximumSourceLinks = 3_500;

export function requestURLForSource(source, now = new Date()) {
  const url = new URL(source.url);
  if (url.hostname === "www.wienerlinien.at" && url.pathname.replace(/\/$/, "") === "/news") {
    return "https://tramwm.wienerlinien.at/web/guest/news";
  }
  if (url.hostname === "salzburg-verkehr.at" && url.pathname.replace(/\/$/, "") === "/aktuelles/verkehr") {
    return "https://salzburg-verkehr.at/wp-json/mccom/v1/traffic/de";
  }
  if (url.hostname.endsWith("ris.bka.gv.at") && url.pathname === "/Ergebnis.wxe") {
    const start = new Date(now.getTime() - 25 * 60 * 60 * 1000);
    const format = (date) => `${String(date.getUTCDate()).padStart(2, "0")}.${String(date.getUTCMonth() + 1).padStart(2, "0")}.${date.getUTCFullYear()}`;
    for (const key of ["VonDatum", "ImRisSeitVonDatum"]) url.searchParams.set(key, format(start));
    for (const key of ["BisDatum", "ImRisSeitBisDatum"]) url.searchParams.set(key, format(now));
  }
  return url.href;
}

async function boundedText(response) {
  const reader = response.body?.getReader();
  if (!reader) return "";
  const parts = [];
  let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maximumSourceBytes) throw new Error("source-body-too-large");
      parts.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  return new TextDecoder().decode(Buffer.concat(parts));
}

export function extractSourceLinks(html, baseURL) {
  const links = [];
  const seen = new Set();
  for (const match of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    let url;
    try { url = new URL(match[1].replace(/&amp;/g, "&"), baseURL); } catch { continue; }
    if (!["http:", "https:"].includes(url.protocol)) continue;
    url.hash = "";
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    links.push({url: url.href, title: match[2].replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim().slice(0, 240)});
    if (links.length === maximumSourceLinks) break;
  }
  return links;
}

// AMS embeds its news index as HTML-escaped structured data rather than links.
// Keep only recent article paths; every article still needs direct review.
export function extractAMSNewsLinks(html, baseURL, now = new Date()) {
  const decoded = html.replace(/&#34;|&quot;/g, '"');
  const earliest = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
  const links = [];
  const seen = new Set();
  const pattern = /"path"\s*:\s*"(\/regionen\/[^"\s]+\/news\/(\d{4})\/(\d{2})\/[^"\s]+)"/g;
  for (const match of decoded.matchAll(pattern)) {
    const month = new Date(Date.UTC(Number(match[2]), Number(match[3]) - 1, 1));
    if (month < earliest || month > now) continue;
    const url = new URL(match[1], baseURL).href;
    if (seen.has(url)) continue;
    seen.add(url);
    const nearby = decoded.slice(match.index, match.index + 2_000);
    const title = nearby.match(/"header"\s*:\s*"([^"\n]+)"/)?.[1] ?? "AMS Nachricht";
    links.push({url, title: title.slice(0, 240)});
    if (links.length === maximumSourceLinks) break;
  }
  return links;
}

// Salzburg Verkehr renders its traffic listing from its own public JSON feed.
// The HTML listing contains only navigation links before JavaScript runs.
export function extractSalzburgTrafficLinks(json) {
  const entries = JSON.parse(json);
  if (!Array.isArray(entries)) throw new Error("invalid-salzburg-traffic-feed");
  const links = [];
  const seen = new Set();
  for (const entry of entries) {
    if (typeof entry?.link !== "string" || typeof entry?.title !== "string") continue;
    let url;
    try { url = new URL(entry.link); } catch { continue; }
    if (url.protocol !== "https:" || url.hostname !== "salzburg-verkehr.at") continue;
    url.hash = "";
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    links.push({url: url.href, title: entry.title.trim().slice(0, 240)});
    if (links.length === maximumSourceLinks) break;
  }
  return links;
}

// ÖBB's traffic newsroom wraps article cards in nested anchors and comments.
// A generic anchor parser includes those comments in titles and can bury the
// actual service notice among navigation links.
export function extractOEBBTrafficLinks(html, baseURL) {
  const links = [];
  const seen = new Set();
  const pattern = /<div\s+class="isotope-item[^\"]*"\s+data-id="\d+"[^>]*>\s*<a\s+href=['"]([^'"]+)['"][\s\S]*?<h3>([\s\S]*?)<\/h3>/gi;
  for (const match of html.matchAll(pattern)) {
    let url;
    try { url = new URL(match[1].replace(/&amp;/g, "&"), baseURL); } catch { continue; }
    if (url.hostname !== "presse-oebb.com" || !url.pathname.startsWith("/news-")) continue;
    url.hash = "";
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    const title = match[2].replace(/<[^>]*>/g, " ").replace(/&amp;/g, "&")
      .replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim().slice(0, 240);
    links.push({url: url.href, title});
    if (links.length === maximumSourceLinks) break;
  }
  if (!links.length) throw new Error("invalid-oebb-traffic-listing");
  return links;
}

export function extractOEBBLiveLinks(html, baseURL) {
  const links = extractSourceLinks(html, baseURL).filter(({url}) => {
    const parsed = new URL(url);
    return parsed.hostname === "www.unsereoebb.at" &&
      parsed.pathname.startsWith("/de/verkehrsmeldungen~");
  });
  if (!links.length) throw new Error("invalid-oebb-live-listing");
  return links;
}

export async function inspectNewsSource(source, fetchImpl = fetch, now = new Date()) {
  const requestedURL = requestURLForSource(source, now);
  const checkedAt = now.toISOString();
  try {
    const response = await fetchImpl(requestedURL, {
      redirect: "follow",
      signal: AbortSignal.timeout(16_000),
      headers: {"user-agent": "UAC News source monitor"},
    });
    const body = await boundedText(response);
    const botBlocked = response.ok && source.sourceId === "https://www.wienerlinien.at/news" &&
      /<title>\s*Radware Page\s*<\/title>/i.test(body);
    const text = body.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
      .replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    let links = [];
    if (response.ok && !botBlocked) {
      const host = new URL(requestedURL).hostname;
      links = host === "rss.orf.at" ? extractORFFeedLinks(body) :
        requestedURL === "https://salzburg-verkehr.at/wp-json/mccom/v1/traffic/de"
          ? extractSalzburgTrafficLinks(body)
          : host === "presse-oebb.com" && new URL(requestedURL).pathname === "/News.aspx"
          ? extractOEBBTrafficLinks(body, response.url || requestedURL)
          : host === "www.unsereoebb.at" && new URL(requestedURL).pathname === "/de/verkehrsmeldungen"
          ? extractOEBBLiveLinks(body, response.url || requestedURL)
          : host === "www.ams.at" ? extractAMSNewsLinks(body, response.url || requestedURL, now)
          : selectCoreOfficialArticles(extractSourceLinks(body, response.url || requestedURL), body, requestedURL, now);
      if (!links.length && ["www.ages.at", "www.bmf.gv.at", "www.integrationsfonds.at"].includes(host)) {
        throw new Error("source-article-extraction-empty");
      }
    }
    return {
      sourceId: source.sourceId,
      recipients: source.recipients,
      editorialMode: source.editorialMode,
      discoveryOnly: source.editorialMode === "discovery",
      requestedURL,
      finalURL: response.url || requestedURL,
      checkedAt,
      httpStatus: response.status,
      contentType: response.headers.get("content-type"),
      etag: response.headers.get("etag"),
      lastModified: response.headers.get("last-modified"),
      contentHash: createHash("sha256").update(text).digest("hex"),
      links,
      error: botBlocked ? "source-bot-protection-page" : response.ok ? null : `http-${response.status}`,
    };
  } catch (error) {
    return {
      sourceId: source.sourceId,
      recipients: source.recipients,
      requestedURL,
      checkedAt,
      httpStatus: 0,
      links: [],
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

export async function scanNewsSources(registry, {fetchImpl = fetch, now = new Date(), concurrency = 6} = {}) {
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 10) {
    throw new Error("Scan concurrency must be from 1 to 10.");
  }
  const plan = planUniqueSourceFetches(registry);
  const results = new Array(plan.length);
  let next = 0;
  await Promise.all(Array.from({length: Math.min(concurrency, plan.length)}, async () => {
    while (next < plan.length) {
      const index = next++;
      results[index] = await inspectNewsSource(plan[index], fetchImpl, now);
    }
  }));
  return results;
}

export async function runNewsSharedScan(outputRoot, runId, {fetchImpl = fetch, now = new Date()} = {}) {
  if (!/^news-\d{4}-\d{2}-\d{2}T\d{2}$/.test(runId)) throw new Error("Invalid news run ID.");
  const registry = JSON.parse(await readFile(join(outputRoot, "source-registry.json"), "utf8"));
  const snapshots = join(outputRoot, "snapshots");
  const target = join(snapshots, `${runId}.json`);
  if (await access(target).then(() => true, () => false)) {
    throw new Error(`Shared discovery snapshot already exists: ${runId}`);
  }
  const lock = join(outputRoot, "shared-scan.lock");
  const token = randomUUID();
  await mkdir(lock);
  let ownerWritten = false;
  try {
    await writeFile(join(lock, "owner.json"), JSON.stringify({runId, token, startedAt: now.toISOString()}));
    ownerWritten = true;
    const sharedPath = join(outputRoot, "shared-source-state.json");
    const sharedState = JSON.parse(await readFile(sharedPath, "utf8"));
    for (const source of planUniqueSourceFetches(registry)) {
      if (!sharedState.sources[source.sourceId]) {
        throw new Error(`Missing shared source state: ${source.sourceId}`);
      }
    }
    const results = (await scanNewsSources(registry, {fetchImpl, now})).map((row) => ({
      ...row, sourcePolicyVersion: registry.editorialPolicyVersion ?? 1,
    }));
    await mkdir(snapshots, {recursive: true});
    const temporary = join(snapshots, `.${runId}.${token}.tmp`);
    try {
      await writeFile(temporary, JSON.stringify(results) + "\n");
      await link(temporary, target);
    } finally {
      await unlink(temporary).catch(() => {});
    }
    for (const row of results) {
      const state = sharedState.sources[row.sourceId];
      if (!state) throw new Error(`Missing shared source state: ${row.sourceId}`);
      state.lastFetchAt = row.checkedAt;
      state.lastSnapshotId = runId;
      if (row.etag) state.etag = row.etag;
      if (row.lastModified) state.lastModified = row.lastModified;
    }
    const stateTemporary = `${sharedPath}.${token}.tmp`;
    await writeFile(stateTemporary, JSON.stringify(sharedState, null, 2) + "\n");
    await rename(stateTemporary, sharedPath);
    return {runId, snapshotPath: target, sources: results.length,
      failed: results.filter((row) => row.error).length};
  } finally {
    if (!ownerWritten) {
      await rmdir(lock);
    } else {
      const ownerPath = join(lock, "owner.json");
      const owner = JSON.parse(await readFile(ownerPath, "utf8"));
      if (owner.token !== token) throw new Error("Shared scan lock owner changed; refusing to release it.");
      await unlink(ownerPath);
      await rmdir(lock);
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [outputRoot, runId, mode] = process.argv.slice(2);
  if (!outputRoot || !runId || (mode && mode !== "--run")) {
    console.error("Usage: node scripts/newsSharedScan.mjs <news-scopes-directory> <news-YYYY-MM-DDTHH> [--run]");
    process.exitCode = 1;
  } else {
    try {
      if (mode === "--run") {
        console.log(JSON.stringify(await runNewsSharedScan(resolve(outputRoot), runId)));
      } else {
        const registry = JSON.parse(await readFile(join(resolve(outputRoot), "source-registry.json"), "utf8"));
        console.log(JSON.stringify({dryRun: true, runId, uniqueSources: planUniqueSourceFetches(registry).length}));
      }
    } catch (error) {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    }
  }
}
