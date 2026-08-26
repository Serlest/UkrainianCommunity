import {strict as assert} from "node:assert";
import {test} from "node:test";

import {
  parseLegalEvidenceAccountRequest,
  parseLegalEvidenceLimit,
  parseLegalEvidenceUserRequest,
} from "./legalEvidence";

test("legal evidence list uses a bounded owner-screen page", () => {
  assert.equal(parseLegalEvidenceLimit(undefined), 100);
  assert.equal(parseLegalEvidenceLimit({}), 100);
  assert.equal(parseLegalEvidenceLimit({limit: 1}), 1);
  assert.equal(parseLegalEvidenceLimit({limit: 200}), 200);
});

test("legal evidence list rejects malformed and unbounded limits", () => {
  assert.throws(() => parseLegalEvidenceLimit("100"));
  assert.throws(() => parseLegalEvidenceLimit({limit: 0}));
  assert.throws(() => parseLegalEvidenceLimit({limit: 201}));
  assert.throws(() => parseLegalEvidenceLimit({limit: 10.5}));
});

test("legal evidence account list supports browsing, search, and a stable cursor", () => {
  assert.deepEqual(parseLegalEvidenceAccountRequest(undefined), {
    query: null,
    limit: 50,
    cursor: null,
  });
  assert.deepEqual(parseLegalEvidenceAccountRequest({query: "  philipp  ", limit: 25}), {
    query: "philipp",
    limit: 25,
    cursor: null,
  });
  assert.deepEqual(parseLegalEvidenceAccountRequest({
    limit: 50,
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  }), {
    query: null,
    limit: 50,
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  });
});

test("legal evidence account requests reject ambiguous searches and invalid users", () => {
  assert.throws(() => parseLegalEvidenceAccountRequest({query: "x"}));
  assert.throws(() => parseLegalEvidenceAccountRequest({limit: 101}));
  assert.throws(() => parseLegalEvidenceAccountRequest({
    query: "user",
    cursor: {userId: "user-1", createdAt: "2026-08-25T10:00:00.000Z"},
  }));
  assert.equal(parseLegalEvidenceUserRequest({userId: " user-1 "}), "user-1");
  assert.throws(() => parseLegalEvidenceUserRequest({userId: "bad/id"}));
});
