import {strict as assert} from "node:assert";
import {after, beforeEach, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {adminStorage, db} from "../firebase/admin";
import {cleanupDeletedContentReferences, deleteNewsContent, deleteEventContent} from "./contentDeletion";
import {cleanupExpiredContent, eventRetentionDays, subtractUtcDays} from "../retention/dataRetention";
import {deleteListedContentStorageObjects} from "./contentStorageDeletion";

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

test("expired news deletion removes its comments, likes, saved records and cover", {
  skip: !live || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const cover = adminStorage.bucket().file(`news/${contentId}/cover.jpg`);
  const organizationCover = adminStorage.bucket().file(`organizations/org-1/news/${contentId}/cover.png`);
  await Promise.all([
    newsReference.update({organizationId: "org-1"}),
    newsReference.collection("comments").doc("comment-1").set({text: "Old comment"}),
    cover.save(Buffer.from("old-cover")),
    organizationCover.save(Buffer.from("old-organization-cover")),
  ]);

  await deleteNewsContent(contentId);

  const [news, comment, like, bookmark, view, event, coverExists, organizationCoverExists] = await Promise.all([
    newsReference.get(),
    newsReference.collection("comments").doc("comment-1").get(),
    db.collection("likes").doc(`${contentId}_${userId}`).get(),
    userReference.collection("newsBookmarks").doc(contentId).get(),
    userReference.collection("newsViews").doc(contentId).get(),
    eventReference.get(),
    cover.exists(),
    organizationCover.exists(),
  ]);
  assert.equal(news.exists, false);
  assert.equal(comment.exists, false);
  assert.equal(like.exists, false);
  assert.equal(bookmark.exists, false);
  assert.equal(view.exists, false);
  assert.equal(coverExists[0], false);
  assert.equal(organizationCoverExists[0], false);
  assert.equal(event.exists, true);
});

test("expired event deletion removes registrations, nested comments, references and media without touching news", {
  skip: !live || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const cover=adminStorage.bucket().file(`events/${contentId}/cover.jpg`);
  const legacy=adminStorage.bucket().file(`organizations/org-1/draftUploads/events/${contentId}_cover.jpg`);
  const organizationCover=adminStorage.bucket().file(`organizations/org-1/events/${contentId}/cover.png`);
  const registration=db.collection("registrations").doc(`retention_${contentId}`);
  const comment=eventReference.collection("comments").doc("old-comment");
  await Promise.all([
    eventReference.update({organizationId:"org-1"}), comment.set({text:"Old comment"}),
    comment.collection("replies").doc("reply").set({text:"Old reply"}),
    registration.set({eventId:contentId,userId}),cover.save(Buffer.from("cover")),legacy.save(Buffer.from("legacy")),organizationCover.save(Buffer.from("org-cover")),
  ]);
  await deleteEventContent(contentId);
  await deleteEventContent(contentId); // An interrupted/retried cleanup stays safe.
  const removed=[eventReference,comment,comment.collection("replies").doc("reply"),registration,
    db.collection("likes").doc(`event_${contentId}_${userId}`),
    userReference.collection("eventBookmarks").doc(contentId),userReference.collection("eventViews").doc(contentId),
    userReference.collection("recentViews").doc(`event_${contentId}`),
    userReference.collection("activityLog").doc("event-action"),userReference.collection("notificationInbox").doc("event-notification")];
  for (const reference of removed) assert.equal((await reference.get()).exists,false,reference.path);
  assert.equal((await cover.exists())[0],false);assert.equal((await legacy.exists())[0],false);
  assert.equal((await organizationCover.exists())[0],false);
  assert.equal((await newsReference.get()).exists,true);
  assert.equal((await userReference.collection("newsBookmarks").doc(contentId).get()).exists,true);
  const banner=await db.collection("featuredBanners").doc("event-banner").get();
  assert.equal(banner.get("isActive"),false);assert.equal(banner.get("actionType"),"none");
  assert.equal(banner.get("actionTargetID"),undefined);
});

test("scheduled event cleanup uses end date and exact 30-day boundary, keeping drafts and upcoming events", {
  skip: !live || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
}, async () => {
  const now=new Date("2026-10-29T03:00:00Z"),cutoff=subtractUtcDays(now,eventRetentionDays);
  const keep=["recent","future","pending","draft","missing-date"].map(s=>db.collection("events").doc(`${contentId}-${s}`));
  try {
    await eventReference.update({endDate:Timestamp.fromDate(cutoff)});
    await Promise.all(keep.map((ref,i)=>ref.set({moderationStatus:i===2 ? "pendingReview":i===3 ? "draft":"approved",
      ...(i===4 ? {}:{endDate:Timestamp.fromMillis(i===1 ? now.getTime()+86400000:i===0 ? cutoff.getTime()+1:cutoff.getTime()-1)}),
      date:Timestamp.fromMillis(0)})));
    assert.equal(await cleanupExpiredContent("events","endDate",cutoff),1);
    assert.equal((await eventReference.get()).exists,false);
    for (const ref of keep) assert.equal((await ref.get()).exists,true,ref.path);
    assert.equal((await newsReference.get()).exists,true);
    assert.equal(await cleanupExpiredContent("events","endDate",cutoff),0);
  } finally { await Promise.all(keep.map(ref=>db.recursiveDelete(ref))); }
});

test("simultaneous cleanup workers tolerate an object disappearing after listing", {
  skip:!live || !process.env.FIREBASE_STORAGE_EMULATOR_HOST,
},async()=>{
  const bucket=adminStorage.bucket(),prefix=`events/${contentId}/`;
  const cover=bucket.file(prefix+"raced-cover.jpg");await cover.save(Buffer.from("race"));
  const [listed]=await bucket.getFiles({prefix});assert.ok(listed.length>0);
  await cover.delete();
  async function* snapshot(){for(const file of listed) yield file;}
  await Promise.all([deleteListedContentStorageObjects(snapshot()),deleteListedContentStorageObjects(snapshot())]);
  assert.equal((await cover.exists())[0],false);
});

async function cleanup(): Promise<void> {
  await Promise.all([
    db.recursiveDelete(userReference),
    db.recursiveDelete(newsReference),
    db.recursiveDelete(eventReference),
    db.collection("likes").doc(`${contentId}_${userId}`).delete(),
    db.collection("likes").doc(`event_${contentId}_${userId}`).delete(),
    db.collection("featuredBanners").doc("news-banner").delete(),
    db.collection("featuredBanners").doc("event-banner").delete(),
  ]);
}
