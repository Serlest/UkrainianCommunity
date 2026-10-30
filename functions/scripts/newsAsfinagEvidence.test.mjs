import test from "node:test";
import assert from "node:assert/strict";
import {inspectAsfinagData, inspectAsfinagNotice, readAsfinagEvidence, viennaInstant, ASFINAG_CONFIG, dataURL} from "./newsAsfinagEvidence.mjs";

const now = new Date("2026-10-30T13:00:00Z"); // 14:00 Vienna; do not use host TZ.
function feature(properties = {}) {
  return {type: "Feature", geometry: {type: "Point", coordinates: [16, 48]}, properties: {
    messageID: "one", situationID: "s1", source: "ASFINAG", messageType: "Accident",
    name_de: "A1", description_de: "Alle Fahrstreifen gesperrt, Umleitung über B1.",
    validityFrom: "2026-10-30T13:30:00", validityTo: "2026-10-30T15:00:00",
    publicationPeriodFrom: "2026-10-30T13:35:00", publicationPeriodTo: "2026-10-30T15:00:00",
    ...properties}};
}
function collection(features = [feature()]) {
  return {type: "FeatureCollection", totalFeatures: features.length, numberMatched: features.length,
    numberReturned: features.length, timeStamp: now.toISOString(), features};
}

test("nationwide query has no viewport, zoom or category filters; configured official backend required", async () => {
  assert.equal(new URL(dataURL()).searchParams.has("bbox"), false);
  const urls = [];
  const result = await readAsfinagEvidence({clock: () => now, fetchImpl: async (url) => {
    urls.push(url);
    return {ok: true, text: async () => JSON.stringify(url === ASFINAG_CONFIG
      ? {formatVersion: "1.0", services: {vaoWFS: new URL(dataURL()).origin + new URL(dataURL()).pathname}}
      : collection())};
  }});
  assert.deepEqual(urls, [ASFINAG_CONFIG, dataURL()]);
  assert.equal(result.status, "complete");
  assert.equal(result.notices[0].active, true);
  assert.equal(result.notices[0].triage, "review_restriction");
});

test("HTTP200 HAMM error / HTML shell / missing counts cannot become a zero", () => {
  for (const data of [{err: "HAMM", svcResL: []}, {}, {type: "FeatureCollection", features: []}]) {
    assert.throws(() => inspectAsfinagData(data, now), /schema\/count/);
  }
});

test("silent cap, missing row and duplicate IDs fail completeness", () => {
  assert.throws(() => inspectAsfinagData({...collection(), numberMatched: 2000, totalFeatures: 2000}, now), /truncated/);
  assert.throws(() => inspectAsfinagData(collection([feature(), feature()]), now), /duplicated/);
});

test("stale response and an unapproved redirected configuration fail", async () => {
  assert.throws(() => inspectAsfinagData({...collection(), timeStamp: "2026-10-30T12:00:00Z"}, now), /stale/);
  await assert.rejects(readAsfinagEvidence({fetchImpl: async () => ({ok: true,
    text: async () => JSON.stringify({formatVersion: "1.0", services: {vaoWFS: "https://example.org/wfs"}})})}), /configuration changed/);
});

test("future and expired notices are not active; end is exclusive", () => {
  const result = inspectAsfinagData(collection([
    feature({messageID: "future", validityFrom: "2026-10-30T14:01:00"}),
    feature({messageID: "ended", validityTo: "2026-10-30T14:00:00"}),
  ]), now);
  assert.deepEqual(result.notices.map((row) => row.active), [false, false]);
});

test("construction classification uses actual cause; incident in construction area remains for review", () => {
  const result = inspectAsfinagData(collection([
    feature({messageID: "planned", description_de: "Tunnel aufgrund von Instandhaltungsarbeiten gesperrt"}),
    feature({messageID: "acute", description_de: "Im Baustellenbereich Unfall, alle Fahrstreifen gesperrt"}),
    feature({messageID: "jam", messageType: "AbnormalTraffic", description_de: "3 km Stau"}),
    feature({messageID: "works_hazard", messageType: "Roadworks", description_de: "Generalsanierung; Unfall, alle Fahrstreifen gesperrt"}),
  ]), now);
  assert.deepEqual(result.notices.map((row) => row.triage), ["planned_works", "review_restriction", "review_routine_traffic", "review_restriction"]);
  assert.deepEqual(result.reviewMessageIds, ["acute", "jam", "works_hazard"]);
});

test("unknown category or invalid time is partial and remains visible, not rejected", () => {
  const result = inspectAsfinagData(collection([
    feature({messageID: "unknown", messageType: "NewHazard"}),
    feature({messageID: "badtime", validityFrom: null}),
  ]), now);
  assert.equal(result.status, "partial");
  assert.deepEqual(result.reviewMessageIds, ["unknown", "badtime"]);
  assert.equal(result.notices[1].active, null);
});

test("title-only construction may be excluded but is never described as full primary evidence", () => {
  const result = inspectAsfinagData(collection([feature({description_de: null,
    name_de: "Rampensperre aufgrund von Instandhaltungsarbeiten"})]), now);
  assert.equal(result.status, "complete");
  assert.equal(result.notices[0].triage, "planned_works");
  assert.equal(result.notices[0].text, null);
  assert.equal(result.notices[0].textEvidence, "title_only_not_publication_evidence");
  const missing = inspectAsfinagData(collection([feature({description_de: null})]), now);
  assert.equal(missing.status, "partial");
});

test("Vienna UTC offsets and DST ambiguity are explicit", () => {
  assert.equal(new Date(viennaInstant("2026-10-30T14:00:00")).toISOString(), "2026-10-30T13:00:00.000Z");
  assert.equal(new Date(viennaInstant("2026-07-30T14:00:00")).toISOString(), "2026-07-30T12:00:00.000Z");
  assert.throws(() => viennaInstant("2026-10-25T02:30:00"), /Ambiguous/);
  assert.throws(() => viennaInstant("2026-03-29T02:30:00"), /invalid/);
});

test("large complete response is fully read, without a fixed site/incident cap", () => {
  const result = inspectAsfinagData(collection(Array.from({length: 1301}, (_, i) => feature({messageID: String(i)}))), now);
  assert.equal(result.totalRead, 1301);
  assert.equal(result.reviewMessageIds.length, 1301);
  assert.equal(result.notices[0].sourceURL, dataURL());
});

test("detail recheck requires service success, exact ID, full text and current validity", () => {
  const remL = Object.entries({MESSAGE_ID: "one", DESCRIPTION: "Tunnel gesperrt", PROVIDER_NAME: "ASFINAG",
    PUBLICATION_FROM: "2026-10-30T13:35:00", PUBLICATION_TO: "2026-10-30T15:00:00"})
    .map(([code, txtN]) => ({code, txtN}));
  const data = {err: "OK", svcResL: [{err: "OK", meth: "GeoFeatureDetails", res: {
    common: {remL}, geoFeature: {id: "vao-wfs:b25l", title: "Tunnel", msgL: remL.map((_, remX) => ({remX})),
      validityList: [{startDate: "20261030", startTime: "133000", endDate: "20261030", endTime: "150000"}]}}}]};
  assert.equal(inspectAsfinagNotice(data, "one", now).active, true);
  assert.equal(inspectAsfinagNotice(data, "one", new Date("2026-10-30T14:00:00Z")).active, false);
  assert.throws(() => inspectAsfinagNotice(data, "wrong", now), /mismatch/);
  assert.throws(() => inspectAsfinagNotice({err: "HAMM", svcResL: []}, "one", now), /service error/);
  const missing = structuredClone(data); missing.svcResL[0].res.common.remL[1].txtN = "";
  assert.throws(() => inspectAsfinagNotice(missing, "one", now), /mismatch/);
});
