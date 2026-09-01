import {strict as assert} from "node:assert";
import {after, beforeEach, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {cleanupDeletedContentReferences} from "./contentDeletion";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const contentId = "content-lifecycle-shared-id";
const userId = "content-lifecycle-user";
const newsReference = db.collection("news").doc(contentId);
const eventReference = db.collection("events").doc(contentId);
const userReference = db.collection("users").doc(userId);

beforeEach(async () => {
  if (!live) return;
  await cleanup();
  const now = Timestamp.fromMillis(1_000);
  await Promise.all([
    newsReference.set({id: contentId, moderationStatus: "approved"}),
    eventReference.set({id: contentId, moderationStatus: "approved"}),
    userReference.set({id: userId}),
    db.collection("likes").doc(`${contentId}_${userId}`).set({newsId: contentId}),
    db.collection("likes").doc(`event_${contentId}_${userId}`).set({eventId: contentId}),
    userReference.collection("newsBookmarks").doc(contentId).set({newsId: contentId}),
    userReference.collection("eventBookmarks").doc(contentId).set({eventId: contentId}),
    userReference.collection("newsViews").doc(contentId).set({newsId: contentId}),
    userReference.collection("eventViews").doc(contentId).set({eventId: contentId}),
    userReference.collection("recentViews").doc(`news_${contentId}`).set({
      itemId: contentId,
      itemType: "news",
    }),
    userReference.collection("recentViews").doc(`event_${contentId}`).set({
      itemId: contentId,
      itemType: "event",
    }),
    userReference.collection("activityLog").doc("news-action").set({
      targetId: contentId,
      targetType: "news",
    }),
    userReference.collection("activityLog").doc("event-action").set({
      targetId: contentId,
      targetType: "event",
    }),
    userReference.collection("notificationInbox").doc("news-notification").set({
      actionTargetId: contentId,
      actionType: "openNews",
    }),
    userReference.collection("notificationInbox").doc("event-notification").set({
      actionTargetId: contentId,
      actionType: "openEvent",
    }),
    db.collection("featuredBanners").doc("news-banner").set({
      actionTargetID: contentId,
      actionType: "news",
      isActive: true,
      updatedAt: now,
    }),
    db.collection("featuredBanners").doc("event-banner").set({
      actionTargetID: contentId,
      actionType: "event",
      isActive: true,
      updatedAt: now,
    }),
  ]);
});

after(async () => {
  if (live) await cleanup();
});

test("news lifecycle removes only news references and safely retires its banner", {
  skip: !live,
}, async () => {
  await cleanupDeletedContentReferences("news", contentId);
  await cleanupDeletedContentReferences("news", contentId);

  const [
    news,
    event,
    newsLike,
    eventLike,
    newsRecent,
    eventRecent,
    newsActivity,
    eventActivity,
    newsNotification,
    eventNotification,
    newsBanner,
    eventBanner,
  ] = await Promise.all([
    newsReference.get(),
    eventReference.get(),
    db.collection("likes").doc(`${contentId}_${userId}`).get(),
    db.collection("likes").doc(`event_${contentId}_${userId}`).get(),
    userReference.collection("recentViews").doc(`news_${contentId}`).get(),
    userReference.collection("recentViews").doc(`event_${contentId}`).get(),
    userReference.collection("activityLog").doc("news-action").get(),
    userReference.collection("activityLog").doc("event-action").get(),
    userReference.collection("notificationInbox").doc("news-notification").get(),
    userReference.collection("notificationInbox").doc("event-notification").get(),
    db.collection("featuredBanners").doc("news-banner").get(),
    db.collection("featuredBanners").doc("event-banner").get(),
  ]);

  assert.equal(news.exists, true);
  assert.equal(event.exists, true);
  assert.equal(newsLike.exists, false);
  assert.equal(eventLike.exists, true);
  assert.equal(newsRecent.exists, false);
  assert.equal(eventRecent.exists, true);
  assert.equal(newsActivity.exists, false);
  assert.equal(eventActivity.exists, true);
  assert.equal(newsNotification.exists, false);
  assert.equal(eventNotification.exists, true);
  assert.equal(newsBanner.get("isActive"), false);
  assert.equal(newsBanner.get("actionType"), "none");
  assert.equal(newsBanner.get("actionTargetID"), undefined);
  assert.equal(eventBanner.get("isActive"), true);
  assert.equal(eventBanner.get("actionType"), "event");
});

async function cleanup(): Promise<void> {
  await Promise.all([
    db.recursiveDelete(userReference),
    newsReference.delete(),
    eventReference.delete(),
    db.collection("likes").doc(`${contentId}_${userId}`).delete(),
    db.collection("likes").doc(`event_${contentId}_${userId}`).delete(),
    db.collection("featuredBanners").doc("news-banner").delete(),
    db.collection("featuredBanners").doc("event-banner").delete(),
  ]);
}
