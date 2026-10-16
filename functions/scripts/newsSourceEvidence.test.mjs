import test from "node:test";
import assert from "node:assert/strict";
import {extractMediaFeedLinks, extractMediaListingLinks, extractORFFeedLinks, selectCoreOfficialArticles, calendarDateFromText} from "./newsSourceEvidence.mjs";
import {extractSourceLinks, inspectNewsSource, requestURLForSource} from "./newsSharedScan.mjs";
import {articleBodyURL, readNewsArticle} from "./newsReadArticle.mjs";

test("RSS 2 and RDF provide article dates in Vienna without treating them as primary evidence", () => {
  const item = '<item><title><![CDATA[Neue Hilfe &amp; Beratung]]></title><link>https://wien.orf.at/stories/123/</link>' +
    '<description>Neue &quot;Beratung&quot;</description><pubDate>Thu, 15 Oct 2026 22:30:00 +0000</pubDate></item>';
  const [article] = extractORFFeedLinks(`<rss><channel>${item}</channel></rss>`);
  assert.equal(article.discoveredDate, "2026-10-16");
  assert.equal(article.title, "Neue Hilfe & Beratung");
  assert.equal(article.requiresDirectArticleReview, true);
  assert.equal(article.dateEvidence, "media_feed_only");
  const rdf = '<rdf:RDF><item rdf:about="https://orf.at/stories/123/"><title>National</title>' +
    '<link>https://orf.at/stories/123/</link><dc:date>2026-10-16T09:00:00+02:00</dc:date></item></rdf:RDF>';
  assert.equal(extractORFFeedLinks(rdf)[0].discoveredPublishedAt, "2026-10-16T07:00:00.000Z");
  assert.throws(() => extractORFFeedLinks('<html>Bot challenge</html>'), /invalid-orf-feed/);
  assert.throws(() => extractORFFeedLinks('<rss><channel></channel></rss>'), /empty-or-changed/);
  assert.throws(() => extractORFFeedLinks(`<rss>${item.replace(/<pubDate>.*?<\/pubDate>/, "")}</rss>`), /date-missing/);
});

test("regional newspaper feeds and JSON-LD provide dated articles, while image links do not erase headlines", () => {
  const rss = '<rss><channel><item><title>Neue Schule in Tirol</title><link>https://www.tt.com/artikel/123/neue-schule</link><pubDate>Fri, 16 Oct 2026 08:00:00 +0000</pubDate></item></channel></rss>';
  assert.equal(extractMediaFeedLinks(rss, "https://www.tt.com/rss/tirol.xml")[0].discoveredDate, "2026-10-16");
  const html = '<script type="application/ld+json">' + JSON.stringify({"@type":"ItemList", itemListElement:[{item:{"@type":"NewsArticle",headline:"Neues Gymnasium",url:"/neunkirchen/neues-gymnasium-a123456",datePublished:"2026-10-16T08:00:00Z"}}]}) + '</script>';
  assert.equal(extractMediaListingLinks(html, "https://www.noen.at/", [])[0].title, "Neues Gymnasium");
  const links = extractSourceLinks('<a href="/article"><img src="pic.jpg"></a><a href="/article">Eine wichtige neue Nachricht</a>', "https://example.at/");
  assert.equal(links.length, 1);assert.equal(links[0].title, "Eine wichtige neue Nachricht");
  assert.equal(requestURLForSource({url:"https://www.sn.at/salzburg/rss"}), "https://www.sn.at/salzburg/rss/");
});

test("legacy RSS encodings retain umlauts and broken article extraction is a source error", async () => {
  const body = '<?xml version="1.0" encoding="ISO-8859-1"?><rss><channel><item><title>Oberösterreich</title><link>https://www.nachrichten.at/article/1</link><pubDate>Fri, 16 Oct 2026 08:00:00 +0000</pubDate></item></channel></rss>';
  const row = await inspectNewsSource({url:"https://www.nachrichten.at/rss",sourceId:"test",editorialMode:"discovery"},
    async () => new Response(Buffer.from(body, "latin1")));
  assert.equal(row.error, null);assert.equal(row.links[0].title, "Oberösterreich");
  const failed = await inspectNewsSource({url:"https://www.tirol.gv.at/presse/meldungen",sourceId:"test"}, async () => new Response('<a href="/menu">Menu</a>'));
  assert.equal(failed.httpStatus, 200);assert.match(failed.error, /article-extraction-empty/);
});

test("core official listings omit navigation and archives, retaining date-only articles", () => {
  const links = [{url: "https://www.bmf.gv.at/menu.html", title: "Menu"},
    {url: "https://www.bmf.gv.at/presse/pressemeldungen/2026.html", title: "Archive"},
    {url: "https://www.bmf.gv.at/presse/pressemeldungen/2026/oktober-2026/hilfe.html", title: "16. Oktober 2026 Hilfe"}];
  const result = selectCoreOfficialArticles(links, "", "https://www.bmf.gv.at/presse/pressemeldungen.html", new Date("2026-10-16T06:00:00Z"));
  assert.equal(result.length, 1);
  assert.equal(result[0].discoveredDate, "2026-10-16");
  assert.equal(calendarDateFromText("31.02.2026"), null);
  const ages = '<section class="product-item"><h2>Produkt</h2><time>16.10.2026</time>' +
    '<a href="/mensch/produktwarnungen-produktrueckrufe/produkt/produkt">Details</a></section>';
  const [recall] = selectCoreOfficialArticles([], ages, "https://www.ages.at/mensch/produktwarnungen-produktrueckrufe", new Date());
  assert.equal(recall.title, "Produkt");
  assert.equal(recall.discoveredDate, "2026-10-16");
});

test("Kärnten direct article reader follows the official body loader and preserves the public URL", async () => {
  const url = "https://www.ktn.gv.at/Service/News?nid=40109";
  const calls = [];
  const article = await readNewsArticle(url, async (u) => {
    calls.push(u);
    return new Response(u.includes("dyncontent") ? '<h1>Neue Hilfe</h1><p>Offizieller Artikeltext</p><p>15.10.2026</p>' : '<h1>Neue Hilfe</h1><script>loadBody()</script>');
  });
  assert.deepEqual(calls, [url, "https://www.ktn.gv.at/Service/News/dyncontent?nid=40109"]);
  assert.equal(article.requestedArticleURL, url);
  assert.match(article.text, /Offizieller Artikeltext/);
  assert.deepEqual(article.dateCandidates, ["2026-10-15"]);
  assert.equal(articleBodyURL("https://www.ktn.gv.at/Service/News"), "https://www.ktn.gv.at/Service/News");
});

test("direct reader exposes declared paid access without claiming an accessible teaser is full text", async () => {
  const article = await readNewsArticle("https://www.tt.com/artikel/123/beispiel", async () =>
    new Response('<script type="application/ld+json">{"isAccessibleForFree":false}</script><article><h1>Beispiel</h1><p>Kurzer Vorspann</p></article>'));
  assert.equal(article.accessRestricted, true);
  assert.match(article.note, /false does not prove full text/);
});

test("NÖ press reader excludes long navigation before truncation and retains nested article body", async () => {
  const page = '<nav><h1>Über NÖKI</h1>' + 'Navigation '.repeat(3000) + '</nav>' +
    '<div class="col-xs-12 col-md-9 main-cont pressarticle"><div class="topbar"><div>16.10.2026</div></div>' +
    '<h1>Neue Doppelturnhalle</h1><p>27 mal 30 Meter, sechs Millionen Euro.</p><div><p>Bis zu 30 Turnstunden.</p></div></div><footer>Kontakt</footer>';
  const a = await readNewsArticle("https://www.noe.gv.at/noe/Turnhalle.html", async () => new Response(page));
  assert.equal(a.textTruncated, false);
  assert.equal(a.title, "Neue Doppelturnhalle");
  assert.doesNotMatch(a.text, /Navigation|Kontakt/);
  assert.match(a.text, /sechs Millionen Euro/);
  assert.match(a.text, /Bis zu 30 Turnstunden/);
  assert.deepEqual(a.dateCandidates, ["2026-10-16"]);
  await assert.rejects(readNewsArticle("https://www.noe.gv.at/noe/Turnhalle.html", async () =>
    new Response('<div class="main-cont pressarticle"><h1>Unvollständig</h1>')), /container is incomplete/);
});
