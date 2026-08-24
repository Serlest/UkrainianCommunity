import {strict as assert} from "node:assert";
import {test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

import {
  type EventRegistrationMutationAction,
  type EventRegistrationMutationResponse,
  planEventRegistrationMutation,
} from "./eventRegistration";
import {registrationCounterDedupeOperationId} from "../counters/aggregation";

const now = Timestamp.fromDate(new Date("2026-08-24T10:00:00.000Z"));

function event(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    moderationStatus: "approved",
    cancellationState: "active",
    startDate: Timestamp.fromDate(new Date("2026-08-25T10:00:00.000Z")),
    requiresRegistration: true,
    registeredCount: 0,
    capacity: 20,
    ...overrides,
  };
}

function assertRegistrationError(
  operation: () => unknown,
  code: string,
  reason: string
): void {
  assert.throws(operation, (error: unknown) => {
    assert.ok(error instanceof HttpsError);
    assert.equal(error.code, code);
    assert.deepEqual(error.details, {reason});
    return true;
  });
}

test("register creates a server-managed registration and authoritative count", () => {
  const plan = planEventRegistrationMutation({
    action: "register",
    eventId: "event-1",
    userId: "user-1",
    eventData: event({registeredCount: 4}),
    registrationExists: false,
    registrationData: undefined,
    now,
    operationId: "operation-1",
  });

  assert.deepEqual(plan.response, {
    eventId: "event-1",
    registrationState: "registered",
    registeredCount: 5,
    didChange: true,
  });
  assert.equal(plan.nextRegisteredCount, 5);
  assert.equal(plan.registrationData?.counterManagedAtomically, true);
  assert.equal(plan.registrationData?.counterOperationId, "operation-1");
});

test("duplicate register and unregister calls are idempotent", () => {
  const duplicateRegister = planEventRegistrationMutation({
    action: "register",
    eventId: "event-1",
    userId: "user-1",
    eventData: event({registeredCount: 1, capacity: 1}),
    registrationExists: true,
    registrationData: {counterOperationId: "original-operation"},
    now,
    operationId: "ignored-operation",
  });
  assert.deepEqual(duplicateRegister.response, {
    eventId: "event-1",
    registrationState: "registered",
    registeredCount: 1,
    didChange: false,
  });
  assert.equal(duplicateRegister.nextRegisteredCount, undefined);

  const duplicateUnregister = planEventRegistrationMutation({
    action: "unregister",
    eventId: "event-1",
    userId: "user-1",
    eventData: event({registeredCount: 0}),
    registrationExists: false,
    registrationData: undefined,
    now,
    operationId: "operation-2",
  });
  assert.deepEqual(duplicateUnregister.response, {
    eventId: "event-1",
    registrationState: "notRegistered",
    registeredCount: 0,
    didChange: false,
  });
});

test("unregister atomically decrements without going negative and records trigger dedupe", () => {
  const plan = planEventRegistrationMutation({
    action: "unregister",
    eventId: "event-1",
    userId: "user-1",
    eventData: event({registeredCount: 1}),
    registrationExists: true,
    registrationData: {counterOperationId: "registration-generation-1"},
    now,
    operationId: "new-operation",
  });

  assert.equal(plan.response.registrationState, "notRegistered");
  assert.equal(plan.response.registeredCount, 0);
  assert.equal(plan.response.didChange, true);
  assert.equal(plan.deleteRegistration, true);
  assert.equal(plan.counterOperationId, "registration-generation-1");
  assert.equal(plan.counterOperationData?.operation, "unregister");
});

test("legacy unregister uses the registration id that the delete trigger can dedupe", () => {
  const registrationId = "event_event-1_legacy-user";
  const plan = planEventRegistrationMutation({
    action: "unregister",
    eventId: "event-1",
    userId: "legacy-user",
    eventData: event({registeredCount: 3}),
    registrationExists: true,
    registrationData: {
      id: registrationId,
      eventId: "event-1",
      userId: "legacy-user",
    },
    now,
    operationId: "new-random-operation",
  });

  assert.equal(plan.response.registeredCount, 2);
  assert.equal(plan.counterOperationId, registrationId);
  assert.equal(
    registrationCounterDedupeOperationId(
      plan.registrationData,
      registrationId
    ),
    registrationId
  );
  assert.equal(plan.counterOperationData?.operation, "unregister");
});

test("rejects missing, no-registration, cancelled, past, and full events", () => {
  const input = {
    action: "register" as const,
    eventId: "event-1",
    userId: "user-1",
    registrationExists: false,
    registrationData: undefined,
    now,
    operationId: "operation-1",
  };

  assertRegistrationError(
    () => planEventRegistrationMutation({...input, eventData: undefined}),
    "not-found",
    "event-not-found"
  );
  assertRegistrationError(
    () => planEventRegistrationMutation({
      ...input,
      eventData: event({requiresRegistration: false}),
    }),
    "failed-precondition",
    "registration-not-required"
  );
  assertRegistrationError(
    () => planEventRegistrationMutation({
      ...input,
      eventData: event({cancellationState: "cancelled"}),
    }),
    "failed-precondition",
    "event-cancelled"
  );
  assertRegistrationError(
    () => planEventRegistrationMutation({
      ...input,
      eventData: event({startDate: now}),
    }),
    "failed-precondition",
    "event-past"
  );
  assertRegistrationError(
    () => planEventRegistrationMutation({
      ...input,
      eventData: event({registeredCount: 20, capacity: 20}),
    }),
    "resource-exhausted",
    "event-full"
  );
});

test("concurrent users cannot both claim the last slot", async () => {
  const harness = new InMemoryRegistrationHarness(event({capacity: 1}));
  const attempts = await Promise.allSettled([
    harness.mutate("register", "user-1"),
    harness.mutate("register", "user-2"),
  ]);

  assert.equal(attempts.filter((attempt) => attempt.status === "fulfilled").length, 1);
  assert.equal(attempts.filter((attempt) => attempt.status === "rejected").length, 1);
  const rejection = attempts.find((attempt) => attempt.status === "rejected");
  assert.ok(rejection?.status === "rejected" && rejection.reason instanceof HttpsError);
  assert.equal(rejection.reason.code, "resource-exhausted");
  assert.equal(harness.registeredCount, 1);
  assert.equal(harness.registrationCount, 1);
});

class InMemoryRegistrationHarness {
  private readonly eventData: Record<string, unknown>;
  private readonly registrations = new Map<string, Record<string, unknown>>();
  private transactionTail: Promise<void> = Promise.resolve();
  private operationSequence = 0;

  constructor(eventData: Record<string, unknown>) {
    this.eventData = {...eventData};
  }

  get registeredCount(): number {
    return this.eventData.registeredCount as number;
  }

  get registrationCount(): number {
    return this.registrations.size;
  }

  async mutate(
    action: EventRegistrationMutationAction,
    userId: string
  ): Promise<EventRegistrationMutationResponse> {
    const previousTransaction = this.transactionTail;
    let releaseTransaction: () => void = () => undefined;
    this.transactionTail = new Promise<void>((resolve) => {
      releaseTransaction = resolve;
    });
    await previousTransaction;

    try {
      const registrationData = this.registrations.get(userId);
      const operationId = `operation-${++this.operationSequence}`;
      const plan = planEventRegistrationMutation({
        action,
        eventId: "event-1",
        userId,
        eventData: this.eventData,
        registrationExists: registrationData !== undefined,
        registrationData,
        now,
        operationId,
      });

      if (plan.registrationData !== undefined) {
        this.registrations.set(userId, plan.registrationData);
      }
      if (plan.deleteRegistration) {
        this.registrations.delete(userId);
      }
      if (plan.nextRegisteredCount !== undefined) {
        this.eventData.registeredCount = plan.nextRegisteredCount;
      }
      return plan.response;
    } finally {
      releaseTransaction();
    }
  }
}
