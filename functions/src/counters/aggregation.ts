import { FieldValue } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";

import { db } from "../firebase/admin";

type CounterCollection = "events" | "news" | "organizations";
type CounterField =
  | "commentCount"
  | "likeCount"
  | "registeredCount"
  | "subscriberCount"
  | "viewCount";
type CounterDelta = -1 | 1;

const triggerOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

async function counterAggregationEnabled(): Promise<boolean> {
  const snapshot = await db.collection("appRuntimeConfig").doc("counterAggregation").get();
  return snapshot.data()?.enabled === true;
}

function stringField(data: Record<string, unknown>, field: string): string | undefined {
  const value = data[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

function eventParam(params: Record<string, string>, field: string): string | undefined {
  const value = params[field];
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : undefined;
}

async function updateExistingCounter(
  collection: CounterCollection,
  documentId: string | undefined,
  field: CounterField,
  delta: CounterDelta
): Promise<void> {
  if (documentId === undefined) {
    return;
  }

  const reference = db.collection(collection).doc(documentId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (!snapshot.exists) {
      return;
    }

    if (delta > 0) {
      transaction.update(reference, {
        [field]: FieldValue.increment(delta),
      });
      return;
    }

    const currentValue = snapshot.get(field);
    const currentCount = typeof currentValue === "number" ? currentValue : 0;
    transaction.update(reference, {
      [field]: Math.max(0, currentCount + delta),
    });
  });
}

async function updateLikeCounter(
  data: Record<string, unknown> | undefined,
  delta: CounterDelta
): Promise<void> {
  if (data === undefined || !(await counterAggregationEnabled())) {
    return;
  }

  const newsId = stringField(data, "newsId");
  if (newsId !== undefined) {
    await updateExistingCounter("news", newsId, "likeCount", delta);
    return;
  }

  const eventId = stringField(data, "eventId");
  if (eventId !== undefined) {
    await updateExistingCounter("events", eventId, "likeCount", delta);
    return;
  }

  const organizationId = stringField(data, "organizationId");
  if (organizationId !== undefined) {
    await updateExistingCounter("organizations", organizationId, "likeCount", delta);
    return;
  }

  const subscribedOrganizationId = stringField(data, "subscribedOrganizationId");
  await updateExistingCounter("organizations", subscribedOrganizationId, "subscriberCount", delta);
}

async function updateRegistrationCounter(
  data: Record<string, unknown> | undefined,
  delta: CounterDelta
): Promise<void> {
  if (data === undefined || !(await counterAggregationEnabled())) {
    return;
  }

  await updateExistingCounter("events", stringField(data, "eventId"), "registeredCount", delta);
}

async function updateCounterFromParam(
  collection: CounterCollection,
  documentId: string | undefined,
  field: CounterField,
  delta: CounterDelta
): Promise<void> {
  if (!(await counterAggregationEnabled())) {
    return;
  }

  await updateExistingCounter(collection, documentId, field, delta);
}

export const aggregateLikeCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "likes/{likeId}" },
  async (event) => {
    await updateLikeCounter(event.data?.data(), 1);
  }
);

export const aggregateLikeCounterOnDelete = onDocumentDeleted(
  { ...triggerOptions, document: "likes/{likeId}" },
  async (event) => {
    await updateLikeCounter(event.data?.data(), -1);
  }
);

export const aggregateRegistrationCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "registrations/{registrationId}" },
  async (event) => {
    await updateRegistrationCounter(event.data?.data(), 1);
  }
);

export const aggregateRegistrationCounterOnDelete = onDocumentDeleted(
  { ...triggerOptions, document: "registrations/{registrationId}" },
  async (event) => {
    await updateRegistrationCounter(event.data?.data(), -1);
  }
);

export const aggregateNewsCommentCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "news/{newsId}/comments/{commentId}" },
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "commentCount", 1);
  }
);

export const aggregateNewsCommentCounterOnDelete = onDocumentDeleted(
  { ...triggerOptions, document: "news/{newsId}/comments/{commentId}" },
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "commentCount", -1);
  }
);

export const aggregateEventCommentCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "events/{eventId}/comments/{commentId}" },
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "commentCount", 1);
  }
);

export const aggregateEventCommentCounterOnDelete = onDocumentDeleted(
  { ...triggerOptions, document: "events/{eventId}/comments/{commentId}" },
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "commentCount", -1);
  }
);

export const aggregateNewsViewCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "users/{uid}/newsViews/{newsId}" },
  async (event) => {
    const newsId = eventParam(event.params, "newsId");
    await updateCounterFromParam("news", newsId, "viewCount", 1);
  }
);

export const aggregateEventViewCounterOnCreate = onDocumentCreated(
  { ...triggerOptions, document: "users/{uid}/eventViews/{eventId}" },
  async (event) => {
    const eventId = eventParam(event.params, "eventId");
    await updateCounterFromParam("events", eventId, "viewCount", 1);
  }
);
