import assert from "node:assert/strict";
import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-email-verification-rules";
const RULES_PATH = "../../Firebase/firestore.rules";

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL(RULES_PATH, import.meta.url), "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seed();
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function auth(uid, emailVerified = false) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
  }).firestore();
}

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, "users", "unverified-user"), user("unverified-user"));
    await setDoc(doc(db, "users", "verified-user"), user("verified-user"));
    await setDoc(doc(db, "users", "owner-user"), user("owner-user", {
      globalRole: "owner",
    }));

    await setDoc(doc(db, "news", "news-1"), {
      id: "news-1",
      moderationStatus: "approved",
      sourceType: "organization",
      organizationId: "org-1",
      title: "News item",
      summary: "Approved for rule testing",
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      registeredCount: 0,
      createdAt: new Date("2026-06-01T10:00:00Z"),
      updatedAt: new Date("2026-06-01T10:00:00Z"),
      publishedAt: new Date("2026-06-01T10:00:00Z"),
      createdBy: "seed",
      updatedBy: "seed",
      isDeleted: false,
    });

    await setDoc(doc(db, "events", "event-1"), {
      id: "event-1",
      moderationStatus: "approved",
      title: "Approved Event",
      summary: "Approved for registration test",
      sourceType: "organization",
      organizationId: "org-1",
      city: "Vienna",
      venue: "Community Hall",
      startDate: new Date("2027-01-15T10:00:00Z"),
      endDate: new Date("2027-01-15T11:00:00Z"),
      likeCount: 0,
      commentCount: 0,
      viewCount: 0,
      registeredCount: 0,
      createdAt: new Date("2026-06-01T10:00:00Z"),
      updatedAt: new Date("2026-06-01T10:00:00Z"),
      registrationState: "notRegistered",
      cancellationState: "active",
    });

    await setDoc(doc(db, "organizations", "org-1"), {
      id: "org-1",
      ownerId: "owner-id",
      adminIds: [],
      moderatorIds: [],
      moderationStatus: "approved",
      likeCount: 0,
      createdAt: new Date("2026-06-01T10:00:00Z"),
      updatedAt: new Date("2026-06-01T10:00:00Z"),
    });
  });
}

function user(uid, overrides = {}) {
  return {
    id: uid,
    fullName: "Test User",
    displayName: "Test User",
    city: "Vienna",
    email: `${uid}@example.com`,
    bio: "",
    globalRole: "user",
    isBlocked: false,
    blockState: "active",
    accountStatus: "active",
    warningCount: 0,
    canManageGuide: false,
    selectedFederalState: "Vienna",
    acceptedTermsAt: new Date("2026-06-01T09:00:00Z"),
    acceptedPrivacyAt: new Date("2026-06-01T09:00:00Z"),
    acceptedTermsVersion: "1",
    acceptedPrivacyVersion: "1",
    termsVersion: "1",
    privacyVersion: "1",
    communityMemberships: [],
    ...overrides,
  };
}

describe("email verification enforcement", () => {
  test("unverified user can create profile bootstrap document, but cannot write interaction content", async () => {
    const unverifiedDb = auth("pending-user", false);

    await assertSucceeds(setDoc(doc(unverifiedDb, "users", "pending-user"), user("pending-user")));

    await assertFails(setDoc(doc(unverifiedDb, "likes", "news-1_pending-user"), {
      id: "news-1_pending-user",
      userId: "pending-user",
      newsId: "news-1",
      createdAt: new Date("2026-06-09T10:00:00Z"),
    }));

    await assertFails(setDoc(doc(unverifiedDb, "users", "pending-user", "newsBookmarks", "news-1"), {
      id: "news-1",
      newsId: "news-1",
      userId: "pending-user",
    }));

    await assertFails(setDoc(doc(unverifiedDb, "registrations", "event_event-1_pending-user"), {
      id: "event_event-1_pending-user",
      eventId: "event-1",
      userId: "pending-user",
      registeredAt: new Date("2026-06-09T10:00:00Z"),
      createdAt: new Date("2026-06-09T10:00:00Z"),
    }));

    await assertFails(setDoc(doc(unverifiedDb, "news", "news-1", "comments", "comment-1"), {
      id: "comment-1",
      parentType: "news",
      parentId: "news-1",
      authorId: "pending-user",
      authorName: "Pending User",
      text: "Pending user comment",
      createdAt: new Date("2026-06-09T10:00:00Z"),
      isDeleted: false,
    }));

    await assertFails(setDoc(doc(unverifiedDb, "feedback", "feedback-pending"), {
      id: "feedback-pending",
      userId: "pending-user",
      userDisplayName: "Pending User",
      type: "question",
      subject: "Email verification",
      message: "Please review",
      status: "open",
      createdAt: new Date("2026-06-09T10:00:00Z"),
      updatedAt: new Date("2026-06-09T10:00:00Z"),
      lastMessageText: "Please review",
      lastMessageAt: new Date("2026-06-09T10:00:00Z"),
      lastMessageByUserId: "pending-user",
      lastMessageByRole: "user",
      unreadForOwner: true,
      unreadForUser: false,
    }));
  });

  test("verified user can write interaction and feedback content", async () => {
    const verifiedDb = auth("verified-user", true);

    await assertSucceeds(setDoc(doc(verifiedDb, "likes", "news-1_verified-user"), {
      id: "news-1_verified-user",
      userId: "verified-user",
      newsId: "news-1",
      createdAt: new Date("2026-06-09T11:00:00Z"),
    }));

    await assertSucceeds(setDoc(doc(verifiedDb, "users", "verified-user", "newsBookmarks", "news-1"), {
      id: "news-1",
      newsId: "news-1",
      userId: "verified-user",
    }));

    await assertSucceeds(setDoc(doc(verifiedDb, "registrations", "event_event-1_verified-user"), {
      id: "event_event-1_verified-user",
      eventId: "event-1",
      userId: "verified-user",
      registeredAt: new Date("2026-06-09T11:00:00Z"),
      createdAt: new Date("2026-06-09T11:00:00Z"),
    }));

    await assertSucceeds(setDoc(doc(verifiedDb, "news", "news-1", "comments", "comment-verified"), {
      id: "comment-verified",
      parentType: "news",
      parentId: "news-1",
      authorId: "verified-user",
      authorName: "Verified User",
      text: "Verified user comment",
      createdAt: new Date("2026-06-09T11:00:00Z"),
      isDeleted: false,
    }));

    await assertSucceeds(setDoc(doc(verifiedDb, "feedback", "feedback-verified"), {
      id: "feedback-verified",
      userId: "verified-user",
      userDisplayName: "Verified User",
      type: "suggestion",
      subject: "Verified suggestion",
      message: "Verified feedback message",
      status: "open",
      createdAt: new Date("2026-06-09T11:00:00Z"),
      updatedAt: new Date("2026-06-09T11:00:00Z"),
      lastMessageText: "Verified feedback message",
      lastMessageAt: new Date("2026-06-09T11:00:00Z"),
      lastMessageByUserId: "verified-user",
      lastMessageByRole: "user",
      unreadForOwner: true,
      unreadForUser: false,
    }));
  });

  test("owner/admin style management writes are still gated by verified email", async () => {
    const unverifiedOwnerDb = auth("owner-user", false);
    const verifiedOwnerDb = auth("owner-user", true);

    await assertFails(setDoc(doc(unverifiedOwnerDb, "organizations", "org-2"), {
      id: "org-2",
      name: "New Org",
      description: "Draft org",
      city: "Vienna",
      moderationStatus: "pendingReview",
      adminIds: [],
      moderatorIds: [],
      submittedByUserId: "owner-user",
      submittedByDisplayName: "Owner User",
      submittedAt: new Date("2026-06-09T12:00:00Z"),
      updatedAt: new Date("2026-06-09T12:00:00Z"),
      likeCount: 0,
      viewCount: 0,
      likeState: "notLiked",
      subscriberCount: 0,
      eventsHeldCount: 0,
      volunteersCount: 0,
      helpedPeopleCount: 0,
      ownerId: "",
      email: "owner@example.com",
    }));

    await assertSucceeds(updateDoc(doc(verifiedOwnerDb, "organizations", "org-1"), {
      name: "Verified owner managed organization",
    }));
  });

  test("anonymous users still keep public read access, but cannot write interaction docs", async () => {
    const publicDb = unauthenticated();

    await assertSucceeds(getDoc(doc(publicDb, "news", "news-1")));
    await assertSucceeds(getDoc(doc(publicDb, "organizations", "org-1")));
    await assertFails(setDoc(doc(publicDb, "likes", "news-1_anonymous"), {
      id: "news-1_anonymous",
      userId: "anonymous",
      newsId: "news-1",
      createdAt: new Date("2026-06-09T11:00:00Z"),
    }));
  });
});
