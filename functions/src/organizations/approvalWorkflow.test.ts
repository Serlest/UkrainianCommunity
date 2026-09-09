import {strict as assert} from "node:assert";
import {test} from "node:test";

import {HttpsError} from "firebase-functions/v2/https";

import {
  approveOrganizationWorkflow,
  assertReviewableStatus,
  notificationMessage,
  notificationPayload,
  parseReviewRequest,
  rejectOrganizationWorkflow,
  requiredReviewText,
  requestOrganizationRevisionWorkflow,
} from "./approvalWorkflow";

test("organization moderation input is normalized and required review text is enforced", () => {
  const revision = parseReviewRequest({
    organizationId: " org-1 ",
    message: " Add a public phone number ",
    operationId: " operation-1 ",
    expectedRevision: " 10:20 ",
  });
  assert.deepEqual(revision, {
    organizationId: "org-1",
    message: "Add a public phone number",
    reason: undefined,
    operationId: "operation-1",
    expectedRevision: "10:20",
  });
  assert.equal(requiredReviewText(revision, "message"), "Add a public phone number");
  assert.throws(
    () => requiredReviewText({organizationId: "org-1"}, "reason"),
    isHttpsError("invalid-argument")
  );
});

test("only a currently pending organization submission is reviewable", () => {
  assert.doesNotThrow(() => assertReviewableStatus("pendingReview"));
  for (const status of ["needsRevision", "rejected", "approved"] as const) {
    assert.throws(() => assertReviewableStatus(status), isHttpsError("failed-precondition"));
  }
});

test("approve, revision, and rejection notifications carry actionable organization context", () => {
  const organization = {
    organizationId: "org-1",
    submittedByUserId: "submitter-1",
    name: "Ukrainian Market",
  };

  assert.equal(
    notificationMessage(organization, approveOrganizationWorkflow),
    "Ukrainian Market was approved."
  );
  assert.deepEqual(
    notificationPayload(
      organization,
      requestOrganizationRevisionWorkflow,
      "Add opening hours"
    ),
    {
      organizationId: "org-1",
      organizationName: "Ukrainian Market",
      reviewMessage: "Add opening hours",
    }
  );
  assert.deepEqual(
    notificationPayload(organization, rejectOrganizationWorkflow, "Duplicate request"),
    {
      organizationId: "org-1",
      organizationName: "Ukrainian Market",
      rejectionReason: "Duplicate request",
    }
  );
});

function isHttpsError(code: string): (error: unknown) => boolean {
  return (error: unknown) => error instanceof HttpsError && error.code === code;
}
