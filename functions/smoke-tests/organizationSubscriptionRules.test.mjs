import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-organization-subscription-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
const ORGANIZATION_ID = "org-private-subscribers";
const OTHER_ORGANIZATION_ID = "org-other";
const SUBSCRIBER_ID = "subscriber-user";
const SUBSCRIPTION_ID =
  `organization_follow_${ORGANIZATION_ID}_${SUBSCRIBER_ID}`;

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

function auth(uid, emailVerified = true) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
  }).firestore();
}

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}

function user(uid, overrides = {}) {
  return {
    id: uid,
    globalRole: "user",
    accountStatus: "active",
    blockState: "active",
    ...overrides,
  };
}

function organization(id, ownerId, overrides = {}) {
  return {
    id,
    ownerId,
    adminIds: [],
    moderatorIds: [],
    moderationStatus: "approved",
    ...overrides,
  };
}

function subscription(organizationId, userId) {
  return {
    id: `organization_follow_${organizationId}_${userId}`,
    userId,
    subscribedOrganizationId: organizationId,
    createdAt: new Date("2026-08-01T10:00:00Z"),
  };
}

function subscriptionsFor(db, organizationId) {
  return query(
    collection(db, "likes"),
    where("subscribedOrganizationId", "==", organizationId)
  );
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    const users = [
      user(SUBSCRIBER_ID),
      user("other-subscriber"),
      user("unrelated-user"),
      user("organization-owner"),
      user("other-owner"),
      user("organization-admin"),
      user("organization-moderator"),
      user("app-admin", {globalRole: "admin"}),
      user("app-owner", {globalRole: "owner"}),
      user("new-subscriber"),
    ];
    await Promise.all(users.map((value) =>
      setDoc(doc(db, "users", value.id), value)
    ));

    await setDoc(
      doc(db, "organizations", ORGANIZATION_ID),
      organization(ORGANIZATION_ID, "organization-owner", {
        adminIds: ["organization-admin"],
        moderatorIds: ["organization-moderator"],
      })
    );
    await setDoc(
      doc(db, "organizations", OTHER_ORGANIZATION_ID),
      organization(OTHER_ORGANIZATION_ID, "other-owner")
    );

    await setDoc(
      doc(db, "likes", SUBSCRIPTION_ID),
      subscription(ORGANIZATION_ID, SUBSCRIBER_ID)
    );
    await setDoc(
      doc(db, "likes", `organization_follow_${ORGANIZATION_ID}_other-subscriber`),
      subscription(ORGANIZATION_ID, "other-subscriber")
    );
    await setDoc(
      doc(db, "likes", `organization_follow_${OTHER_ORGANIZATION_ID}_other-subscriber`),
      subscription(OTHER_ORGANIZATION_ID, "other-subscriber")
    );
  });
}

describe("organization subscriber privacy", () => {
  test("guest cannot read a subscription document or subscriber query", async () => {
    const db = unauthenticated();

    await assertFails(getDoc(doc(db, "likes", SUBSCRIPTION_ID)));
    await assertFails(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
  });

  test("unrelated verified user cannot read subscriber identities", async () => {
    const db = auth("unrelated-user");

    await assertFails(getDoc(doc(db, "likes", SUBSCRIPTION_ID)));
    await assertFails(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
  });

  test("subscriber can read only their own subscription records", async () => {
    const db = auth(SUBSCRIBER_ID);

    await assertSucceeds(getDoc(doc(db, "likes", SUBSCRIPTION_ID)));
    await assertSucceeds(getDocs(query(
      collection(db, "likes"),
      where("userId", "==", SUBSCRIBER_ID)
    )));
    await assertFails(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
  });

  test("organization owner can query that organization's subscribers only", async () => {
    const db = auth("organization-owner");

    await assertSucceeds(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
    await assertFails(getDocs(collection(db, "likes")));
    await assertFails(getDocs(subscriptionsFor(db, OTHER_ORGANIZATION_ID)));
  });

  test("organization admin and moderator cannot query subscriber identities", async () => {
    await assertFails(getDocs(subscriptionsFor(
      auth("organization-admin"),
      ORGANIZATION_ID
    )));
    await assertFails(getDocs(subscriptionsFor(
      auth("organization-moderator"),
      ORGANIZATION_ID
    )));
  });

  test("App Admin has no organization override", async () => {
    const db = auth("app-admin");
    await assertFails(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
  });

  test("App Owner retains the platform override", async () => {
    const db = auth("app-owner");

    await assertSucceeds(getDocs(subscriptionsFor(db, ORGANIZATION_ID)));
    await assertSucceeds(getDocs(collection(db, "likes")));
  });

  test("verified user can still subscribe and unsubscribe themselves", async () => {
    const db = auth("new-subscriber");
    const id =
      `organization_follow_${ORGANIZATION_ID}_new-subscriber`;
    const reference = doc(db, "likes", id);

    await assertSucceeds(setDoc(
      reference,
      subscription(ORGANIZATION_ID, "new-subscriber")
    ));
    await assertSucceeds(deleteDoc(reference));
  });
});
