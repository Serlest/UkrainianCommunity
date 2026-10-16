import test from "node:test";
import assert from "node:assert/strict";
import {extractORFFeedLinks, selectCoreOfficialArticles, calendarDateFromText} from "./newsSourceEvidence.mjs";
import {articleBodyURL, readNewsArticle} from "./newsReadArticle.mjs";

test("RSS 2 and RDF provide article dates in Vienna without treating them as primary evidence", () => {
  const item = '<item><title><![CDATA[Neue Hilfe &amp; Beratung]]></title><link>https://wien.orf.at/stories/123/</link>' +
    '<description>Neue &quot;Beratung&quot;</description><pubDate>Thu, 15 Oct 2026 22:30:00 +0000</pubDate></item>';
  const [article] = extractORFFeedLinks(`<rss><channel>${item}</channel></rss>`);
  assert.equal(article.discoveredDate, "2026-10-16");
  assert.equal(article.title, "Neue Hilfe & Beratung");
  assert.equal(article.requiresOfficialPrimary, true);
  assert.equal(article.dateEvidence, "media_feed_only");
  const rdf = '<rdf:RDF><item rdf:about="https://orf.at/stories/123/"><title>National</title>' +
    '<link>https://orf.at/stories/123/</link><dc:date>2026-10-16T09:00:00+02:00</dc:date></item></rdf:RDF>';
  assert.equal(extractORFFeedLinks(rdf)[0].discoveredPublishedAt, "2026-10-16T07:00:00.000Z");
  assert.throws(() => extractORFFeedLinks('<html>Bot challenge</html>'), /invalid-orf-feed/);
  assert.throws(() => extractORFFeedLinks('<rss><channel></channel></rss>'), /empty-or-changed/);
  assert.throws(() => extractORFFeedLinks(`<rss>${item.replace(/<pubDate>.*?<\/pubDate>/, "")}</rss>`), /date-missing/);
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
