#!/usr/bin/env node
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {viennaDate} from "./newsSourceEvidence.mjs";

// Service address/name embedded in the official current-earthquakes map.
export const EARTHQUAKE_PAGE = "https://www.geosphere.at/de/karten/aktuelle-erdbeben";
export const EARTHQUAKE_API = "https://www.geosphere.at/data/earthquakes";

export function inspectEarthquakeData(rows, now = new Date()) {
  if (!Array.isArray(rows) || rows.length === 0) throw new Error("Earthquake event list empty or schema changed; not a verified zero.");
  const seen = new Set();
  const events = rows.map((row) => {
    if (!row || !Number.isSafeInteger(row.event_id) || seen.has(row.event_id) ||
        typeof row.region !== "string" || !row.region || !Number.isInteger(row.location_id) ||
        typeof row.datetime_utc !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?$/.test(row.datetime_utc) ||
        !Array.isArray(row.reference_magnitude) || !Number.isFinite(row.reference_magnitude[0]) ||
        typeof row.press_text !== "string") {
      throw new Error("Earthquake event schema invalid; coverage partial.");
    }
    const time = new Date(row.datetime_utc.replace(/Z?$/, "Z"));
    if (!Number.isFinite(time.getTime()) || time.getTime() > now.getTime() + 5 * 60_000) {
      throw new Error("Earthquake UTC time invalid or in the future.");
    }
    seen.add(row.event_id);
    return {eventId: row.event_id, occurredAtUTC: time.toISOString(),
      occurredDateVienna: viennaDate(time), region: row.region, locationId: row.location_id,
      magnitude: row.reference_magnitude[0], magnitudeType: row.reference_magnitude[1] ?? null,
      eventType: row.event_type ?? null, author: row.author ?? null,
      officialPressText: row.press_text};
  });
  return {checkedAt: now.toISOString(), sourceURL: EARTHQUAKE_PAGE, dataURL: EARTHQUAKE_API,
    totalEvents: events.length,
    todayAustriaEvents: events.filter((event) => event.locationId === 1 &&
      event.occurredDateVienna === viennaDate(now)),
    note: "Event time is not automatically a publication/update date. Read officialPressText for consequences and the issuing notice date. A harmless tremor is not an actionable warning; no publication decision is made here."};
}

export async function readEarthquakeEvidence({fetchImpl = fetch, now = new Date()} = {}) {
  const response = await fetchImpl(EARTHQUAKE_API, {signal: AbortSignal.timeout(15_000)});
  if (!response.ok) throw new Error(`GeoSphere earthquake API HTTP ${response.status}; coverage partial.`);
  const text = await response.text();
  if (Buffer.byteLength(text) > 8_000_000) throw new Error("Earthquake data too large.");
  return inspectEarthquakeData(JSON.parse(text), now);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { console.log(JSON.stringify(await readEarthquakeEvidence(), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
