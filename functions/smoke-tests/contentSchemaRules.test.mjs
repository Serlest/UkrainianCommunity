import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteDoc, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-content-schema-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const NOW = new Date("2026-08-25T12:00:00Z");

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: readFileSync(new URL(RULES_PATH, import.meta.url), "utf8")},
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users", "owner"), user("owner", "owner")),
      setDoc(doc(db, "users", "app-admin"), user("app-admin", "admin")),
      setDoc(doc(db, "users", "org-owner"), user("org-owner")),
      setDoc(doc(db, "users", "regular-user"), user("regular-user")),
      setDoc(doc(db, "organizations", "org-1"), organization()),
      setDoc(doc(db, "news", "seed-news"), news("seed-news", "org-owner")),
      setDoc(doc(db, "events", "seed-event"), event("seed-event", "org-owner")),
      setDoc(doc(db, "news", "legacy-news"), (() => {
        const value = news("legacy-news", "org-owner");
        delete value.authorId;
        return value;
      })()),
      setDoc(doc(db, "events", "legacy-event"), (() => {
        const value = event("legacy-event", "org-owner");
        delete value.requiresRegistration;
        return value;
      })()),
      setDoc(doc(db, "news", "seed-news", "comments", "news-comment"), {
        authorId: "regular-user",
      }),
      setDoc(doc(db, "events", "seed-event", "comments", "event-comment"), {
        authorId: "regular-user",
      }),
      setDoc(doc(db, "organizations", "org-1", "comments", "organization-comment"), {
        authorId: "regular-user",
      }),
      setDoc(doc(db, "feedback", "feedback-1"), {
        id: "feedback-1",
        userId: "regular-user",
        status: "closed",
      }),
      setDoc(doc(db, "feedback", "dsa-feedback-1"), {
        id: "dsa-feedback-1",
        userId: "regular-user",
        status: "open",
        dsaCase: {caseNumber: "UC-20260825-TEST", status: "submitted"},
      }),
      setDoc(doc(db, "dsaCases", "dsa-feedback-1"), {
        caseNumber: "UC-20260825-TEST",
        accessTokenHash: "server-only",
      }),
      setDoc(doc(db, "users", "org-owner", "dsaStatements", "dsa-feedback-1"), {
        id: "dsa-feedback-1",
        caseNumber: "UC-20260825-TEST",
        status: "decided",
      }),
    ]);
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

function db(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  }).firestore();
}

function user(uid, globalRole = "user") {
  return {id: uid, globalRole, accountStatus: "active", blockState: "active"};
}

function organization() {
  return {
    id: "org-1",
    name: "Schema Organization",
    description: "Canonical organization document",
    city: "Vienna",
    ownerId: "org-owner",
    adminIds: [],
    moderatorIds: [],
    moderationStatus: "approved",
    subscriberCount: 0,
    eventsHeldCount: 0,
    volunteersCount: 0,
    helpedPeopleCount: 0,
    likeCount: 0,
    likeState: "notLiked",
    createdAt: NOW,
    updatedAt: NOW,
  };
}

function news(id, authorId) {
  return {
    id,
    title: "Canonical news",
    subtitle: "A bounded subtitle",
    body: "A complete article body",
    sourceType: "organization",
    organizationId: "org-1",
    authorId,
    authorName: "Organization Owner",
    publishedAt: NOW,
    createdAt: NOW,
    updatedAt: NOW,
    moderationStatus: "approved",
    likeCount: 0,
    likeState: "notLiked",
    viewCount: 0,
    commentCount: 0,
    tags: ["community"],
  };
}

function event(id, authorId) {
  return {
    id,
    title: "Canonical event",
    summary: "A bounded summary",
    details: "Complete event details",
    sourceType: "organization",
    organizationId: "org-1",
    authorId,
    city: "Vienna",
    venue: "Community Hall",
    startDate: new Date("2026-09-10T17:00:00Z"),
    endDate: new Date("2026-09-10T19:00:00Z"),
    createdAt: NOW,
    updatedAt: NOW,
    requiresRegistration: true,
    price: 0,
    registeredCount: 0,
    moderationStatus: "approved",
    registrationState: "notRegistered",
    likeCount: 0,
    likeState: "notLiked",
    viewCount: 0,
    commentCount: 0,
    visibility: "public",
    isAllDay: false,
  };
}

describe("strict client content schemas", () => {
  test("organization owner can create canonical news and events", async () => {
    await assertSucceeds(setDoc(doc(db("org-owner"), "news", "new-news"), news("new-news", "org-owner")));
    await assertSucceeds(setDoc(doc(db("org-owner"), "events", "new-event"), event("new-event", "org-owner")));
  });

  test("organization owner can update canonical news and events", async () => {
    await assertSucceeds(updateDoc(doc(db("org-owner"), "news", "seed-news"), {
      title: "Updated canonical news",
      updatedAt: new Date("2026-08-25T12:10:00Z"),
    }));
    await assertSucceeds(updateDoc(doc(db("org-owner"), "events", "seed-event"), {
      summary: "Updated bounded summary",
      updatedAt: new Date("2026-08-25T12:10:00Z"),
    }));
    await assertSucceeds(updateDoc(doc(db("org-owner"), "news", "legacy-news"), {
      imageURL: "https://example.com/news.jpg",
      updatedAt: new Date("2026-08-25T12:10:00Z"),
    }));
    await assertSucceeds(updateDoc(doc(db("org-owner"), "events", "legacy-event"), {
      imageURL: "https://example.com/event.jpg",
      updatedAt: new Date("2026-08-25T12:10:00Z"),
    }));
  });

  test("unknown fields, forged identity, and invalid dates fail closed", async () => {
    await assertFails(setDoc(doc(db("org-owner"), "news", "extra-news"), {
      ...news("extra-news", "org-owner"),
      privileged: true,
    }));
    await assertFails(setDoc(doc(db("org-owner"), "news", "forged-news"), news("different-id", "org-owner")));
    await assertFails(setDoc(doc(db("org-owner"), "events", "invalid-event"), {
      ...event("invalid-event", "org-owner"),
      endDate: new Date("2026-09-10T16:00:00Z"),
    }));
  });

  test("comments require an exact parent, author, and mirrored body", async () => {
    const valid = {
      id: "comment-1",
      parentType: "news",
      parentId: "seed-news",
      authorId: "regular-user",
      authorName: "Regular User",
      text: "Useful comment",
      body: "Useful comment",
      createdAt: NOW,
      isDeleted: false,
      moderationStatus: "approved",
    };
    await assertSucceeds(setDoc(doc(db("regular-user"), "news", "seed-news", "comments", "comment-1"), valid));
    await assertFails(setDoc(doc(db("regular-user"), "news", "seed-news", "comments", "comment-2"), {
      ...valid,
      id: "comment-2",
      body: "Different body",
    }));
  });
});

describe("platform moderation and server-owned deletion", () => {
  test("App Admin can update status and timestamp, but cannot rewrite content", async () => {
    await assertSucceeds(updateDoc(doc(db("app-admin"), "news", "seed-news"), {
      moderationStatus: "archived",
      updatedAt: new Date("2026-08-25T12:05:00Z"),
    }));
    await assertSucceeds(updateDoc(doc(db("app-admin"), "events", "seed-event"), {
      moderationStatus: "archived",
      updatedAt: new Date("2026-08-25T12:05:00Z"),
    }));
    await assertFails(updateDoc(doc(db("app-admin"), "events", "seed-event"), {
      title: "Admin rewrite",
    }));
    await assertFails(updateDoc(doc(db("regular-user"), "news", "seed-news"), {
      moderationStatus: "archived",
      updatedAt: new Date("2026-08-25T12:05:00Z"),
    }));
  });

  test("feedback documents cannot be deleted directly by owner or submitter", async () => {
    await assertFails(deleteDoc(doc(db("owner"), "feedback", "feedback-1")));
    await assertFails(deleteDoc(doc(db("regular-user"), "feedback", "feedback-1")));
  });

  test("DSA cases are server-only and cannot be closed without the decision function", async () => {
    await assertFails(updateDoc(doc(db("owner"), "feedback", "dsa-feedback-1"), {
      status: "closed",
      updatedAt: new Date("2026-08-25T12:05:00Z"),
    }));
    await assertFails(setDoc(doc(db("owner"), "dsaCases", "owner-forged"), {caseNumber: "forged"}));
    await assertFails(updateDoc(doc(db("owner"), "dsaCases", "dsa-feedback-1"), {status: "decided"}));
  });

  test("only the affected user can read their sanitized DSA statement and nobody can forge it", async () => {
    const statement = doc(db("org-owner"), "users", "org-owner", "dsaStatements", "dsa-feedback-1");
    await assertSucceeds(getDoc(statement));
    await assertFails(getDoc(doc(db("regular-user"), "users", "org-owner", "dsaStatements", "dsa-feedback-1")));
    await assertFails(getDoc(doc(db("owner"), "users", "org-owner", "dsaStatements", "dsa-feedback-1")));
    await assertFails(updateDoc(statement, {status: "noAction"}));
    await assertFails(setDoc(doc(db("org-owner"), "users", "org-owner", "dsaStatements", "forged"), {
      id: "forged",
      status: "decided",
    }));
  });

  test("comment authors cannot delete their own comments, but moderators can", async () => {
    await assertFails(deleteDoc(doc(
      db("regular-user"),
      "news",
      "seed-news",
      "comments",
      "news-comment"
    )));
    await assertFails(deleteDoc(doc(
      db("regular-user"),
      "events",
      "seed-event",
      "comments",
      "event-comment"
    )));
    await assertFails(deleteDoc(doc(
      db("regular-user"),
      "organizations",
      "org-1",
      "comments",
      "organization-comment"
    )));

    await assertSucceeds(deleteDoc(doc(
      db("app-admin"),
      "news",
      "seed-news",
      "comments",
      "news-comment"
    )));
    await assertSucceeds(deleteDoc(doc(
      db("app-admin"),
      "events",
      "seed-event",
      "comments",
      "event-comment"
    )));
    await assertSucceeds(deleteDoc(doc(
      db("org-owner"),
      "organizations",
      "org-1",
      "comments",
      "organization-comment"
    )));
  });

  test("published comments are immutable", async () => {
    await assertFails(updateDoc(doc(
      db("regular-user"),
      "news",
      "seed-news",
      "comments",
      "news-comment"
    ), { text: "Changed", body: "Changed", updatedAt: NOW }));
    await assertFails(updateDoc(doc(
      db("regular-user"),
      "events",
      "seed-event",
      "comments",
      "event-comment"
    ), { text: "Changed", body: "Changed", updatedAt: NOW }));
    await assertFails(updateDoc(doc(
      db("regular-user"),
      "organizations",
      "org-1",
      "comments",
      "organization-comment"
    ), { text: "Changed", body: "Changed", updatedAt: NOW }));
  });
});
