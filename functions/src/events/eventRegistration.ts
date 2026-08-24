import {randomUUID} from "node:crypto";

import {Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {
  analyticsActionProofCollection,
  analyticsActionProofDocumentData,
  requireMatchingAnalyticsActionProofBinding,
  type AnalyticsActionProofBinding,
} from "../analytics/analyticsActionProof";

export type EventRegistrationMutationAction = "register" | "unregister";
export type EventRegistrationState = "registered" | "notRegistered";

export interface EventRegistrationMutationResponse {
  eventId: string;
  registrationState: EventRegistrationState;
  registeredCount: number;
  didChange: boolean;
}

export interface EventRegistrationMutationPlan {
  response: EventRegistrationMutationResponse;
  nextRegisteredCount?: number;
  registrationData?: DocumentData;
  deleteRegistration: boolean;
  counterOperationData?: DocumentData;
  counterOperationId?: string;
}

export interface EventRegistrationMutationInput {
  action: EventRegistrationMutationAction;
  eventId: string;
  userId: string;
  eventData: DocumentData | undefined;
  registrationExists: boolean;
  registrationData: DocumentData | undefined;
  now: Timestamp;
  operationId: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
};

const registrationCounterOperationsCollection = "eventRegistrationCounterOperations";
const registrationCounterOperationRetentionMilliseconds = 30 * 24 * 60 * 60 * 1_000;
const maximumDocumentIdLength = 512;

export const registerForEvent = onCall(
  callableOptions,
  async (request): Promise<EventRegistrationMutationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const eventId = eventDocumentId(request.data);
    const actionProof = requireMatchingAnalyticsActionProofBinding(
      isRecord(request.data) ? request.data.actionProof : undefined,
      "event_register",
      eventId
    );
    return mutateEventRegistration("register", eventId, auth.uid, actionProof);
  }
);

export const unregisterFromEvent = onCall(
  callableOptions,
  async (request): Promise<EventRegistrationMutationResponse> => {
    const auth = await requireVerifiedActiveUser(request);
    const eventId = eventDocumentId(request.data);
    return mutateEventRegistration("unregister", eventId, auth.uid);
  }
);

export async function mutateEventRegistration(
  action: EventRegistrationMutationAction,
  eventId: string,
  userId: string,
  actionProof?: AnalyticsActionProofBinding
): Promise<EventRegistrationMutationResponse> {
  const eventReference = db.collection("events").doc(eventId);
  const registrationId = registrationDocumentId(eventId, userId);
  const registrationReference = db.collection("registrations").doc(registrationId);

  return db.runTransaction(async (transaction) => {
    const [eventSnapshot, registrationSnapshot] = await transaction.getAll(
      eventReference,
      registrationReference
    );
    const now = Timestamp.now();
    const operationId = randomUUID();
    const plan = planEventRegistrationMutation({
      action,
      eventId,
      userId,
      eventData: eventSnapshot.exists ? eventSnapshot.data() : undefined,
      registrationExists: registrationSnapshot.exists,
      registrationData: registrationSnapshot.data(),
      now,
      operationId,
    });

    if (plan.registrationData !== undefined) {
      transaction.create(registrationReference, plan.registrationData);
      if (actionProof !== undefined) {
        transaction.create(
          db.collection(analyticsActionProofCollection).doc(actionProof.proofID),
          analyticsActionProofDocumentData(actionProof, userId, now.toDate())
        );
      }
    }
    if (plan.counterOperationData !== undefined && plan.counterOperationId !== undefined) {
      transaction.create(
        db.collection(registrationCounterOperationsCollection).doc(plan.counterOperationId),
        plan.counterOperationData
      );
    }
    if (plan.deleteRegistration) {
      transaction.delete(registrationReference);
    }
    if (plan.nextRegisteredCount !== undefined) {
      transaction.update(eventReference, {
        registeredCount: plan.nextRegisteredCount,
      });
    }

    return plan.response;
  });
}

export function planEventRegistrationMutation(
  input: EventRegistrationMutationInput
): EventRegistrationMutationPlan {
  if (input.eventData === undefined) {
    throw registrationError("not-found", "event-not-found", "Event does not exist.");
  }

  const currentCount = nonNegativeInteger(
    input.eventData.registeredCount,
    "invalid-registration-counter"
  );

  if (input.action === "unregister") {
    if (!input.registrationExists) {
      return unchangedResponse(input.eventId, "notRegistered", currentCount);
    }

    const nextCount = Math.max(0, currentCount - 1);
    const counterOperationId = existingOperationId(input.registrationData) ??
      registrationDocumentId(input.eventId, input.userId);
    return {
      response: {
        eventId: input.eventId,
        registrationState: "notRegistered",
        registeredCount: nextCount,
        didChange: true,
      },
      nextRegisteredCount: nextCount,
      deleteRegistration: true,
      counterOperationId,
      counterOperationData: {
        id: counterOperationId,
        registrationId: registrationDocumentId(input.eventId, input.userId),
        eventId: input.eventId,
        userId: input.userId,
        operation: "unregister",
        createdAt: input.now,
        expiresAt: Timestamp.fromMillis(
          input.now.toMillis() + registrationCounterOperationRetentionMilliseconds
        ),
      },
    };
  }

  // Retrying an already committed registration is deliberately idempotent. The
  // existing server document wins even if the event became full in the meantime.
  if (input.registrationExists) {
    return unchangedResponse(input.eventId, "registered", currentCount);
  }

  assertEventAcceptsRegistration(input.eventData, input.now, currentCount);
  const nextCount = currentCount + 1;
  const registrationId = registrationDocumentId(input.eventId, input.userId);
  return {
    response: {
      eventId: input.eventId,
      registrationState: "registered",
      registeredCount: nextCount,
      didChange: true,
    },
    nextRegisteredCount: nextCount,
    registrationData: {
      id: registrationId,
      eventId: input.eventId,
      userId: input.userId,
      registeredAt: input.now,
      createdAt: input.now,
      counterManagedAtomically: true,
      counterOperationId: input.operationId,
    },
    deleteRegistration: false,
  };
}

function assertEventAcceptsRegistration(
  eventData: DocumentData,
  now: Timestamp,
  registeredCount: number
): void {
  if (eventData.cancellationState === "cancelled") {
    throw registrationError(
      "failed-precondition",
      "event-cancelled",
      "Registration is closed because the event was cancelled."
    );
  }
  if (eventData.moderationStatus !== "approved") {
    throw registrationError(
      "failed-precondition",
      "event-not-approved",
      "Registration is only available for approved events."
    );
  }

  const startDate = eventData.startDate;
  if (!(startDate instanceof Timestamp)) {
    throw registrationError(
      "failed-precondition",
      "invalid-registration-config",
      "The event start date is invalid."
    );
  }
  if (startDate.toMillis() <= now.toMillis()) {
    throw registrationError(
      "failed-precondition",
      "event-past",
      "Registration is closed because the event has already started."
    );
  }
  if (eventData.requiresRegistration !== true) {
    throw registrationError(
      "failed-precondition",
      "registration-not-required",
      "This event does not accept in-app registrations."
    );
  }

  const capacity = optionalPositiveInteger(eventData.capacity);
  if (capacity !== undefined && registeredCount >= capacity) {
    throw registrationError(
      "resource-exhausted",
      "event-full",
      "This event has reached its registration capacity."
    );
  }
}

function eventDocumentId(data: unknown): string {
  if (!isRecord(data) || typeof data.eventId !== "string") {
    throw registrationError("invalid-argument", "invalid-event-id", "eventId is required.");
  }

  const eventId = data.eventId.trim();
  if (
    eventId.length === 0 ||
    eventId.length > maximumDocumentIdLength ||
    eventId.includes("/")
  ) {
    throw registrationError(
      "invalid-argument",
      "invalid-event-id",
      "eventId must be a valid document ID."
    );
  }
  return eventId;
}

function registrationDocumentId(eventId: string, userId: string): string {
  return `event_${eventId}_${userId}`;
}

function nonNegativeInteger(value: unknown, reason: string): number {
  if (value === undefined || value === null) {
    return 0;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw registrationError(
      "failed-precondition",
      reason,
      "The event registration counter is invalid."
    );
  }
  return value;
}

function optionalPositiveInteger(value: unknown): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0) {
    throw registrationError(
      "failed-precondition",
      "invalid-registration-config",
      "The event capacity is invalid."
    );
  }
  return value;
}

function existingOperationId(data: DocumentData | undefined): string | undefined {
  const value = data?.counterOperationId;
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function unchangedResponse(
  eventId: string,
  registrationState: EventRegistrationState,
  registeredCount: number
): EventRegistrationMutationPlan {
  return {
    response: {
      eventId,
      registrationState,
      registeredCount,
      didChange: false,
    },
    deleteRegistration: false,
  };
}

function registrationError(
  code: "failed-precondition" | "invalid-argument" | "not-found" | "resource-exhausted",
  reason: string,
  message: string
): HttpsError {
  return new HttpsError(code, message, {reason});
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
