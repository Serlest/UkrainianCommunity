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

export function extractORFFeedLinks(xml) {
  if (!/<(?:rss|rdf:RDF)\b/i.test(xml)) throw new Error("invalid-orf-feed");
  const links = [];
  const seen = new Set();
  const field = (item, tag) => item.match(new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, "i"))?.[1] ?? "";
  for (const match of xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)) {
    const item = match[1];
    let url;
    try { url = new URL(plainText(field(item, "link"))); } catch { continue; }
    if (url.protocol !== "https:" || !(url.hostname === "orf.at" || url.hostname.endsWith(".orf.at")) ||
        !/^\/stories\/\d+\/?$/.test(url.pathname)) continue;
    if (seen.has(url.href)) continue;
    seen.add(url.href);
    const date = new Date(plainText(field(item, "pubDate") || field(item, "dc:date")));
    if (!Number.isFinite(date.getTime())) throw new Error("orf-article-date-missing");
    links.push({url: url.href, title: plainText(field(item, "title")).slice(0, 240),
      description: plainText(field(item, "description")).slice(0, 700),
      discoveredPublishedAt: date.toISOString(), discoveredDate: viennaDate(date),
      dateEvidence: "media_feed_only", requiresOfficialPrimary: true});
  }
  if (!links.length) throw new Error("empty-or-changed-orf-feed");
  return links;
}

export function selectCoreOfficialArticles(links, body, requestedURL, now) {
  const host = new URL(requestedURL).hostname;
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
