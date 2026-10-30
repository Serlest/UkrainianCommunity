#!/usr/bin/env node
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {writeFile} from "node:fs/promises";

export const ASFINAG_PAGE = "https://routenplaner.asfinag.at/?activeTab=traffic-messages&language=de";
export const ASFINAG_CONFIG = "https://routenplaner.asfinag.at/webapp/config/webapp.config.json";
const WFS = "https://geo.verkehrsauskunft.at/vao-rendermediator/api/wfs";
const TYPES = new Set(["Roadworks", "RoadOrCarriagewayOrLaneManagement", "ConditionalAccessRestriction",
  "AbnormalTraffic", "Conditions", "Obstruction", "Accident"]);
const fmt = new Intl.DateTimeFormat("sv-SE", {timeZone: "Europe/Vienna", year: "numeric", month: "2-digit",
  day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23"});

// This VAO service uses Austrian local wall time (unlike GeoSphere's UTC earthquake service).
// Enumerate possible offsets: fail visibly for ambiguous/nonexistent DST times, never guess.
export function viennaInstant(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value)) {
    throw new Error(`Invalid VAO local timestamp: ${value}`);
  }
  const wall = Date.parse(value + "Z");
  const matches = [60, 120].map((minutes) => wall - minutes * 60_000)
    .filter((time) => Number.isFinite(time) && fmt.format(new Date(time)).replace(" ", "T") === value);
  if (matches.length !== 1) throw new Error(`Ambiguous or invalid Europe/Vienna timestamp: ${value}`);
  return matches[0];
}

export function dataURL() {
  const url = new URL(WFS);
  // No viewport, zoom, FRC, category, date or country filter. Do not silently lose local roads,
  // non-car access restrictions or an unexpected new category. Count metadata proves exhaustion.
  url.search = new URLSearchParams({service: "WFS", version: "1.0.0", request: "GetFeature",
    typeName: "vao:traffic_message_unique", srsName: "EPSG:4326", outputformat: "JSON"});
  return url.href;
}

export function inspectAsfinagData(data, now = new Date()) {
  if (data?.type !== "FeatureCollection" || !Array.isArray(data.features) ||
      !Number.isSafeInteger(data.numberMatched) || !Number.isSafeInteger(data.numberReturned) ||
      !Number.isSafeInteger(data.totalFeatures) || data.numberMatched < 0 ||
      data.numberMatched !== data.totalFeatures || data.numberReturned !== data.features.length ||
      data.numberMatched !== data.features.length) {
    throw new Error("ASFINAG WFS schema/count mismatch or truncated response; coverage partial.");
  }
  const serverAt = Date.parse(data.timeStamp);
  if (!/Z$/.test(data.timeStamp ?? "") || !Number.isFinite(serverAt) ||
      now.getTime() - serverAt > 10 * 60_000 || serverAt - now.getTime() > 60_000) {
    throw new Error("ASFINAG WFS response timestamp stale/invalid; coverage partial.");
  }
  const seen = new Set();
  const coverageErrors = [];
  const notices = data.features.map((feature) => {
    const p = feature?.properties;
    if (!p || typeof p.messageID !== "string" || !p.messageID || seen.has(p.messageID) ||
        (p.description_de !== null && typeof p.description_de !== "string") ||
        !(p.description_de || p.name_de || "").trim() ||
        typeof p.messageType !== "string" || typeof p.source !== "string" || !p.source.trim()) {
      throw new Error("ASFINAG notice identity/text/provider missing or duplicated; coverage partial.");
    }
    seen.add(p.messageID);
    const row = {messageId: p.messageID, situationId: p.situationID, provider: p.source,
      messageType: p.messageType, title: p.name_de, text: p.description_de,
      textEvidence: p.description_de?.trim() ? "full_description" : "title_only_not_publication_evidence",
      validityFrom: p.validityFrom, validityTo: p.validityTo,
      publicationPeriodFrom: p.publicationPeriodFrom, publicationPeriodTo: p.publicationPeriodTo,
      sourceVersion: p.version, roadCode: p.asf_roadcode ?? null,
      vehicleType: p.vehicleType, car: p.modetype_car, truck: p.modetype_truckOver35t,
      geometry: feature.geometry, sourceURL: dataURL()};
    let times;
    try {
      times = [p.validityFrom, p.validityTo, p.publicationPeriodFrom, p.publicationPeriodTo].map(viennaInstant);
    } catch (error) {
      coverageErrors.push({messageId: p.messageID, error: error.message});
      return {...row, active: null, triage: "unverified_time"};
    }
    const [start, end, published, removed] = times;
    if (end < start || removed < published) {
      coverageErrors.push({messageId: p.messageID, error: "Reversed validity/publication interval"});
      return {...row, active: null, triage: "unverified_time"};
    }
    // End dates are feed validity bounds, not proof of physical reopening. Daily/weekly schedules
    // in the text may narrow this envelope: these rows always require actual editorial reading.
    const active = start <= now.getTime() && now.getTime() < end &&
      published <= now.getTime() && now.getTime() < removed;
    let triage = "outside_validity";
    if (active) {
      const text = [p.name_de, p.description_de].filter(Boolean).join("\n");
      const acute = /(?:Unfall|defekt|Panne|Falschfahrer|Lawin|Mure|Hochwasser|Überflut|Steinschlag|Sturm|Glätte|Teile auf der Fahrbahn|Gegenstände auf der Fahrbahn)/i.test(text);
      const planned = !acute && (p.messageType === "Roadworks" ||
        /(?:aufgrund von Instandhaltungsarbeiten|Grund(?: dafür)?:?\s*(?:Bauarbeiten|Instandsetzung)|Generalsanierung|Fahrbahnerneuerung|Belagsarbeiten)/i.test(text));
      // Unknown categories and every closure/condition/access restriction remain visible.
      // A routine queue or accident can still include a full closure: never discard by type alone.
      const major = /(?:gesperrt|Sperre|Sperrung|Umleitung|umgeleitet|nicht passierbar|Lawin|Mure|Hochwasser|Überflut|Steinschlag|Schnee|Glätte|Sturm|Sicht|Falschfahrer|Evaku|road closed|closed|flood|snow|avalanche)/i.test(text);
      triage = planned ? "planned_works" : major || !["AbnormalTraffic", "Accident"].includes(p.messageType)
        ? "review_restriction" : "review_routine_traffic";
      if (!TYPES.has(p.messageType)) coverageErrors.push({messageId: p.messageID, error: `Unknown type ${p.messageType}`});
      if (!planned && !p.description_de?.trim()) {
        coverageErrors.push({messageId: p.messageID, error: "Active non-construction notice has no full description"});
      }
    }
    return {...row, active, triage, publicationDateVienna: p.publicationPeriodFrom.slice(0, 10),
      dateCaution: "Publication-period start may be a feed republication; verify today's material change. Read text schedules and current status before live."};
  });
  const counts = {};
  for (const row of notices) counts[row.triage] = (counts[row.triage] ?? 0) + 1;
  return {schemaVersion: 1, checkedAt: now.toISOString(), status: coverageErrors.length ? "partial" : "complete",
    officialPageURL: ASFINAG_PAGE, sourceURL: dataURL(), configURL: ASFINAG_CONFIG,
    sourceTimestamp: data.timeStamp, timeZone: "Europe/Vienna", totalMatched: data.numberMatched,
    totalRead: notices.length, counts, coverageErrors, notices,
    reviewMessageIds: notices.filter((row) => row.triage.startsWith("review_") || row.active === null).map((row) => row.messageId),
    note: "Complete means all source rows read, not all restrictions are publishable. Read every review row (including routine traffic for hidden major effects); retain foreign/unknown territory for assessment, not automatic Austria-wide publication. No story queue or automatic publisher."};
}

async function readJSON(url, fetchImpl) {
  const response = await fetchImpl(url, {signal: AbortSignal.timeout(45_000)});
  if (!response.ok) throw new Error(`ASFINAG HTTP ${response.status}; coverage partial.`);
  const text = await response.text();
  if (Buffer.byteLength(text) > 40_000_000) throw new Error("ASFINAG response exceeds safety bound; coverage partial.");
  return JSON.parse(text);
}

export async function readAsfinagEvidence({fetchImpl = fetch, clock = () => new Date()} = {}) {
  // Follow the deployed external configuration, not the obsolete map-in fallback in bundled JS.
  const config = await readJSON(ASFINAG_CONFIG, fetchImpl);
  if (config.formatVersion !== "1.0" || config.services?.vaoWFS !== WFS) {
    throw new Error("ASFINAG official service configuration changed; inspect before using another endpoint.");
  }
  return inspectAsfinagData(await readJSON(dataURL(), fetchImpl), clock());
}

export function inspectAsfinagNotice(data, messageId, now = new Date()) {
  const result = data?.svcResL?.[0];
  const feature = result?.res?.geoFeature;
  const common = result?.res?.common;
  if (data?.err !== "OK" || result?.err !== "OK" || result?.meth !== "GeoFeatureDetails" ||
      !feature || !Array.isArray(feature.msgL) || !Array.isArray(common?.remL)) {
    throw new Error("ASFINAG detail service error or removed notice; not an active confirmation.");
  }
  const fields = {};
  for (const ref of feature.msgL) {
    const rem = common.remL[ref.remX];
    if (!rem || typeof rem.code !== "string" || typeof rem.txtN !== "string") throw new Error("Invalid ASFINAG notice reference");
    fields[rem.code] = rem.txtN;
  }
  if (fields.MESSAGE_ID !== messageId || !fields.DESCRIPTION?.trim() || !fields.PROVIDER_NAME?.trim()) {
    throw new Error("ASFINAG detail ID/text/provider mismatch; not publication evidence.");
  }
  const compactTime = (date, time) => {
    if (!/^\d{8}$/.test(date ?? "") || !/^\d{6}$/.test(time ?? "")) throw new Error("Invalid ASFINAG validity");
    return viennaInstant(`${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6)}T${time.slice(0, 2)}:${time.slice(2, 4)}:${time.slice(4)}`);
  };
  if (!feature.validityList?.length) throw new Error("ASFINAG detail validity missing");
  const intervals = feature.validityList.map((v) => [compactTime(v.startDate, v.startTime), compactTime(v.endDate, v.endTime)]);
  if (intervals.some(([start, end]) => end < start)) throw new Error("Reversed ASFINAG detail validity");
  const t = now.getTime();
  const active = intervals.some(([start, end]) => start <= t && t < end) &&
    viennaInstant(fields.PUBLICATION_FROM) <= t && t < viennaInstant(fields.PUBLICATION_TO);
  return {checkedAt: now.toISOString(), sourceURL: "https://routenplaner.asfinag.at/hamm/gate",
    officialPageURL: ASFINAG_PAGE, requestMethod: "POST", serviceMethod: "GeoFeatureDetails",
    featureId: feature.id, messageId, active, title: feature.title, text: fields.DESCRIPTION,
    provider: fields.PROVIDER_NAME, fields, validity: feature.validityList,
    note: "Actual official detail read; sourceURL is the endpoint read, not an invented incident page. Publication period alone is not proof of a material change today. Re-read immediately before live; expiry is not proof of reopening."};
}

export async function readAsfinagNotice(messageId, {fetchImpl = fetch, clock = () => new Date()} = {}) {
  if (typeof messageId !== "string" || !messageId || messageId.length > 2000) throw new Error("Invalid ASFINAG message ID");
  const config = await readJSON(ASFINAG_CONFIG, fetchImpl);
  const gate = new URL(config.vs_asfinag?.urlMgate ?? config.urlMgate, ASFINAG_PAGE).href;
  if (config.formatVersion !== "1.0" || gate !== "https://routenplaner.asfinag.at/hamm/gate" || !config.hciAuth?.aid) {
    throw new Error("ASFINAG detail configuration changed");
  }
  // Same public service/feature identifier used by the map's GeoFeatureDetails call.
  // Never store/send account credentials; aid is the public webapp configuration value.
  const request = {ver: "1.59", lang: "deu", auth: {type: "AID", aid: config.hciAuth.aid},
    client: {id: "VAO", type: "WEB", name: "webapp", l: "vs_asfinag"}, ext: "VAO.22",
    svcReqL: [{meth: "GeoFeatureDetails", req: {id: "vao-wfs:" + Buffer.from(messageId).toString("base64")}}]};
  const response = await fetchImpl(gate, {method: "POST", headers: {"Content-Type": "application/json"},
    body: JSON.stringify(request), signal: AbortSignal.timeout(45_000)});
  if (!response.ok) throw new Error(`ASFINAG detail HTTP ${response.status}`);
  return inspectAsfinagNotice(await response.json(), messageId, clock());
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const args = process.argv.slice(2);
    const detail = args[0] === "--notice";
    if ((!detail && args.length > 1) || (detail && (args.length < 2 || args.length > 3))) {
      throw new Error("Usage: node newsAsfinagEvidence.mjs [new-evidence.json] OR --notice messageId [new-evidence.json]");
    }
    const result = detail ? await readAsfinagNotice(args[1]) : await readAsfinagEvidence();
    const output = detail ? args[2] : args[0];
    if (output) {
      await writeFile(resolve(output), JSON.stringify(result, null, 2) + "\n", {flag: "wx"});
      console.log(JSON.stringify({path: resolve(output), status: result.status, totalRead: result.totalRead,
        counts: result.counts, reviewCount: result.reviewMessageIds?.length, coverageErrors: result.coverageErrors,
        ...(detail ? {messageId: result.messageId, active: result.active} : {})}));
    } else console.log(JSON.stringify(result, null, 2));
    if ((!detail && result.status !== "complete") || (detail && !result.active)) process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
