import {after, before, beforeEach, describe, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteField, doc, getDoc, setDoc, updateDoc} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-organization-creation-proof-rules";
const RULES_PATH = "../../Firebase/firestore.rules";
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
    await setDoc(doc(db, "users", "creator"), {
      id: "creator",
      globalRole: "user",
      accountStatus: "active",
      blockState: "active",
    });
    await setDoc(doc(db, "legalDocuments", "organizationRules"), {
      activeVersion: "2026.10",
      requiresAcceptance: true,
    });
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

function creatorDb() {
  return testEnv.authenticatedContext("creator", {
    email: "creator@example.com",
    email_verified: true,
  }).firestore();
}

function request(id, name = "Ukrainian Shop") {
  return {
    id,
    name,
    description: "A verified organization request",
    city: "Innsbruck",
    federalState: "tirol",
    ownerId: "",
    adminIds: [],
    moderatorIds: [],
    subscriberCount: 0,
    eventsHeldCount: 0,
    volunteersCount: 0,
    helpedPeopleCount: 0,
    likeCount: 0,
    likeState: "notLiked",
    moderationStatus: "pendingReview",
    submittedByUserId: "creator",
    submittedAt: new Date(),
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

async function seedProof(id, overrides = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "organizationCreationProofs", id), {
      organizationId: id,
      organizationName: "Ukrainian Shop",
      userId: "creator",
      documentType: "organizationRules",
      version: "2026.10",
      acceptedAt: new Date(),
      expiresAt: new Date("2099-01-01T00:00:00Z"),
      ...overrides,
    });
  });
}


// Mirrors the iOS repository's populated create/update payload. The former
// sparse fixture and directory-only tests missed the combined expression cost
// of legal proof + profile + contact/language fields on ordinary-user creation.
function populatedRequest(id) {
  return {
    ...request(id),
    localizations: {
      uk: {
        name: "Ukrainian Shop", shortDescription: "Українські товари у Відні",
        fullDescription: "Повний опис українською", missionStatement: "Підтримуємо громаду",
        serviceArea: "Вся Австрія", specialHoursNote: "За домовленістю",
        services: ["Доставка", "Самовивіз"], currentOfferTitle: "Знижка",
        currentOfferDetails: "Діє цього тижня",
      },
      de: {
        name: "Ukrainischer Shop", shortDescription: "Ukrainische Produkte in Wien",
        fullDescription: "Vollständige Beschreibung auf Deutsch", missionStatement: "Wir unterstützen die Community",
        serviceArea: "Ganz Österreich", specialHoursNote: "Nach Vereinbarung",
        services: ["Lieferung", "Abholung"], currentOfferTitle: "Rabatt",
        currentOfferDetails: "Diese Woche gültig",
      },
    },
    shortDescription: "Італійський одяг на щодень 🇮🇹",
    fullDescription: "A fully populated organization request",
    regionScope: "federalState",
    organizationType: "retail",
    languages: Array.from({length: 12}, (_, i) => `Language ${i}`),
    socialLinks: {instagram: "https://example.com/instagram"},
    submittedByDisplayName: "Request creator",
    contactEmail: "shop@example.com", email: "shop@example.com",
    website: "https://example.com", phone: "+4312345678",
    address: "Example street 1", latitude: 48.3, longitude: 14.3,
    foundedYear: 2026, foundedMonth: 8,
    telegramURL: "https://t.me/example", donationURL: "https://example.com/donate",
    facebookURL: "https://example.com/facebook", instagramURL: "https://example.com/instagram",
    whatsappURL: "https://wa.me/4312345678", youtubeURL: "https://example.com/youtube",
    linkedinURL: "https://example.com/linkedin", missionStatement: "Mission", contactPerson: "Contact",
    directoryProfile: {
      profileKind: "business", secondaryCategories: ["retail", "culture"],
      serviceModes: ["online", "inStore", "pickup", "delivery", "atClient"],
      serviceArea: "Austria", regularHours: {monday: "09:00-18:00", tuesday: "09:00-18:00",
        wednesday: "09:00-18:00", thursday: "09:00-18:00", friday: "09:00-18:00",
        saturday: "09:00-18:00", sunday: "closed"},
      specialHoursNote: "By appointment", services: Array.from({length: 8}, (_, i) => `Service ${i}`),
      orderURL: "https://example.com/order", bookingURL: "https://example.com/book",
      currentOfferTitle: "Offer", currentOfferDetails: "Details",
      currentOfferURL: "https://example.com/offer", currentOfferValidUntil: new Date("2027-01-01"),
    },
  };
}

describe("organization creation rules evidence", () => {
  test("requires a current organization-bound proof", async () => {
    const db = creatorDb();
    await assertFails(setDoc(doc(db, "organizations", "missing-proof"), request("missing-proof")));

    await seedProof("wrong-version", {version: "2026.9"});
    await assertFails(setDoc(doc(db, "organizations", "wrong-version"), request("wrong-version")));

    await seedProof("wrong-name");
    await assertFails(setDoc(
      doc(db, "organizations", "wrong-name"),
      request("wrong-name", "Changed name")
    ));

    await seedProof("valid-proof");
    await assertSucceeds(setDoc(doc(db, "organizations", "valid-proof"), request("valid-proof")));
  });

  test("ordinary user creates a full profile with legal proof and then saves its logo", async () => {
    const id = "full-profile";
    await seedProof(id);
    const ref = doc(creatorDb(), "organizations", id);
    await assertSucceeds(setDoc(ref, populatedRequest(id)));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, {
      imageURL: "https://example.com/logo.jpg", logoURL: "https://example.com/logo.jpg",
      coverURL: "https://example.com/cover.jpg", updatedAt: new Date(),
    }));
    await assertFails(getDoc(doc(testEnv.unauthenticatedContext().firestore(), "organizations", id)));
    await assertFails(updateDoc(ref, {moderationStatus: "approved"}));
    await assertFails(updateDoc(ref, {ownerId: "creator"}));
  });

  test("fully populated direct publication remains exclusive to the app owner", async () => {
    for (const role of ["user", "admin", "owner"]) {
      await testEnv.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), "users", "creator"), {globalRole: role}));
      const pendingID = `pending-${role}`;
      await seedProof(pendingID);
      await assertSucceeds(setDoc(doc(creatorDb(), "organizations", pendingID), populatedRequest(pendingID)));
      const approvedID = `approved-${role}`;
      await seedProof(approvedID);
      const write = setDoc(doc(creatorDb(), "organizations", approvedID), {
        ...populatedRequest(approvedID), moderationStatus: "approved",
      });
      if (role === "owner") await assertSucceeds(write);
      else await assertFails(write);
    }
  });

  test("populated requests still reject privilege changes, forged proof and invalid schema", async () => {
    const cases = [
      {ownerId: "creator"}, {adminIds: ["creator"]}, {moderatorIds: ["creator"]},
      {subscriberCount: 1}, {likeCount: 1}, {submittedByUserId: "another-user"},
      {name: "Name not covered by the proof"}, {moderationStatus: "rejected"},
      {website: "x".repeat(2049)}, {languages: Array(13).fill("de")},
      {directoryProfile: {profileKind: "unsupported"}}, {unexpectedField: true},
    ];
    for (const [index, overrides] of cases.entries()) {
      const id = `invalid-full-${index}`;
      await seedProof(id);
      await assertFails(setDoc(doc(creatorDb(), "organizations", id), {...populatedRequest(id), ...overrides}));
    }
    for (const [id, overrides] of [
      ["expired-proof", {expiresAt: new Date("2000-01-01")}],
      ["another-user-proof", {userId: "someone-else"}],
    ]) {
      await seedProof(id, overrides);
      await assertFails(setDoc(doc(creatorDb(), "organizations", id), populatedRequest(id)));
    }
  });

  test("full-profile edits preserve review decisions and allow a cleared resubmission", async () => {
    const id = "reviewed-full";
    await testEnv.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), "organizations", id), {
      ...populatedRequest(id), moderationStatus: "needsRevision",
      reviewMessage: "Please correct the address", rejectionReason: "Incorrect address",
    }));
    const ref = doc(creatorDb(), "organizations", id);
    await assertSucceeds(updateDoc(ref, {address: "Corrected address", updatedAt: new Date()}));
    await assertFails(updateDoc(ref, {reviewMessage: "Changed by requester"}));
    await assertFails(updateDoc(ref, {moderationStatus: "pendingReview"}));
    await assertSucceeds(updateDoc(ref, {
      moderationStatus: "pendingReview", reviewMessage: deleteField(),
      rejectionReason: deleteField(), submittedAt: new Date(), updatedAt: new Date(),
    }));
    await assertFails(updateDoc(ref, {reviewMessage: null}));
    await assertFails(updateDoc(ref, {likeCount: 1}));
    await assertFails(updateDoc(ref, {adminIds: ["creator"]}));
  });

  test("organization owner can update the complete approved profile without schema duplication", async () => {
    const id = "approved-full-edit";
    await testEnv.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), "organizations", id), {
      ...populatedRequest(id), moderationStatus: "approved", ownerId: "creator",
    }));
    const ref = doc(creatorDb(), "organizations", id);
    await assertSucceeds(updateDoc(ref, {website: "https://example.com/new", updatedAt: new Date()}));
    await assertFails(updateDoc(ref, {ownerId: "someone-else"}));
    await assertFails(updateDoc(ref, {directoryProfile: {profileKind: "unsupported"}}));
  });

  test("full-profile creation still requires a verified active account", async () => {
    await seedProof("unverified");
    const unverified = testEnv.authenticatedContext("creator", {email_verified: false}).firestore();
    await assertFails(setDoc(doc(unverified, "organizations", "unverified"), populatedRequest("unverified")));
    await seedProof("blocked");
    await testEnv.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), "users", "creator"), {blockState: "bannedPermanent"}));
    await assertFails(setDoc(doc(creatorDb(), "organizations", "blocked"), populatedRequest("blocked")));
  });

  for (const photoCount of [0, 1, 30]) {
    test(`gallery counter ${photoCount} permits profile edits but stays server-owned`, async () => {
      const id = `gallery-profile-${photoCount}`;
      await testEnv.withSecurityRulesDisabled(async c => {
        const db = c.firestore();
        await setDoc(doc(db, "organizations", id), {
          ...populatedRequest(id), moderationStatus: "approved", ownerId: "creator",
          adminIds: ["organization-admin"], photoCount,
        });
        for (const uid of ["organization-admin", "outsider"]) {
          await setDoc(doc(db, "users", uid), {
            id: uid, globalRole: "user", accountStatus: "active", blockState: "active",
          });
        }
      });
      for (const uid of ["creator", "organization-admin"]) {
        const db = testEnv.authenticatedContext(uid, {email_verified: true}).firestore();
        const ref = doc(db, "organizations", id);
        await assertSucceeds(updateDoc(ref, {website: "https://example.com/edited", updatedAt: new Date()}));
        if ((await getDoc(ref)).data().photoCount !== photoCount) throw new Error("Gallery count changed");
        for (const patch of [
          {photoCount: photoCount + 1}, {photoCount: deleteField()}, {photoCount: null},
          {ownerId: "outsider"}, {adminIds: ["outsider"]}, {moderationStatus: "rejected"},
          {submittedAt: new Date("2000-01-01")}, {reviewMessage: "Forged decision"},
        ]) await assertFails(updateDoc(ref, patch));
      }
      for (const db of [
        testEnv.unauthenticatedContext().firestore(),
        testEnv.authenticatedContext("outsider", {email_verified: true}).firestore(),
        testEnv.authenticatedContext("creator", {email_verified: false}).firestore(),
      ]) await assertFails(updateDoc(doc(db, "organizations", id), {website: "https://example.com/forbidden"}));
    });
  }

  test("clients cannot create a gallery counter, including zero or direct owner publication", async () => {
    for (const role of ["user", "owner"]) {
      await testEnv.withSecurityRulesDisabled(c => updateDoc(doc(c.firestore(), "users", "creator"), {globalRole: role}));
      for (const [index, photoCount] of [0, 1, -1, 1.5, "1", null].entries()) {
        const id = `forged-counter-${role}-${index}`;
        await seedProof(id);
        await assertFails(setDoc(doc(creatorDb(), "organizations", id), {
          ...populatedRequest(id), photoCount, moderationStatus: role === "owner" ? "approved" : "pendingReview",
        }));
      }
    }
  });

  test("malformed server counters and unknown fields still fail closed", async () => {
    for (const [index, extra] of [
      {photoCount: -1}, {photoCount: 1.5}, {photoCount: "1"}, {photoCount: null},
      {photoCount: 1, unexpectedField: true},
    ].entries()) {
      const id = `invalid-gallery-${index}`;
      await testEnv.withSecurityRulesDisabled(c => setDoc(doc(c.firestore(), "organizations", id), {
        ...populatedRequest(id), moderationStatus: "approved", ownerId: "creator", ...extra,
      }));
      await assertFails(updateDoc(doc(creatorDb(), "organizations", id), {website: "https://example.com/edited"}));
    }
  });

  test("does not expose creation proofs to clients", async () => {
    await seedProof("private-proof");
    await assertFails(getDoc(doc(creatorDb(), "organizationCreationProofs", "private-proof")));
  });
});
