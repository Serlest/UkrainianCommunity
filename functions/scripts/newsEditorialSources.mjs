// Editorial source policy for the prepared v3 news scopes. Listing a source is
// not evidence that a newly discovered article is current or publishable.
export const NEWS_EDITORIAL_RULES = Object.freeze({
  maxArticleAgeHours: 24,
  required: ["direct_original_url", "published_at", "practical_effect", "original_uk_text", "original_de_text", "generated_relevant_image"],
  include: ["public_services", "residence_and_integration", "work_and_benefits", "health_and_safety", "education", "public_transport", "regional_economy", "housing", "infrastructure", "community_changes", "major_disruptions", "verified_earthquakes"],
  exclude: ["party_opinions", "political_conflict", "crime_reports", "murders", "war_without_direct_austrian_service_impact", "promotions", "events", "undated_pages"],
  rejectedCandidateDisposition: "reject_without_publication_or_editorial_queue",
});

const states = ["wien", "niederoesterreich", "oberoesterreich", "salzburg", "tirol", "vorarlberg", "steiermark", "kaernten", "burgenland"];
const all = [...states, "austria"];
const vor = ["wien", "niederoesterreich", "burgenland"];

// scan: a dated official listing suitable for discovery; its linked article
// still needs date, territory and practical-value verification.
// adapter: official, useful, but its current listing/format needs a dedicated
// extractor or a human check before it can enter automated discovery.
// reference: official background only; never treat a static page as new news.
const officialSources = [
  {url: "https://www.ams.at/arbeitsmarktdaten-und-medien/medien/news", scopes: all, mode: "scan", topics: ["work", "benefits"]},
  {url: "https://www.oebb.at/de/fahrplan/baustelleninformation", scopes: all, mode: "scan", topics: ["rail_planned_works"]},
  {url: "https://presse.oebb.at/de/", scopes: all, mode: "adapter", topics: ["rail_service"]},
  {url: "https://presse-oebb.com/News.aspx?l=deutsch&menueid=27022", scopes: all, mode: "scan", topics: ["rail_service", "rail_disruptions"]},
  {url: "https://www.unsereoebb.at/de/verkehrsmeldungen", scopes: all, mode: "scan", topics: ["rail_disruptions"]},
  {url: "https://www.ages.at/mensch/produktwarnungen-produktrueckrufe", scopes: all, mode: "scan", topics: ["product_safety"]},
  {url: "https://www.geosphere.at/de/karten/aktuelle-erdbeben", scopes: all, mode: "adapter", topics: ["earthquakes"]},
  {url: "https://warnungen.at-alert.at/de", scopes: all, mode: "adapter", topics: ["civil_protection_alerts"]},
  {url: "https://routenplaner.asfinag.at/?activeTab=traffic-messages&language=de", scopes: all, mode: "adapter", topics: ["road_disruptions", "natural_hazards"]},
  {url: "https://www.geosphere.at/de/karten/wetterprognose", scopes: all, mode: "adapter", topics: ["severe_weather"]},
  {url: "https://lawinen.at/", scopes: ["niederoesterreich", "oberoesterreich", "salzburg", "tirol", "vorarlberg", "steiermark", "kaernten"], mode: "adapter", topics: ["avalanche_risk"]},
  {url: "https://www.ris.bka.gv.at/LgblAuth/", scopes: states, mode: "adapter", topics: ["effective_regional_law"]},
  {url: "https://www.vor.at/aktuelles/news/news", scopes: vor, mode: "scan", topics: ["regional_transport"]},
  {url: "https://www.vor.at/aktuelles/news/verkehrsmeldungen", scopes: vor, mode: "scan", topics: ["regional_transport_disruptions"]},

  {url: "https://www.bundeskanzleramt.gv.at/bundeskanzleramt/nachrichten-der-bundesregierung.html", scopes: ["austria"], mode: "scan", topics: ["public_services"]},
  {url: "https://www.bmf.gv.at/presse/pressemeldungen.html", scopes: ["austria"], mode: "scan", topics: ["taxes", "benefits"]},
  {url: "https://www.integrationsfonds.at/der-oeif/neuigkeiten/", scopes: ["austria"], mode: "scan", topics: ["integration"]},
  {url: "https://www.ris.bka.gv.at/Bgbl-Auth/", scopes: ["austria"], mode: "adapter", topics: ["effective_federal_law"]},
  {url: "https://www.bbu.gv.at/ukraine-info-faq-deutsch", scopes: ["austria"], mode: "reference", topics: ["ukraine_residence"]},
  {url: "https://www.oesterreich.gv.at/", scopes: ["austria"], mode: "reference", topics: ["public_services"]},

  {url: "https://presse.wien.gv.at/aktuell", scopes: ["wien"], mode: "scan", topics: ["city_services"]},
  {url: "https://www.wienerlinien.at/news", scopes: ["wien"], mode: "scan", topics: ["urban_transport"]},
  {url: "https://www.wienerlinien.at/betriebsinfo", scopes: ["wien"], mode: "adapter", topics: ["urban_transport_disruptions"]},

  {url: "https://www.noe.gv.at/noe/Uebersicht.html", scopes: ["niederoesterreich"], mode: "scan", topics: ["state_services"]},

  {url: "https://www.land-oberoesterreich.gv.at/presse.htm", scopes: ["oberoesterreich"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.ooevv.at/de/info-service/news.html", scopes: ["oberoesterreich"], mode: "scan", topics: ["regional_transport"]},

  {url: "https://www.salzburg.gv.at/kommunikation", scopes: ["salzburg"], mode: "scan", topics: ["state_services"]},
  {url: "https://salzburg-verkehr.at/aktuelles/verkehr/", scopes: ["salzburg"], mode: "scan", topics: ["regional_transport"]},

  {url: "https://www.tirol.gv.at/presse/meldungen/", scopes: ["tirol"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.vvt.at/ihre-fahrt/verkehrsmeldungen", scopes: ["tirol"], mode: "adapter", topics: ["regional_transport_disruptions"]},

  {url: "https://presse.vorarlberg.at/land/dist/vlk_aktuell.html", scopes: ["vorarlberg"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.vmobil.at/de", scopes: ["vorarlberg"], mode: "adapter", topics: ["regional_transport"]},

  {url: "https://www.news.steiermark.at/cms/ziel/154271055/DE/", scopes: ["steiermark"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.verbundlinie.at/de/verbindungen/fahrplandownloads/fahrplandownload", scopes: ["steiermark"], mode: "adapter", topics: ["regional_transport"]},

  {url: "https://www.ktn.gv.at/Service/News", scopes: ["kaernten"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.kaerntner-linien.at/news/", scopes: ["kaernten"], mode: "scan", topics: ["regional_transport"]},
  {url: "https://www.kaerntner-linien.at/info-service/stoermeldungen/", scopes: ["kaernten"], mode: "scan", topics: ["regional_transport_disruptions"]},

  {url: "https://www.burgenland.at/service/medienservice/aktuelle-meldungen/", scopes: ["burgenland"], mode: "scan", topics: ["state_services"]},
  {url: "https://www.verkehrsbetriebe-burgenland.at/ueber-uns/aktuelles", scopes: ["burgenland"], mode: "scan", topics: ["regional_transport"]},
];

// Regional coverage is driven by verified source usefulness, not a site-count cap.
const mediaFeeds = [
  ["news", "austria"], ["wien", "wien"], ["noe", "niederoesterreich"],
  ["ooe", "oberoesterreich"], ["salzburg", "salzburg"], ["tirol", "tirol"],
  ["vorarlberg", "vorarlberg"], ["steiermark", "steiermark"],
  ["kaernten", "kaernten"], ["burgenland", "burgenland"],
].map(([feed, scope]) => ({url: `https://rss.orf.at/${feed}.xml`, scopes: [scope],
  mode: "discovery", primaryPolicy: "editorial", publisherGroup: "orf", topics: ["public_interest_leads"]}));

// These authorities are visited only when a specific lead needs their primary
// article. Their home pages are never counted as current news or scanned feeds.
const targetedAuthorities = [
  ["https://www.bmi.gv.at/news.html", "austria"],
  ["https://www.bmb.gv.at/", "austria"],
  ["https://www.sozialministerium.gv.at/", "austria"],
  ["https://www.gesundheit.gv.at/news/aktuelles.html", "austria"],
  ["https://www.statistik.at/medien/pressemitteilungen", "austria"],
  ["https://www.parlament.gv.at/aktuelles/pk", "austria"],
  ["https://www.wko.at/", "austria"],
  ["https://www.bbu.gv.at/", "austria"],
  ["https://austria.mfa.gov.ua/", "austria"],
  ["https://www.linz.at/medienservice/", "oberoesterreich"],
  ["https://www.st-poelten.at/", "niederoesterreich"],
  ["https://www.stadt-salzburg.at/", "salzburg"],
  ["https://www.innsbruck.gv.at/", "tirol"],
  ["https://www.bregenz.gv.at/", "vorarlberg"],
  ["https://www.graz.at/", "steiermark"],
  ["https://www.klagenfurt.at/", "kaernten"],
  ["https://www.eisenstadt.gv.at/", "burgenland"],
  ...[["wien", "wien"], ["noe", "niederoesterreich"], ["ooe", "oberoesterreich"],
    ["sbg", "salzburg"], ["tirol", "tirol"], ["vbg", "vorarlberg"],
    ["stmk", "steiermark"], ["kaernten", "kaernten"], ["bgld", "burgenland"]]
    .map(([host, scope]) => [`https://${host}.arbeiterkammer.at/`, scope]),
].map(([url, scope]) => ({url, scopes: [scope], mode: "adapter", topics: ["targeted_primary_verification"]}));

const regionalMedia = [
  ["https://www.tt.com/rss/tirol.xml", "tirol", "tiroler_tageszeitung"],
  ["https://www.kleinezeitung.at/rss/steiermark", "steiermark", "styria"],
  ["https://www.kleinezeitung.at/rss/kaernten", "kaernten", "styria"],
  ["https://www.nachrichten.at/storage/rss/rss/oberoesterreich.xml", "oberoesterreich", "wimmer"],
  ["https://www.noen.at/", "niederoesterreich", "noe_pressehaus"],
  ["https://www.bvz.at/", "burgenland", "noe_pressehaus"],
  ["https://www.sn.at/salzburg/rss/", "salzburg", "salzburger_nachrichten"],
  ["https://www.vn.at/", "vorarlberg", "russmedia"],
  ["https://www.vol.at/", "vorarlberg", "russmedia"],
  ["https://kurier.at/chronik/wien/xml/rss", "wien", "kurier"],
  ["https://www.derstandard.at/rss", "austria", "derstandard"],
  ["https://kurier.at/politik/inland/xml/rss", "austria", "kurier"],
  ["https://kurier.at/wirtschaft/xml/rss", "austria", "kurier"],
].map(([url, scope, publisherGroup]) => ({url, scopes: [scope], mode: "discovery",
  primaryPolicy: "editorial", publisherGroup, topics: ["regional_public_interest"]}));
const localDiscovery = states.map((scope) => ({url: `https://www.meinbezirk.at/${scope}/rss`,
  scopes: [scope], mode: "discovery", primaryPolicy: "lead_only", publisherGroup: "regionalmedien",
  topics: ["local_leads"], note: "Community contributions require named-source verification; not an approved editorial primary."}));

export const NEWS_EDITORIAL_SOURCES = Object.freeze([
  ...officialSources.map((source) => source.url === "https://www.vor.at/aktuelles/news/verkehrsmeldungen" ||
      source.url === "https://www.salzburg.gv.at/kommunikation" ?
    {...source, mode: "adapter", note: source.url.includes("vor.at") ?
      "Verified operator-reference hub, not a dated live incident feed." :
      "Listing exposes navigation; official LKORR body search requires a working adapter. Targeted verification remains available."} : source),
  ...targetedAuthorities,
  // National stories can surface first in a regional edition. Fetch once and
  // let Österreich screen these leads; publication territory still needs proof.
  ...[...mediaFeeds, ...regionalMedia].map((source) => ({...source,
    scopes: [...new Set([...source.scopes, "austria"])]})),
  ...localDiscovery,
]);
export const NEWS_DISCOVERY_POLICY_VERSION = 4;

export function editorialPublisherForURL(value, scope) {
  const host = new URL(value).hostname.replace(/^www\./, "");
  return NEWS_EDITORIAL_SOURCES.find((source) => {
    // Feed assignment is a discovery optimization, not the article's territory
    // or the publisher's authority. The editorial gate checks territory itself.
    if (source.primaryPolicy !== "editorial") return false;
    const registered = new URL(source.url).hostname.replace(/^www\./, "").replace(/^rss\./, "");
    return host === registered || host.endsWith(`.${registered}`);
  }) ?? null;
}
