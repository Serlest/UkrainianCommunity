import {after, before, beforeEach, describe, test} from "node:test";
import {readFileSync} from "node:fs";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, getDoc, serverTimestamp, setDoc} from "firebase/firestore";

const PROJECT_ID = "ukrainian-community-canonical-visibility-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const USER_ID = "verified-user";

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
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", USER_ID), {
      id: USER_ID,
      globalRole: "user",
      accountStatus: "active",
      blockState: "active",
    });
    for (const moderationStatus of ["approved", "pendingReview"]) {
      await setDoc(doc(db, "news", `${moderationStatus}-news`), {
        id: `${moderationStatus}-news`,
        moderationStatus,
      });
      await setDoc(doc(db, "events", `${moderationStatus}-event`), {
        id: `${moderationStatus}-event`,
        moderationStatus,
      });
      await setDoc(doc(db, "organizations", `${moderationStatus}-organization`), {
        id: `${moderationStatus}-organization`,
        moderationStatus,
      });
    }
    await setDoc(doc(db, "news", "event_collision"), {
      id: "event_collision",
      moderationStatus: "approved",
    });
    await setDoc(doc(db, "events", "collision"), {
      id: "collision",
      moderationStatus: "approved",
    });
    await setDoc(doc(db, "organizations", "follow_collision"), {
      id: "follow_collision",
      moderationStatus: "approved",
    });
    await setDoc(doc(db, "organizations", "collision"), {
      id: "collision",
      moderationStatus: "approved",
    });
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function authenticatedDb() {
  return testEnv.authenticatedContext(USER_ID, {
    email: `${USER_ID}@example.com`,
    email_verified: true,
  }).firestore();
}

function likeReferenceAndData(db, kind, targetId) {
  if (kind === "news") {
    const id = `${targetId}_${USER_ID}`;
    return [doc(db, "likes", id), {
      id,
      userId: USER_ID,
      newsId: targetId,
      createdAt: serverTimestamp(),
    }];
  }
  if (kind === "event") {
    const id = `event_${targetId}_${USER_ID}`;
    return [doc(db, "likes", id), {
      id,
      userId: USER_ID,
      eventId: targetId,
      createdAt: serverTimestamp(),
    }];
  }
  if (kind === "organization") {
    const id = `organization_${targetId}_${USER_ID}`;
    return [doc(db, "likes", id), {
      id,
      userId: USER_ID,
      organizationId: targetId,
      createdAt: serverTimestamp(),
    }];
  }

  const id = `organization_follow_${targetId}_${USER_ID}`;
  return [doc(db, "likes", id), {
    id,
    userId: USER_ID,
    subscribedOrganizationId: targetId,
    createdAt: serverTimestamp(),
  }];
}

function bookmarkReferenceAndData(db, kind, targetId) {
  const collectionName = kind === "news" ?
    "newsBookmarks" :
    kind === "event" ? "eventBookmarks" : "organizationBookmarks";
  const targetField = kind === "news" ?
    "newsId" :
    kind === "event" ? "eventId" : "organizationId";
  return [doc(db, "users", USER_ID, collectionName, targetId), {
    id: targetId,
    [targetField]: targetId,
    userId: USER_ID,
    createdAt: serverTimestamp(),
  }];
}

function commentReferenceAndData(db, kind, targetId, commentId) {
  const collectionName = kind === "news" ? "news" : "events";
  return [doc(db, collectionName, targetId, "comments", commentId), {
    id: commentId,
    parentType: kind,
    parentId: targetId,
    authorId: USER_ID,
    authorName: "Verified User",
    text: "Canonical visibility test comment",
    createdAt: serverTimestamp(),
    isDeleted: false,
  }];
}

describe("canonical target visibility for interactions", () => {
  test("approved canonical targets accept likes, follows, and bookmarks", async () => {
    const db = authenticatedDb();
    for (const [kind, targetId] of [
      ["news", "approved-news"],
      ["event", "approved-event"],
      ["organization", "approved-organization"],
      ["follow", "approved-organization"],
    ]) {
      const [reference, data] = likeReferenceAndData(db, kind, targetId);
      await assertSucceeds(setDoc(reference, data));
    }
    for (const [kind, targetId] of [
      ["news", "approved-news"],
      ["event", "approved-event"],
      ["organization", "approved-organization"],
    ]) {
      const [reference, data] = bookmarkReferenceAndData(db, kind, targetId);
      await assertSucceeds(setDoc(reference, data));
    }
  });

  test("pending targets reject likes, follows, bookmarks, and comments", async () => {
    const db = authenticatedDb();
    for (const [kind, targetId] of [
      ["news", "pendingReview-news"],
      ["event", "pendingReview-event"],
      ["organization", "pendingReview-organization"],
      ["follow", "pendingReview-organization"],
    ]) {
      const [reference, data] = likeReferenceAndData(db, kind, targetId);
      await assertFails(setDoc(reference, data));
    }
    for (const [kind, targetId] of [
      ["news", "pendingReview-news"],
      ["event", "pendingReview-event"],
      ["organization", "pendingReview-organization"],
    ]) {
      const [reference, data] = bookmarkReferenceAndData(db, kind, targetId);
      await assertFails(setDoc(reference, data));
    }
    for (const [kind, targetId] of [
      ["news", "pendingReview-news"],
      ["event", "pendingReview-event"],
    ]) {
      const [reference, data] = commentReferenceAndData(
        db,
        kind,
        targetId,
        `pending-${kind}-comment`
      );
      await assertFails(setDoc(reference, data));
    }
  });

  test("missing targets reject orphan likes and follows", async () => {
    const db = authenticatedDb();
    for (const [kind, targetId] of [
      ["news", "missing-news"],
      ["event", "missing-event"],
      ["organization", "missing-organization"],
      ["follow", "missing-organization"],
    ]) {
      const [reference, data] = likeReferenceAndData(db, kind, targetId);
      await assertFails(setDoc(reference, data));
    }
  });

  test("reserved target prefixes cannot create cross-kind like ID collisions", async () => {
    const db = authenticatedDb();
    for (const [kind, targetId] of [
      ["news", "event_collision"],
      ["organization", "follow_collision"],
    ]) {
      const [reference, data] = likeReferenceAndData(db, kind, targetId);
      await assertFails(setDoc(reference, data));
    }
  });

  test("missing targets reject orphan bookmarks and comments", async () => {
    const db = authenticatedDb();
    for (const [kind, targetId] of [
      ["news", "missing-news"],
      ["event", "missing-event"],
      ["organization", "missing-organization"],
    ]) {
      const [reference, data] = bookmarkReferenceAndData(db, kind, targetId);
      await assertFails(setDoc(reference, data));
    }
    for (const [kind, targetId] of [
      ["news", "missing-news"],
      ["event", "missing-event"],
    ]) {
      const [reference, data] = commentReferenceAndData(
        db,
        kind,
        targetId,
        `orphan-${kind}-comment`
      );
      await assertFails(setDoc(reference, data));
    }
  });

  test("counter transition internals are never client-accessible", async () => {
    const db = authenticatedDb();
    for (const collectionName of [
      "counterAggregationSourceStates",
      "counterAggregationBaselines",
      "counterAggregationDeadLetters",
    ]) {
      const reference = doc(db, collectionName, "forged-internal-record");
      await assertFails(getDoc(reference));
      await assertFails(setDoc(reference, {
        sourcePathHash: "forged-hash",
        isActive: true,
        lastEventId: "forged-event",
        lastEventTime: serverTimestamp(),
      }));
    }
  });
});
