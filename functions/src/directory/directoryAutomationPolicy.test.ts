import {strict as assert} from "node:assert";
import {test} from "node:test";
import {
  payloadSHA256, validateAutomaticDirectoryChange, type DirectoryAutomationCandidate,
} from "./directoryAutomationPolicy";

const now = new Date("2026-10-17T12:00:00.000Z");
const original = {
  id: "residence", isHidden: false, groups: [{id: "status", isHidden: false}],
  topics: [{
    id: "temporary-protection", groupID: "status", isHidden: false,
    sections: [{
      id: "contact", isHidden: false, title: {ukrainian: "Контакт", german: "Kontakt"},
      body: {ukrainian: "Текст", german: "Text"},
      source: {name: "BFA", url: "https://www.bfa.gv.at/104/"}, phoneNumber: "+43 1 12345",
    }], regionalSections: {},
  }],
};
const before = JSON.stringify(original);

function candidate(changes: (next: typeof original) => void): DirectoryAutomationCandidate {
  const next = structuredClone(original);
  changes(next);
  return {
    categoryId: "residence", topicId: "temporary-protection", sectionId: "contact",
    expectedRevision: 2, previousPayloadSHA256: payloadSHA256(before),
    nextPayload: JSON.stringify(next), changeClass: "official-contact", field: "phoneNumber",
    newValue: "+43 1 99999",
    evidence: {
      url: "https://www.bfa.gv.at/kontakt/", authority: "Bundesamt für Fremdenwesen und Asyl",
      observedAt: "2026-10-17T11:00:00.000Z",
      excerpt: "Kontakt Bundesamt für Fremdenwesen und Asyl: +43 1 99999",
    },
  };
}

test("accepts one official contact change on the exact published revision", () => {
  const input = candidate((next) => { next.topics[0].sections[0].phoneNumber = "+43 1 99999"; });
  assert.deepEqual(validateAutomaticDirectoryChange(input, before, 2, now), {
    nextPayload: input.nextPayload, oldValue: "+43 1 12345", newValue: "+43 1 99999",
  });
});

test("rejects any sibling content change hidden in a whole-category replacement", () => {
  const input = candidate((next) => {
    next.topics[0].sections[0].phoneNumber = "+43 1 99999";
    next.topics[0].sections[0].body.german = "Anderer Text";
  });
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /more than one/);
});

test("rejects stale revision, stale hash, and unsupported official source", () => {
  const input = candidate((next) => { next.topics[0].sections[0].phoneNumber = "+43 1 99999"; });
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 3, now), /stale revision/);
  input.previousPayloadSHA256 = "0".repeat(64);
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /payload changed/);
  input.previousPayloadSHA256 = payloadSHA256(before);
  input.evidence.url = "https://bfa.gv.at.evil.example/kontakt/";
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /official HTTPS/);
});

test("rejects a claimed single change when the declared value differs from payload", () => {
  const input = candidate((next) => { next.topics[0].sections[0].phoneNumber = "+43 1 88888"; });
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /Declared value/);
});

test("requires the replacement link to be the directly checked official page", () => {
  const input = candidate((next) => {
    next.topics[0].sections[0].source.url = "https://www.bfa.gv.at/kontakt/";
  });
  input.field = "source.url";
  input.newValue = "https://www.bfa.gv.at/kontakt/";
  assert.equal(validateAutomaticDirectoryChange(input, before, 2, now).oldValue,
    "https://www.bfa.gv.at/104/");
  input.evidence.url = "https://www.bfa.gv.at/other/";
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /directly checked/);
});

test("holds a candidate whose official observation is old", () => {
  const input = candidate((next) => { next.topics[0].sections[0].phoneNumber = "+43 1 99999"; });
  input.evidence.observedAt = "2026-10-01T11:00:00.000Z";
  assert.throws(() => validateAutomaticDirectoryChange(input, before, 2, now), /seven-day/);
});
