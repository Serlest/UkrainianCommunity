// Discovery metadata is a lead, never a substitute for the direct official
// article's date or an editorial publication decision.
export function plainText(value = "") {
  return value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]*>/g, " ")
    .replace(/&#(x[0-9a-f]+|\d+);/gi, (_, code) => {
      const point = code[0].toLowerCase() === "x" ? parseInt(code.slice(1), 16) : Number(code);
      return point > 0 && point <= 0x10ffff ? String.fromCodePoint(point) : " ";
    })
    .replace(/&(amp|quot|apos|lt|gt|nbsp|ouml|auml|uuml|Ouml|Auml|Uuml|szlig);/g,
      (_, name) => ({amp: "&", quot: '"', apos: "'", lt: "<", gt: ">", nbsp: " ",
        ouml: "ö", auml: "ä", uuml: "ü", Ouml: "Ö", Auml: "Ä", Uuml: "Ü", szlig: "ß"})[name])
    .replace(/\s+/g, " ").trim();
}

export function viennaDate(value) {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return null;
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Vienna", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(date).map(({type, value}) => [type, value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function calendarDateFromText(value) {
  const text = plainText(value);
  const numeric = text.match(/\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b/);
  const months = ["Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
  const named = text.match(/\b(\d{1,2})\.\s*(Jänner|Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember)\s+(\d{4})\b/i);
  let date;
  if (numeric) date = `${numeric[3]}-${numeric[2].padStart(2, "0")}-${numeric[1].padStart(2, "0")}`;
  else if (named) {
    const month = named[2].toLowerCase() === "januar" ? 1 : months.findIndex((m) => m.toLowerCase() === named[2].toLowerCase()) + 1;
    date = `${named[3]}-${String(month).padStart(2, "0")}-${named[1].padStart(2, "0")}`;
  }
  const parsed = new Date(`${date}T00:00:00Z`);
  return date && Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === date ? date : null;
}

export function extractMediaFeedLinks(xml, sourceURL, label = "media") {
  if (!/<(?:rss|rdf:RDF|feed)\b/i.test(xml)) throw new Error(`invalid-${label}-feed`);
  const links = [];
  const seen = new Set();
  const root = new URL(sourceURL).hostname.replace(/^www\./, "").replace(/^rss\./, "");
  const field = (item, tag) => item.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"))?.[1] ?? "";
  for (const match of xml.matchAll(/<(item|entry)\b[^>]*>([\s\S]*?)<\/\1>/gi)) {
    const item = match[2];
    let url;
    const link = plainText(field(item, "link")) || item.match(/<link\b[^>]*href=["']([^"']+)["']/i)?.[1];
    try { url = new URL(link); } catch { continue; }
    if (url.protocol !== "https:" || !(url.hostname === root || url.hostname.endsWith(`.${root}`)) ||
        url.pathname === "/") continue;
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    const date = new Date(plainText(field(item, "pubDate") || field(item, "dc:date") || field(item, "published") || field(item, "updated")));
    if (!Number.isFinite(date.getTime())) throw new Error(`${label}-article-date-missing`);
    links.push({url: url.href, title: plainText(field(item, "title")).slice(0, 240),
      description: plainText(field(item, "description")).slice(0, 700),
      discoveredPublishedAt: date.toISOString(), discoveredDate: viennaDate(date),
      dateEvidence: "media_feed_only", requiresDirectArticleReview: true});
  }
  if (!links.length) throw new Error(`empty-or-changed-${label}-feed`);
  return links;
}

export function extractORFFeedLinks(xml) {
  return extractMediaFeedLinks(xml, "https://rss.orf.at/news.xml", "orf");
}

export function extractMediaListingLinks(html, sourceURL, anchorLinks) {
  const host = new URL(sourceURL).hostname.replace(/^www\./, "");
  const articles = new Map();
  const add = (value) => {
    let url;
    try { url = new URL(value.url, sourceURL); } catch { return; }
    if (url.protocol !== "https:" || url.hostname.replace(/^www\./, "") !== host || url.pathname === "/") return;
    const date = value.datePublished ? new Date(value.datePublished) : null;
    articles.set(url.href, {url: url.href, title: plainText(value.headline).slice(0, 240),
      description: plainText(value.description ?? "").slice(0, 700),
      discoveredPublishedAt: date && Number.isFinite(date.getTime()) ? date.toISOString() : null,
      discoveredDate: date && Number.isFinite(date.getTime()) ? viennaDate(date) :
        url.pathname.match(/\/(\d{4})\/(\d{2})\/(\d{2})\//)?.slice(1).join("-") ?? null,
      dateEvidence: "media_listing_only", requiresDirectArticleReview: true});
  };
  const visit = (value) => {
    if (!value || typeof value !== "object") return;
    if (value.headline && value.url && ["NewsArticle", "Article"].includes(value["@type"])) add(value);
    for (const child of Object.values(value)) if (typeof child === "object") {
      if (Array.isArray(child)) child.forEach(visit); else visit(child);
    }
  };
  for (const script of html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { visit(JSON.parse(script[1])); } catch { /* A different script may contain the article index. */ }
  }
  const pathPattern = host === "bvz.at" ? /^\/Nachrichten\/.+-\d+\.html$/ :
    host === "vn.at" ? /^\/[^/]+\/\d{4}\/\d{2}\/\d{2}\/.+\.vn$/ :
    host === "vol.at" ? /^\/.+\/\d{6,}\/?$/ : null;
  if (pathPattern) for (const link of anchorLinks) {
    if (pathPattern.test(new URL(link.url).pathname) && link.title.trim().length > 15 && !articles.has(link.url)) {
      add({url: link.url, headline: link.title});
    }
  }
  if (!articles.size) throw new Error("media-listing-article-extraction-empty");
  return [...articles.values()];
}

export function selectCoreOfficialArticles(links, body, requestedURL, now) {
  const host = new URL(requestedURL).hostname;
  const patterns = {
    "presse.wien.gv.at": /^\/presse\/\d{4}\/\d{2}\/\d{2}\//,
    "www.tirol.gv.at": /^\/presse\/meldungen\/meldung\/.+/,
    "www.news.steiermark.at": /^\/cms\/beitrag\/\d+\//,
    "presse.vorarlberg.at": /^\/land\/public\/.+/,
    "www.land-oberoesterreich.gv.at": /^\/\d{6,}\.htm$/,
    "www.burgenland.at": /^\/service\/medienservice\/aktuelle-meldungen\/detail\/.+/,
    "www.verkehrsbetriebe-burgenland.at": /^\/news\/.+/,
    "www.ooevv.at": /^\/de\/info-service\/news\/detail\/.+/,
    "www.bundeskanzleramt.gv.at": /^\/bundeskanzleramt\/nachrichten-der-bundesregierung\/\d{4}\/.+\.html$/,
  };
  let selected = null;
  if (patterns[host]) selected = links.filter(({url}) => {
    const value = new URL(url);
    return value.hostname === host && patterns[host].test(value.pathname);
  });
  if (host === "www.ktn.gv.at") selected = links.filter(({url}) => {
    const value = new URL(url);
    return value.hostname === host && value.pathname === "/Service/News" && /^\d+$/.test(value.searchParams.get("nid") ?? "");
  });
  if (host === "www.noe.gv.at") selected = links.filter(({url, title}) => {
    const value = new URL(url); const leaf = value.pathname.split("/").at(-1);
    return value.hostname === host && /^\/noe\/[^/]+\.html$/.test(value.pathname) &&
      title.length > 20 && (leaf.includes("_") || leaf.length > 50);
  });
  if (host === "www.vor.at") selected = links.filter(({url}) => /^\/aktuelles\/news\/news\/[^/]+\/?$/.test(new URL(url).pathname));
  if (host === "www.land-oberoesterreich.gv.at") {
    const list = body.match(/<ol\b[^>]*class="ooeSearchResult"[^>]*>([\s\S]*?)<\/ol>/i)?.[1] ?? "";
    const paths = new Set([...list.matchAll(/href=["']([^"']+)["']/g)].map((m) => new URL(m[1], requestedURL).href));
    selected = selected.filter((x) => paths.has(x.url));
  }
  if (selected) {
    if (!selected.length) throw new Error("official-listing-article-extraction-empty");
    return selected.map((link) => ({...link,
      discoveredDate: calendarDateFromText(link.title), dateEvidence: "official_listing_only"}));
  }
  if (host === "www.bmf.gv.at") {
    const year = Number(viennaDate(now).slice(0, 4));
    return links.filter(({url}) => new RegExp(`/presse/pressemeldungen/(?:${year}|${year - 1})/[^/]+/[^/]+\\.html$`).test(new URL(url).pathname))
      .map((link) => ({...link, discoveredDate: calendarDateFromText(link.title), dateEvidence: "official_listing_only"}))
      .sort((a, b) => (b.discoveredDate ?? "").localeCompare(a.discoveredDate ?? "")).slice(0, 40);
  }
  if (host === "www.integrationsfonds.at") {
    return links.filter(({url}) => new URL(url).hostname === host && new URL(url).pathname.startsWith("/neuigkeit/"))
      .map((link) => ({...link, discoveredDate: calendarDateFromText(link.title), dateEvidence: "official_listing_only"}));
  }
  if (host === "www.ages.at") {
    const articles = [];
    for (const match of body.matchAll(/<section\b[^>]*class="product-item"[^>]*>([\s\S]*?)<\/section>/gi)) {
      const section = match[1];
      const path = section.match(/href=["']([^"']*\/produkt\/[^"']+)["']/i)?.[1];
      if (!path) continue;
      const url = new URL(path, requestedURL);
      if (url.hostname !== host) continue;
      articles.push({url: url.href, title: plainText(section.match(/<h2\b[^>]*>([\s\S]*?)<\/h2>/i)?.[1] ?? ""),
        discoveredDate: calendarDateFromText(section.match(/<time\b[^>]*>([\s\S]*?)<\/time>/i)?.[1] ?? ""),
        dateEvidence: "official_listing_only"});
    }
    return articles;
  }
  return links;
}
