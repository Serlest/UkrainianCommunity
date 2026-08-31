import {strict as assert} from "node:assert";
import {after, before, test} from "node:test";

import {Timestamp} from "firebase-admin/firestore";

import {db} from "../firebase/admin";
import {shouldDeliverInboxNotificationPush} from "./inboxPushDelivery";
import {
  followerImmediatePushWindowMs,
  followerPushDelivery,
  notifyOrganizationFollowers,
  type PublishedOrganizationContent,
} from "./organizationFollowerNotifications";

const live = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
const organizationId = "follower-notification-test-organization";
const contentId = "follower-notification-test-news";
const germanRecipientId = "follower-notification-test-german";
const ukrainianRecipientId = "follower-notification-test-ukrainian";
const excludedAuthorId = "follower-notification-test-author";
const restrictedRecipientId = "follower-notification-test-restricted";
const recipientIds = [
  germanRecipientId,
  ukrainianRecipientId,
  excludedAuthorId,
  restrictedRecipientId,
];

before(async () => {
  if (!live) return;
  await cleanup();

  await Promise.all([
    writeUser(germanRecipientId, "active", "active", "de"),
    writeUser(ukrainianRecipientId, "warned", "warned", "uk"),
    writeUser(excludedAuthorId, "active", "active", "uk"),
    writeUser(restrictedRecipientId, "bannedPermanent", "bannedPermanent", "de"),
  ]);

  const batch = db.batch();
  recipientIds.forEach((userId, index) => {
    const reference = db.collection("likes").doc(subscriptionId(userId));
    batch.set(reference, {
      id: reference.id,
      userId,
      subscribedOrganizationId: organizationId,
      createdAt: Timestamp.fromMillis(10_000 + index),
    });
  });
  await batch.commit();
});

after(async () => {
  if (live) await cleanup();
});

test("follower push is immediate for one hour and inbox-only afterwards", () => {
  const publishedAt = 1_000_000;
  assert.equal(
    followerPushDelivery(publishedAt, publishedAt + followerImmediatePushWindowMs),
    "central"
  );
  assert.equal(
    followerPushDelivery(publishedAt, publishedAt + followerImmediatePushWindowMs + 1),
    "recoveryInboxOnly"
  );
  assert.equal(followerPushDelivery(publishedAt, publishedAt - 1), "central");
  assert.equal(
    shouldDeliverInboxNotificationPush(
      "organizationNewsPublished",
      {pushDelivery: "recoveryInboxOnly"}
    ),
    false
  );
  assert.throws(
    () => followerPushDelivery(Number.NaN, publishedAt),
    /timestamps must be finite/
  );
});

test("follower fan-out is eligible, localized, retry-safe and preserves event time", {
  skip: !live,
}, async () => {
  const publicationEventAt = Timestamp.fromMillis(2_000_000);
  const content: PublishedOrganizationContent = {
    kind: "news",
    contentId,
    organizationId,
    organizationName: "Testorganisation",
    title: "Testnachricht",
    excludedUserIds: [excludedAuthorId],
    publicationEventAt,
    pushDelivery: "recoveryInboxOnly",
  };

  await notifyOrganizationFollowers(content);
  await notifyOrganizationFollowers(content);

  const germanNotification = await notification(germanRecipientId).get();
  const ukrainianNotification = await notification(ukrainianRecipientId).get();
  const authorNotification = await notification(excludedAuthorId).get();
  const restrictedNotification = await notification(restrictedRecipientId).get();

  assert.equal(germanNotification.exists, true);
  assert.equal(ukrainianNotification.exists, true);
  assert.equal(authorNotification.exists, false);
  assert.equal(restrictedNotification.exists, false);

  assert.equal(germanNotification.data()?.title, "Neue Nachricht von Testorganisation");
  assert.equal(ukrainianNotification.data()?.title, "Нова новина від Testorganisation");
  assert.equal(germanNotification.data()?.metadata?.pushDelivery, "recoveryInboxOnly");
  assert.equal(germanNotification.data()?.createdAt.toMillis(), publicationEventAt.toMillis());
  assert.equal(
    germanNotification.data()?.metadata?.publicationEventAt.toMillis(),
    publicationEventAt.toMillis()
  );

  const germanInbox = await db.collection("users")
    .doc(germanRecipientId)
    .collection("notificationInbox")
    .get();
  const ukrainianInbox = await db.collection("users")
    .doc(ukrainianRecipientId)
    .collection("notificationInbox")
    .get();
  assert.equal(germanInbox.size, 1);
  assert.equal(ukrainianInbox.size, 1);
});

async function writeUser(
  userId: string,
  accountStatus: string,
  blockState: string,
  appLanguage: string
): Promise<void> {
  await db.collection("users").doc(userId).set({
    accountStatus,
    blockState,
    appLanguage,
  });
}

function subscriptionId(userId: string): string {
  return `organization_follow_${organizationId}_${userId}`;
}

function notification(userId: string) {
  return db.collection("users")
    .doc(userId)
    .collection("notificationInbox")
    .doc(`organizationNewsPublished_${contentId}_${userId}`);
}

async function cleanup(): Promise<void> {
  await Promise.all(recipientIds.map((userId) =>
    db.recursiveDelete(db.collection("users").doc(userId))
  ));

  const batch = db.batch();
  recipientIds.forEach((userId) => {
    batch.delete(db.collection("likes").doc(subscriptionId(userId)));
  });
  await batch.commit();
}
