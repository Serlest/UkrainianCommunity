import {strict as assert} from "node:assert";
import {test} from "node:test";

import {parseDsaDecision, parseDsaNoticeInput} from "./dsaCases";

test("accepts a precise DSA notice with contact and good-faith declaration", () => {
  const notice = parseDsaNoticeInput({
    exactLocation: "https://example.invalid/content/123",
    contentDescription: "A public organization post",
    illegalExplanation: "The post publishes a private address without a lawful basis.",
    legalBasis: "GDPR and Austrian data-protection law",
    evidence: "Screenshot captured on 25 August 2026",
    category: "privacy",
    reporterName: "Test Reporter",
    reporterEmail: "Reporter@Example.com",
    contactException: false,
    goodFaithConfirmed: true,
    preferredLanguage: "de",
  });

  assert.equal(notice.reporterEmail, "reporter@example.com");
  assert.equal(notice.goodFaithConfirmed, true);
  assert.equal(notice.category, "privacy");
});

test("allows the contact exception only for child-safety notices", () => {
  assert.equal(parseDsaNoticeInput({
    exactLocation: "content-id-1",
    contentDescription: "Child-safety content",
    illegalExplanation: "A concrete and sufficiently detailed child-safety explanation.",
    category: "childSafety",
    contactException: true,
    goodFaithConfirmed: true,
    preferredLanguage: "uk",
  }).contactException, true);

  assert.throws(() => parseDsaNoticeInput({
    exactLocation: "content-id-1",
    contentDescription: "Other content",
    illegalExplanation: "A concrete and sufficiently detailed explanation.",
    category: "other",
    contactException: true,
    goodFaithConfirmed: true,
    preferredLanguage: "uk",
  }));
});

test("rejects notices without good faith or required reporter identity", () => {
  const base = {
    exactLocation: "content-id-1",
    contentDescription: "Reported content",
    illegalExplanation: "A concrete and sufficiently detailed explanation.",
    category: "fraud",
    contactException: false,
    preferredLanguage: "de",
  };
  assert.throws(() => parseDsaNoticeInput({...base, reporterName: "Reporter", reporterEmail: "reporter@example.com"}));
  assert.throws(() => parseDsaNoticeInput({...base, goodFaithConfirmed: true}));
});

test("requires a human, reasoned DSA decision with a legal or terms basis", () => {
  const decision = parseDsaDecision({
    reportId: "report-1",
    outcome: "noAction",
    factsAndCircumstances: "The reported statement is an opinion and the supplied evidence does not establish illegality.",
    legalBasis: "Article 10 ECHR context considered",
    territorialScope: "European Union",
    duration: "No restriction",
    redressInformation: "Internal appeal is available for six months.",
    humanReviewConfirmed: true,
  });
  assert.equal(decision.outcome, "noAction");
  assert.equal(decision.humanReviewConfirmed, true);

  assert.throws(() => parseDsaDecision({...decision, legalBasis: undefined, termsBasis: undefined}));
  assert.throws(() => parseDsaDecision({...decision, humanReviewConfirmed: false}));
});
