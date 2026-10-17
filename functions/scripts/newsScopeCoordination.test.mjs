import assert from "node:assert/strict";
import {mkdtemp, readFile, readdir, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";

import {
  buildScopeDiscoveryBatch,
  buildNewsScopeLayout,
  applyNewsEditorialSources,
  planUniqueSourceFetches,
  prepareNewsScopeLayout,
  routeNewsCandidate,
  mergeTodayDiscovery,
} from "./newsScopeCoordination.mjs";
import {extractAMSNewsLinks, extractOEBBLiveLinks, extractOEBBTrafficLinks, extractSalzburgTrafficLinks, extractSourceLinks, requestURLForSource, runNewsSharedScan, scanNewsSources} from "./newsSharedScan.mjs";

const fixture = {
  sourceProgress: {
    ministry: {url: "https://example.gov/news?utm_source=test", type: "official", scopes: ["austria", "wien"]},
    ministryDuplicate: {url: "https://example.gov/news", type: "official", scopes: ["tirol"]},
    city: {url: "https://city.gv.at/news", type: "official", scopes: ["wien"]},
    stale: {url: "https://legacy.gv.at/archive", type: "official", scopes: []},
  },
  candidateLedger: {"url:https://old.example/story": {status: "pending"}},
};

test("shared sources are fetched once while scope state and candidates remain separate", () => {
  const layout = buildNewsScopeLayout(fixture, "2026-10-12T00:00:00Z");
  assert.equal(layout.manifest.scopeCount, 10);
  assert.equal(layout.manifest.sourceCount, 3);
  assert.equal(layout.manifest.activeSourceCount, 2);
  assert.equal(layout.manifest.legacyPendingImported, 0);
  assert.deepEqual(Object.keys(layout.scopeStates), [
    "wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol",
    "vorarlberg", "steiermark", "kaernten", "burgenland", "austria",
  ]);
  assert.deepEqual(layout.scopeStates.wien.candidateDecisions, {});
  assert.deepEqual(layout.scopeStates.wien.sourceProgress.ministry, {
    processedThrough: null, nextPage: null, lastReviewedAt: null,
  });
  const fetches = planUniqueSourceFetches(layout.registry, ["wien", "tirol", "austria"]);
  assert.equal(fetches.length, 2);
  assert.deepEqual(fetches.find((entry) => entry.sourceId === "ministry").recipients.sort(),
    ["austria", "tirol", "wien"]);
});

test("a source gains active status when a later duplicate assigns a territory", () => {
  const {registry} = buildNewsScopeLayout({sourceProgress: {
    archived: {url: "https://example.gov/news", type: "official", scopes: []},
    assigned: {url: "https://example.gov/news?utm_source=alert", type: "official", scopes: ["wien"]},
  }});
  assert.equal(registry.sources.length, 1);
  assert.equal(registry.sources[0].active, true);
  assert.equal(planUniqueSourceFetches(registry, ["wien"]).length, 1);
});

test("candidate territory must be explicit and cannot be copied to multiple lands", () => {
  assert.equal(routeNewsCandidate({regionScope: "austria"}), "austria");
  assert.equal(routeNewsCandidate({regionScope: "federalState", federalState: "kaernten"}), "kaernten");
  assert.throws(() => routeNewsCandidate({regionScope: "multiFederalState", federalState: "wien"}));
  assert.throws(() => routeNewsCandidate({regionScope: "austria", federalState: "wien"}));
});

test("one shared observation is visible to assigned scopes without duplicate fetching", () => {
  const {registry} = buildNewsScopeLayout(fixture);
  const observations = [
    {sourceId: "ministry", links: [{url: "https://example.gov/item"}]},
    {sourceId: "city", links: []},
  ];
  const wien = buildScopeDiscoveryBatch(registry, observations, "wien");
  const tirol = buildScopeDiscoveryBatch(registry, observations, "tirol");
  assert.equal(wien.results.length, 2);
  assert.deepEqual(tirol.results.map((row) => row.sourceId), ["ministry"]);
  assert.equal(tirol.missingSourceIds.length, 0);
  assert.throws(() => buildScopeDiscoveryBatch(registry, [...observations, observations[0]], "wien"));
});

test("preparation is read-only by default and writes a new layout without modifying legacy", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uac-news-scope-"));
  try {
    const input = join(directory, "legacy.json");
    const output = join(directory, "news-v3");
    const original = JSON.stringify(fixture);
    await writeFile(input, original);
    await prepareNewsScopeLayout(input, output);
    assert.deepEqual(await readdir(directory), ["legacy.json"]);
    await prepareNewsScopeLayout(input, output, {write: true});
    assert.equal((await readdir(join(output, "scopes"))).length, 10);
    assert.equal((await readFile(input, "utf8")), original);
    await assert.rejects(() => prepareNewsScopeLayout(input, output, {write: true}));
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("shared scan fetches a multi-scope source once and preserves immutable snapshots", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uac-news-scan-"));
  try {
    const input = join(directory, "legacy.json");
    const output = join(directory, "news-v3");
    await writeFile(input, JSON.stringify(fixture));
    await prepareNewsScopeLayout(input, output, {write: true});
    const requested = [];
    const fetchImpl = async (url) => {
      requested.push(url);
      return new Response('<a href="/story">Story</a>', {status: 200, headers: {"content-type": "text/html"}});
    };
    const first = await runNewsSharedScan(output, "news-2026-10-12T11", {
      fetchImpl, now: new Date("2026-10-12T09:00:00Z"),
    });
    assert.equal(first.sources, 2);
    assert.equal(requested.length, 2);
    const snapshot = JSON.parse(await readFile(first.snapshotPath, "utf8"));
    assert.equal(snapshot.length, 2);
    assert.equal(snapshot.find((row) => row.sourceId === "ministry").links[0].url,
      "https://example.gov/story");
    await assert.rejects(() => runNewsSharedScan(output, "news-2026-10-12T11", {fetchImpl}),
      /already exists/);
    assert.equal(requested.length, 2);
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("shared scan rejects missing source state before fetching or creating a snapshot", async () => {
  const directory = await mkdtemp(join(tmpdir(), "uac-news-scan-state-"));
  try {
    const input = join(directory, "legacy.json");
    const output = join(directory, "news-v3");
    await writeFile(input, JSON.stringify(fixture));
    await prepareNewsScopeLayout(input, output, {write: true});
    const statePath = join(output, "shared-source-state.json");
    const state = JSON.parse(await readFile(statePath, "utf8"));
    delete state.sources.ministry;
    await writeFile(statePath, JSON.stringify(state));
    let fetched = false;
    await assert.rejects(() => runNewsSharedScan(output, "news-2026-10-12T22", {
      fetchImpl: async () => { fetched = true; throw new Error("should-not-fetch"); },
    }), /Missing shared source state: ministry/);
    assert.equal(fetched, false);
    await assert.rejects(() => readFile(join(output, "snapshots", "news-2026-10-12T22.json")));
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
});

test("dated RIS source requests use the current window while identity stays stable", () => {
  const url = requestURLForSource({url: "https://www.ris.bka.gv.at/Ergebnis.wxe?Abfrage=BgblAuth&VonDatum=30.08.2026&BisDatum=03.09.2026"},
    new Date("2026-10-12T11:00:00Z"));
  assert.match(url, /VonDatum=11\.10\.2026/);
  assert.match(url, /BisDatum=12\.10\.2026/);
});

test("AMS escaped index yields recent direct articles instead of old embedded records", () => {
  const html = [
    '&#34;path&#34;: &#34;/regionen/wien/news/2024/10/old&#34;, &#34;header&#34;: &#34;Old&#34;',
    '&#34;path&#34;: &#34;/regionen/wien/news/2026/10/new&#34;, &#34;header&#34;: &#34;New&#34;',
  ].join("\n");
  assert.deepEqual(extractAMSNewsLinks(html, "https://www.ams.at/", new Date("2026-10-12T12:00:00Z")), [
    {url: "https://www.ams.at/regionen/wien/news/2026/10/new", title: "New"},
  ]);
});

test("Salzburg traffic scan reads the public feed and keeps only official article links", () => {
  assert.equal(requestURLForSource({url: "https://salzburg-verkehr.at/aktuelles/verkehr"}),
    "https://salzburg-verkehr.at/wp-json/mccom/v1/traffic/de");
  assert.deepEqual(extractSalzburgTrafficLinks(JSON.stringify([
    {title: "Linie 36 – Haltestellenänderung", link: "https://salzburg-verkehr.at/linie-36-haltestellenaenderung/"},
    {title: "Duplicate", link: "https://salzburg-verkehr.at/linie-36-haltestellenaenderung/#details"},
    {title: "External", link: "https://example.com/story"},
  ])), [
    {url: "https://salzburg-verkehr.at/linie-36-haltestellenaenderung/", title: "Linie 36 – Haltestellenänderung"},
  ]);
  assert.throws(() => extractSalzburgTrafficLinks("{}"), /invalid-salzburg-traffic-feed/);
});

test("ÖBB traffic listing exposes a clean direct article and fails on a changed layout", () => {
  const html = '<a href="/menu">Menu</a><div class="isotope-item 2026 Oct" data-id="250046">' +
    '<a href="news-zugverkehr?id=250046&amp;menueid=27022&amp;l=deutsch" aria-label="Details">' +
    '<!-- old navigation --><div><h3>ÖBB Verkehrsmeldung: Zugverkehr wieder aufgenommen</h3></div></a></div>';
  assert.deepEqual(extractOEBBTrafficLinks(html, "https://presse-oebb.com/News.aspx"), [
    {url: "https://presse-oebb.com/news-zugverkehr?id=250046&menueid=27022&l=deutsch",
      title: "ÖBB Verkehrsmeldung: Zugverkehr wieder aufgenommen"},
  ]);
  assert.throws(() => extractOEBBTrafficLinks('<a href="/menu">Menu</a>',
    "https://presse-oebb.com/News.aspx"), /invalid-oebb-traffic-listing/);
});

test("ÖBB live service listing excludes sharing links and fails when notices vanish", () => {
  const html = '<a href="/de/verkehrsmeldungen~st%C3%B6rfall_wienerneustadt~">Wiener Neustadt</a>' +
    '<a href="https://www.facebook.com/share?u=https://www.unsereoebb.at/de/verkehrsmeldungen~foo~">Share</a>';
  assert.deepEqual(extractOEBBLiveLinks(html, "https://www.unsereoebb.at/de/verkehrsmeldungen"), [
    {url: "https://www.unsereoebb.at/de/verkehrsmeldungen~st%C3%B6rfall_wienerneustadt~",
      title: "Wiener Neustadt"},
  ]);
  assert.throws(() => extractOEBBLiveLinks('<a href="/de">Menu</a>',
    "https://www.unsereoebb.at/de/verkehrsmeldungen"), /invalid-oebb-live-listing/);
});

test("a source article after a long navigation menu is retained", () => {
  const navigation = Array.from({length: 300}, (_, i) => `<a href="/menu/${i}">Menu</a>`).join("");
  const links = extractSourceLinks(`${navigation}<a href="/presse/meldung/heute">Aktuelle Meldung</a>`,
    "https://example.gv.at/");
  assert.equal(links.at(-1).url, "https://example.gv.at/presse/meldung/heute");
});

test("regional discovery restores usable official listings and adds newspapers without a site-count cap", () => {
  const oldAMS = "https://www.ams.at/regionen/wien/news.html";
  const {registry} = buildNewsScopeLayout({sourceProgress: {
    oldAMS: {url: oldAMS, type: "official", scopes: ["wien"]},
  }});
  const curated = applyNewsEditorialSources(registry);
  assert.equal(curated.sources.find((source) => source.url === oldAMS).active, false);
  const plan = planUniqueSourceFetches(curated);
  assert.equal(plan.some((source) => source.url === oldAMS), false);
  assert.deepEqual(plan.find((source) => source.url ===
    "https://www.unsereoebb.at/de/verkehrsmeldungen").recipients,
    ["wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol",
      "vorarlberg", "steiermark", "kaernten", "burgenland", "austria"]);
  assert.equal(plan.length, 55);
  assert.equal(plan.some((source) => source.url === "https://www.noe.gv.at/noe/Uebersicht.html"), true);
  assert.equal(curated.sources.find((source) => source.url === "https://www.noe.gv.at/noe/Uebersicht.html").editorialMode, "scan");
  assert.deepEqual(plan.find((source) => source.url === "https://rss.orf.at/noe.xml").recipients, ["niederoesterreich", "austria"]);
  assert.equal(plan.find((source) => source.url === "https://rss.orf.at/noe.xml").type, "media");
  assert.equal(plan.find((source) => source.url === "https://www.tt.com/rss/tirol.xml").primaryPolicy, "editorial");
  assert.equal(plan.find((source) => source.url === "https://www.meinbezirk.at/tirol/rss").primaryPolicy, "lead_only");
  assert.equal(plan.some((source) => source.url === "https://www.vmobil.at/de"), false);
});

test("today's union preserves a rolled-off lead and does not mask a current source error", () => {
  const sourceId = "https://rss.orf.at/tirol.xml";
  const previous = [{sourceId, checkedAt: "2026-10-15T22:15:00Z", links: [{url: "https://tirol.orf.at/stories/1/", title: "First"}]},
    {sourceId, checkedAt: "2026-10-15T20:15:00Z", links: [{url: "https://tirol.orf.at/stories/2/", title: "Yesterday"}]}];
  const current = [{sourceId, checkedAt: "2026-10-16T07:00:00Z", error: "fetch failed", links: []}];
  const [row] = mergeTodayDiscovery(current, [previous], "2026-10-16");
  assert.equal(row.error, "fetch failed");
  assert.deepEqual(row.links.map((x) => x.title), ["First"]);
  assert.equal(row.links[0].lastSeenAt, "2026-10-15T22:15:00Z");
});

test('national discovery sees approved regional media and dedicated national feeds without refetching sources',()=>{
 const registry=applyNewsEditorialSources(buildNewsScopeLayout(fixture).registry);
 const plan=planUniqueSourceFetches(registry);assert.equal(plan.length,55);
 const batch=buildScopeDiscoveryBatch(registry,plan.map(x=>({sourceId:x.sourceId,links:[]})),'austria');
 assert.equal(batch.expectedSources,31);
 assert.ok(batch.results.some(x=>x.sourceId==='https://www.noen.at/'));
 assert.ok(batch.results.some(x=>x.sourceId==='https://kurier.at/wirtschaft/xml/rss'));
 assert.ok(!batch.results.some(x=>x.sourceId.includes('meinbezirk')));
 assert.ok(registry.sources.find(x=>x.url==='https://www.statistik.at/medien/pressemitteilungen').editorialMode==='adapter');
});
