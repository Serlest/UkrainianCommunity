import assert from "node:assert/strict";
import test from "node:test";
import {inspectEarthquakeData, readEarthquakeEvidence} from "./newsEarthquakeEvidence.mjs";

const now = new Date("2026-10-16T10:00:00Z");
const row = {event_id: 53287085, datetime_utc: "2026-10-15T23:57:17.095050",
  region: "Hall / Tirol", location_id: 1, reference_magnitude: [2.3, "ml"],
  press_text: "Schäden an Gebäuden sind keine bekannt und bei dieser Stärke nicht zu erwarten."};

test("UTC event before midnight belongs to the current Vienna day; foreign events excluded", () => {
  const result = inspectEarthquakeData([row, {...row, event_id: 2, location_id: 3, region: "Kamtschatka"}], now);
  assert.equal(result.totalEvents, 2);
  assert.equal(result.todayAustriaEvents.length, 1);
  assert.equal(result.todayAustriaEvents[0].occurredDateVienna, "2026-10-16");
  assert.match(result.todayAustriaEvents[0].officialPressText, /keine bekannt/);
});

test("empty, duplicate, malformed and future data cannot be treated as a clean zero", async () => {
  for (const value of [[], {}, [row, row], [{...row, reference_magnitude: []}],
    [{...row, datetime_utc: "2026-10-17T00:00:00"}]]) {
    assert.throws(() => inspectEarthquakeData(value, now));
  }
  await assert.rejects(() => readEarthquakeEvidence({now, fetchImpl: async () =>
    new Response("unavailable", {status: 503})}), /coverage partial/);
  const result = await readEarthquakeEvidence({now, fetchImpl: async () => new Response(JSON.stringify([row]))});
  assert.equal(result.todayAustriaEvents[0].eventId, row.event_id);
});
