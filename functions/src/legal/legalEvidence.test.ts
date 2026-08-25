import {strict as assert} from "node:assert";
import {test} from "node:test";

import {parseLegalEvidenceLimit} from "./legalEvidence";

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
