#!/usr/bin/env node

import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {calendarDateFromText, plainText} from "./newsSourceEvidence.mjs";

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
  const content = officialNOEArticle(page, url) ?? page.match(/<article\b[^>]*>([\s\S]*?)<\/article>/i)?.[1] ??
    page.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i)?.[1] ?? page;
  const text = plainText(content);
  const title = plainText(content.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ??
    page.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ??
    pages[0].body.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ?? "");
  const candidates = new Set();
  const accessRestricted = pages.some(({body}) => /"isAccessibleForFree"\s*:\s*(?:false|"false")/i.test(body));
  for (const match of content.matchAll(/\b\d{1,2}\.\d{1,2}\.\d{4}\b/g)) {
    const date = calendarDateFromText(match[0]);
    if (date) candidates.add(date);
  }
  return {requestedArticleURL: url.href, fetchedURLs: pages.map((p) => p.url), title,
    text: text.slice(0, 24_000), textTruncated: text.length > 24_000,
    dateCandidates: [...candidates], accessRestricted,
    note: "Dates in the body may describe events. Confirm the publication/update date label before using sourceEventDate. accessRestricted detects declared paid access only; false does not prove full text. Review the opened article for teasers, subscription notices and missing body; this reader makes no editorial decision."};
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (!process.argv[2]) throw new Error("Usage: node newsReadArticle.mjs <direct-article-url>");
    console.log(JSON.stringify(await readNewsArticle(process.argv[2]), null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
