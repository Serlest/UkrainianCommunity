import {strict as assert} from "node:assert";
import {after, beforeEach, test} from "node:test";

import {Timestamp, type DocumentReference} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {
  cleanupExpiredScheduledPublicationLeases,
  processScheduledCollection,
  publishScheduledCandidate,
  recoverExpiredPlanningPublications,
} from "./scheduledPublishing";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const ownerUserId = "scheduled-publishing-owner";
const organizationId = "scheduled-publishing-organization";
const ownerReference = db.collection("users").doc(ownerUserId);
const organizationReference = db.collection("organizations").doc(organizationId);

beforeEach(async () => {
  if (!live) return;
  await cleanup();
  await Promise.all([
    ownerReference.set({
      accountStatus: "active",
      blockState: "active",
      globalRole: "owner",
    }),
    organizationReference.set({
      moderationStatus: "approved",
      ownerId: ownerUserId,
      name: "Scheduled Publishing Organization",
    }),
  ]);
});

after(async () => {
  if (live) await cleanup();
});

test("two simultaneous workers publish one durable result", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(10_000);
  const contentId = "concurrent-news";
  const planning = await createScheduledNews(contentId, "a".repeat(40), now);

  const outcomes = await Promise.all([
    publishScheduledCandidate("news", contentId, now),
    publishScheduledCandidate("news", contentId, now),
  ]);

  assert.deepEqual(outcomes.sort(), ["approved", "skipped"]);
  const [content, receipt, lease] = await Promise.all([
    db.collection("news").doc(contentId).get(),
    planning.get(),
    schedulerLease(contentId).get(),
  ]);
  assert.equal(content.get("moderationStatus"), "approved");
  assert.equal(content.get("scheduledAt"), undefined);
  assert.equal(receipt.get("state"), "completed");
  assert.equal(receipt.get("publicationOutcome"), "approved");
  assert.equal(lease.exists, false);
});

test("an exception after claim releases only its own lease", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(20_000);
  const contentId = "lookup-failure-news";
  await createScheduledNews(contentId, "b".repeat(40), now);

  await assert.rejects(
    publishScheduledCandidate("news", contentId, now, {
      planningDraftLookup: async () => {
        throw new Error("simulated planning lookup failure");
      },
    }),
    /simulated planning lookup failure/
  );

  const [content, lease] = await Promise.all([
    db.collection("news").doc(contentId).get(),
    schedulerLease(contentId).get(),
  ]);
  assert.equal(content.get("moderationStatus"), "draft");
  assert.ok(content.get("scheduledAt") instanceof Timestamp);
  assert.equal(lease.exists, false);
});

test("a stale worker cannot overwrite a newer manual schedule", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(30_000);
  const contentId = "rescheduled-news";
  const planning = await createScheduledNews(contentId, "c".repeat(40), now);
  let markLookupReached: (() => void) | undefined;
  let continueLookup: (() => void) | undefined;
  const lookupReached = new Promise<void>((resolve) => {
    markLookupReached = resolve;
  });
  const lookupCanContinue = new Promise<void>((resolve) => {
    continueLookup = resolve;
  });

  const publication = publishScheduledCandidate("news", contentId, now, {
    planningDraftLookup: async () => {
      markLookupReached?.();
      await lookupCanContinue;
      return planning;
    },
  });
  await lookupReached;
  const newerSchedule = Timestamp.fromMillis(60_000);
  await Promise.all([
    db.collection("news").doc(contentId).update({scheduledAt: newerSchedule}),
    planning.update({scheduledAt: newerSchedule}),
  ]);
  continueLookup?.();

  assert.equal(await publication, "skipped");
  const [content, planningSnapshot, lease] = await Promise.all([
    db.collection("news").doc(contentId).get(),
    planning.get(),
    schedulerLease(contentId).get(),
  ]);
  assert.equal(content.get("moderationStatus"), "draft");
  assert.equal(content.get("scheduledAt").toMillis(), newerSchedule.toMillis());
  assert.equal(planningSnapshot.get("state"), "scheduled");
  assert.equal(planningSnapshot.get("scheduledAt").toMillis(), newerSchedule.toMillis());
  assert.equal(lease.exists, false);
});

test("an active owner publication remains untouched by the scheduler", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(35_000);
  const contentId = "active-owner-news";
  const planning = planningReference("9".repeat(40));
  await Promise.all([
    createPublishingPlanning(planning, contentId, Timestamp.fromMillis(36_000)),
    createNews(contentId, "draft", Timestamp.fromMillis(34_000)),
  ]);

  assert.equal(await publishScheduledCandidate("news", contentId, now), "skipped");
  const [content, planningSnapshot, lease] = await Promise.all([
    db.collection("news").doc(contentId).get(),
    planning.get(),
    schedulerLease(contentId).get(),
  ]);
  assert.equal(content.get("moderationStatus"), "draft");
  assert.ok(content.get("scheduledAt") instanceof Timestamp);
  assert.equal(planningSnapshot.get("state"), "publishing");
  assert.ok(planningSnapshot.get("publicationLeaseId"));
  assert.equal(lease.exists, false);
});

test("expired owner publications recover fail-closed", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(40_000);
  const expiredAt = Timestamp.fromMillis(39_000);
  const activeUntil = Timestamp.fromMillis(41_000);
  const draftContentId = "expired-draft-news";
  const approvedContentId = "expired-approved-news";
  const activeContentId = "active-owner-publication-news";
  const draftPlanning = planningReference("d".repeat(40));
  const approvedPlanning = planningReference("e".repeat(40));
  const activePlanning = planningReference("f".repeat(40));

  await Promise.all([
    createPublishingPlanning(draftPlanning, draftContentId, expiredAt),
    createPublishingPlanning(approvedPlanning, approvedContentId, expiredAt),
    createPublishingPlanning(activePlanning, activeContentId, activeUntil),
    createNews(draftContentId, "draft", Timestamp.fromMillis(38_000)),
    createNews(approvedContentId, "approved"),
    createNews(activeContentId, "draft", Timestamp.fromMillis(38_000)),
  ]);

  const result = await recoverExpiredPlanningPublications(now);

  assert.deepEqual(result, {found: 2, changed: 2, skipped: 0, failed: 0});
  const [draft, approved, active, draftContent, activeContent] = await Promise.all([
    draftPlanning.get(),
    approvedPlanning.get(),
    activePlanning.get(),
    db.collection("news").doc(draftContentId).get(),
    db.collection("news").doc(activeContentId).get(),
  ]);
  assert.equal(draft.get("state"), "needsAttention");
  assert.equal(draft.get("publicationLeaseId"), undefined);
  assert.equal(draftContent.get("moderationStatus"), "draft");
  assert.equal(draftContent.get("scheduledAt"), undefined);
  assert.equal(approved.get("state"), "completed");
  assert.equal(approved.get("publicationOutcome"), "approved");
  assert.equal(approved.get("publicationLeaseId"), undefined);
  assert.equal(active.get("state"), "publishing");
  assert.ok(active.get("publicationLeaseId"));
  assert.ok(activeContent.get("scheduledAt") instanceof Timestamp);
});

test("expired scheduler leases are removed while active leases survive", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(50_000);
  const expired = db.collection("scheduledPublicationLeases").doc("expired");
  const active = db.collection("scheduledPublicationLeases").doc("active");
  await Promise.all([
    expired.set({leaseId: "expired", expiresAt: Timestamp.fromMillis(49_000)}),
    active.set({leaseId: "active", expiresAt: Timestamp.fromMillis(51_000)}),
  ]);

  const result = await cleanupExpiredScheduledPublicationLeases(now);

  assert.deepEqual(result, {found: 1, changed: 1, skipped: 0, failed: 0});
  const [expiredSnapshot, activeSnapshot] = await Promise.all([expired.get(), active.get()]);
  assert.equal(expiredSnapshot.exists, false);
  assert.equal(activeSnapshot.exists, true);
});

test("the due query excludes stale non-draft records", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(60_000);
  const dueContentId = "query-due-news";
  const staleContentId = "query-approved-news";
  await Promise.all([
    createScheduledNews(dueContentId, "1".repeat(40), now),
    createNews(staleContentId, "approved", Timestamp.fromMillis(59_000)),
  ]);

  const result = await processScheduledCollection("news", now);

  assert.deepEqual(result, {found: 1, published: 1, review: 0, skipped: 0, failed: 0});
  const stale = await db.collection("news").doc(staleContentId).get();
  assert.equal(stale.get("moderationStatus"), "approved");
  assert.ok(stale.get("scheduledAt") instanceof Timestamp);
});

test("scheduled events use the same durable lease contract", {skip: !live}, async () => {
  const now = Timestamp.fromMillis(70_000);
  const contentId = "scheduled-event";
  const scheduledAt = Timestamp.fromMillis(69_000);
  const planning = planningReference("2".repeat(40));
  await Promise.all([
    db.collection("events").doc(contentId).set({
      id: contentId,
      title: "Scheduled event",
      startDate: Timestamp.fromMillis(80_000),
      authorId: ownerUserId,
      organizationId,
      organizationName: "Scheduled Publishing Organization",
      moderationStatus: "draft",
      scheduledAt,
    }),
    planning.set({
      id: planning.id,
      ownerUserId,
      kind: "event",
      state: "scheduled",
      scheduledAt,
      publishedContentId: contentId,
      publishedContentKind: "event",
      publicationOutcome: "scheduled",
    }),
  ]);

  assert.equal(await publishScheduledCandidate("events", contentId, now), "approved");
  const [content, receipt, lease] = await Promise.all([
    db.collection("events").doc(contentId).get(),
    planning.get(),
    db.collection("scheduledPublicationLeases").doc(`events_${contentId}`).get(),
  ]);
  assert.equal(content.get("moderationStatus"), "approved");
  assert.equal(content.get("scheduledAt"), undefined);
  assert.equal(receipt.get("state"), "completed");
  assert.equal(receipt.get("publishedContentKind"), "event");
  assert.equal(lease.exists, false);
});

async function createScheduledNews(
  contentId: string,
  draftId: string,
  now: Timestamp
): Promise<DocumentReference> {
  const scheduledAt = Timestamp.fromMillis(now.toMillis() - 1_000);
  const planning = planningReference(draftId);
  await Promise.all([
    createNews(contentId, "draft", scheduledAt),
    planning.set({
      id: draftId,
      ownerUserId,
      kind: "news",
      state: "scheduled",
      scheduledAt,
      publishedContentId: contentId,
      publishedContentKind: "news",
      publicationOutcome: "scheduled",
    }),
  ]);
  return planning;
}

async function createPublishingPlanning(
  reference: DocumentReference,
  contentId: string,
  expiresAt: Timestamp
): Promise<void> {
  await reference.set({
    id: reference.id,
    ownerUserId,
    kind: "news",
    state: "publishing",
    publishedContentId: contentId,
    publishedContentKind: "news",
    publicationAttemptId: `attempt-${reference.id}`,
    publicationLeaseId: `lease-${reference.id}`,
    publicationLeaseExpiresAt: expiresAt,
  });
}

async function createNews(
  contentId: string,
  moderationStatus: "draft" | "approved",
  scheduledAt?: Timestamp
): Promise<void> {
  await db.collection("news").doc(contentId).set({
    id: contentId,
    title: contentId,
    sourceURL: `https://example.com/${contentId}`,
    authorId: ownerUserId,
    organizationId,
    organizationName: "Scheduled Publishing Organization",
    moderationStatus,
    regionScope: "federalState",
    ...(scheduledAt ? {scheduledAt} : {}),
  });
}

function planningReference(draftId: string): DocumentReference {
  return ownerReference.collection("contentPlanningDrafts").doc(draftId);
}

function schedulerLease(contentId: string): DocumentReference {
  return db.collection("scheduledPublicationLeases").doc(`news_${contentId}`);
}

async function cleanup(): Promise<void> {
  await Promise.all([
    db.recursiveDelete(ownerReference),
    organizationReference.delete(),
    db.recursiveDelete(db.collection("news")),
    db.recursiveDelete(db.collection("events")),
    db.recursiveDelete(db.collection("scheduledPublicationLeases")),
  ]);
}
