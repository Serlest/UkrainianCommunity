#!/usr/bin/env node

import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {calendarDateFromText, plainText, viennaDate} from "./newsSourceEvidence.mjs";

function elementContent(page, startPattern, tag) {
  const start = startPattern.exec(page);
  if (!start) return null;
  const offset = start.index + start[0].length;
  let depth = 1;
  for (const match of page.slice(offset).matchAll(new RegExp(`<\\/?${tag}\\b[^>]*>`, "gi"))) {
    depth += /^<\//.test(match[0]) ? -1 : 1;
    if (depth === 0) return page.slice(offset, offset + match.index);
  }
  throw new Error("Primary article container is incomplete.");
}

function articleMetadata(page, url) {
  const found = [];
  const identity = (value) => {
    try { const u = new URL(value, url); return u.origin + u.pathname.replace(/\/$/, ""); }
    catch { return null; }
  };
  const visit = (value) => {
    if (!value || typeof value !== "object") return;
    const types = [value["@type"]].flat();
    const target = value.url ?? value.mainEntityOfPage?.["@id"] ?? value["@id"];
    if (types.some((type) => ["NewsArticle", "Article", "ReportageNewsArticle"].includes(type)) &&
        target && identity(target) === identity(url.href)) found.push(value);
    for (const child of Object.values(value)) if (typeof child === "object") {
      if (Array.isArray(child)) child.forEach(visit); else visit(child);
    }
  };
  for (const script of page.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { visit(JSON.parse(script[1])); } catch { /* Other scripts may contain the primary article. */ }
  }
  return found[0] ?? null;
}

function noenArticle(page, url) {
  if (!/(^|\.)noen\.at$/.test(url.hostname)) return null;
  const main = elementContent(page, /<main\b[^>]*id=["']main-content["'][^>]*>/i, "main");
  if (!main) throw new Error("NÖN primary article main-content is missing.");
  const body = elementContent(main, /<div\b[^>]*class=["'][^"']*\barticle-body-text\b[^"']*["'][^>]*>/i, "div");
  if (!body || !plainText(body)) throw new Error("NÖN primary article body is missing; related cards are not article evidence.");
  const heading = main.match(/<h1\b[^>]*>[\s\S]*?<\/h1>/i)?.[0];
  if (!heading) throw new Error("NÖN primary article headline is missing.");
  return `${heading}\n${body}`;
}

export function articleBodyURL(value) {
  const url = new URL(value);
  if (url.hostname === "www.ktn.gv.at" && url.pathname === "/Service/News" && /^\d+$/.test(url.searchParams.get("nid") ?? "")) {
    return `https://www.ktn.gv.at/Service/News/dyncontent?nid=${url.searchParams.get("nid")}`;
  }
  return url.href;
}

function officialNOEArticle(page, url) {
  if (url.hostname !== "www.noe.gv.at") return null;
  const start = /<div\b[^>]*class=["'][^"']*\bmain-cont\b[^"']*\bpressarticle\b[^"']*["'][^>]*>/i.exec(page);
  if (!start) return null;
  const offset = start.index + start[0].length;
  let depth = 1;
  for (const tag of page.slice(offset).matchAll(/<\/?div\b[^>]*>/gi)) {
    depth += /^<\//.test(tag[0]) ? -1 : 1;
    if (depth === 0) return page.slice(offset, offset + tag.index);
  }
  throw new Error("Official NÖ press article container is incomplete.");
}

export async function readNewsArticle(value, fetchImpl = fetch) {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password) throw new Error("A direct HTTPS article URL is required.");
  const pages = [];
  for (const requestURL of [...new Set([url.href, articleBodyURL(url.href)])]) {
    const response = await fetchImpl(requestURL, {signal: AbortSignal.timeout(20_000), redirect: "follow"});
    if (!response.ok) throw new Error(`Article fetch failed: ${response.status} ${requestURL}`);
    const body = await response.text();
    if (Buffer.byteLength(body) > 8_000_000) throw new Error("Article body too large.");
    pages.push({url: response.url || requestURL, body});
  }
  const page = pages.at(-1).body;
  const metadata = articleMetadata(page, url);
  const content = noenArticle(page, url) ?? officialNOEArticle(page, url) ?? page.match(/<article\b[^>]*>([\s\S]*?)<\/article>/i)?.[1] ??
    page.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i)?.[1] ?? page;
  const text = plainText(content);
  const title = plainText(content.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ??
    page.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ??
    pages[0].body.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ?? "");
  const candidates = new Set();
  // Related-card JSON-LD must not make an open primary article look paywalled.
  // Never infer unrestricted access from metadata alone or extract hidden paid text.
  const accessRestricted = metadata ? [false, "false"].includes(metadata.isAccessibleForFree) :
    pages.some(({body}) => /"isAccessibleForFree"\s*:\s*(?:false|"false")/i.test(body));
  const publicationDateEvidence = ["datePublished", "dateModified"].flatMap((field) => {
    const value = metadata?.[field];
    const date = value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : value ? viennaDate(value) : null;
    return date ? [{field, value, date, origin: "primary_article_jsonld", requiresEditorialReview: true}] : [];
  });
  for (const evidence of publicationDateEvidence) candidates.add(evidence.date);
  for (const match of content.matchAll(/\b\d{1,2}\.\d{1,2}\.\d{4}\b/g)) {
    const date = calendarDateFromText(match[0]);
    if (date) candidates.add(date);
  }
  return {requestedArticleURL: url.href, fetchedURLs: pages.map((p) => p.url), title,
    text: text.slice(0, 24_000), textTruncated: text.length > 24_000,
    dateCandidates: [...candidates], publicationDateEvidence, accessRestricted,
    note: "Dates in the body may describe events. Confirm the publication/update date label before using sourceEventDate. accessRestricted detects declared paid access only; false does not prove full text. Review the opened article for teasers, subscription notices and missing body; this reader makes no editorial decision."};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (!process.argv[2]) throw new Error("Usage: node newsReadArticle.mjs <direct-article-url>");
    console.log(JSON.stringify(await readNewsArticle(process.argv[2]), null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
