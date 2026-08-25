import { strict as assert } from "node:assert";
import { test } from "node:test";

import {
  contentReportDocumentId,
  parseContentReportRequest,
  reportSlaHours,
} from "./contentReports";

test("parses direct content reports and normalizes optional details", () => {
  const report = parseContentReportRequest({
    targetType: "news",
    targetId: "news-1",
    reason: "spam",
    illegalExplanation: "  repeated fraudulent promotion  ",
    goodFaithConfirmed: true,
  });

  assert.deepEqual(report, {
    targetType: "news",
    targetId: "news-1",
    parentType: undefined,
    parentId: undefined,
    reason: "spam",
    illegalExplanation: "repeated fraudulent promotion",
    legalBasis: undefined,
    evidence: undefined,
    goodFaithConfirmed: true,
  });
});

test("requires a complete and matching comment parent", () => {
  assert.throws(() => parseContentReportRequest({
    targetType: "comment",
    targetId: "comment-1",
    reason: "harassment",
    illegalExplanation: "A specific unlawful threat.",
    goodFaithConfirmed: true,
  }));
  assert.throws(() => parseContentReportRequest({
    targetType: "event",
    targetId: "event-1",
    parentType: "event",
    parentId: "event-1",
    reason: "spam",
    illegalExplanation: "A specific unlawful promotion.",
    goodFaithConfirmed: true,
  }));
});

test("rejects unsupported values, slash-containing ids, and oversized details", () => {
  assert.throws(() => parseContentReportRequest({
    targetType: "profile",
    targetId: "user-1",
    reason: "spam",
    illegalExplanation: "A specific unlawful promotion.",
    goodFaithConfirmed: true,
  }));
  assert.throws(() => parseContentReportRequest({
    targetType: "news",
    targetId: "news/one",
    reason: "spam",
    illegalExplanation: "A specific unlawful promotion.",
    goodFaithConfirmed: true,
  }));
  assert.throws(() => parseContentReportRequest({
    targetType: "news",
    targetId: "news-1",
    reason: "spam",
    illegalExplanation: "x".repeat(5_001),
    goodFaithConfirmed: true,
  }));
});

test("uses stable per-reporter target ids and reason-based SLA", () => {
  const target = {
    targetType: "comment" as const,
    targetId: "comment-1",
    parentType: "news" as const,
    parentId: "news-1",
  };

  assert.equal(contentReportDocumentId("user-1", target), contentReportDocumentId("user-1", target));
  assert.notEqual(contentReportDocumentId("user-1", target), contentReportDocumentId("user-2", target));
  assert.equal(reportSlaHours("violence"), 24);
  assert.equal(reportSlaHours("spam"), 72);
});
