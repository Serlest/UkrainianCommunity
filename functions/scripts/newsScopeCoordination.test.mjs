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
} from "./newsScopeCoordination.mjs";
import {requestURLForSource, runNewsSharedScan, scanNewsSources} from "./newsSharedScan.mjs";

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

test("dated RIS source requests use the current window while identity stays stable", () => {
  const url = requestURLForSource({url: "https://www.ris.bka.gv.at/Ergebnis.wxe?Abfrage=BgblAuth&VonDatum=30.08.2026&BisDatum=03.09.2026"},
    new Date("2026-10-12T11:00:00Z"));
  assert.match(url, /VonDatum=11\.10\.2026/);
  assert.match(url, /BisDatum=12\.10\.2026/);
});

test("editorial policy replaces stale AMS regional feeds and shares official national sources", () => {
  const oldAMS = "https://www.ams.at/regionen/wien/news.html";
  const {registry} = buildNewsScopeLayout({sourceProgress: {
    oldAMS: {url: oldAMS, type: "official", scopes: ["wien"]},
  }});
  const curated = applyNewsEditorialSources(registry);
  assert.equal(curated.sources.find((source) => source.url === oldAMS).active, false);
  const plan = planUniqueSourceFetches(curated);
  assert.equal(plan.some((source) => source.url === oldAMS), false);
  assert.deepEqual(plan.find((source) => source.url ===
    "https://www.oebb.at/de/fahrplan/baustelleninformation").recipients,
    ["wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol",
      "vorarlberg", "steiermark", "kaernten", "burgenland", "austria"]);
  assert.equal(plan.some((source) => source.url === "https://www.noe.gv.at/noe/Uebersicht.html"), true);
  assert.equal(plan.some((source) => source.url === "https://www.vmobil.at/de"), false);
});
