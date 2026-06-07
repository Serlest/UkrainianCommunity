import assert from "node:assert/strict";
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
  updateDoc,
  where,
} from "firebase/firestore";
import {readFileSync} from "node:fs";

const PROJECT_ID = "ukrainian-community-system-logs-rules";
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
  await testEnv.cleanup();
});

function auth(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function unauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, "users", "owner"), user({globalRole: "owner"}));
    await setDoc(doc(db, "users", "admin"), user({globalRole: "admin"}));
    await setDoc(doc(db, "users", "moderator"), user({globalRole: "moderator"}));
    await setDoc(doc(db, "users", "normal-user"), user({globalRole: "user"}));
    await setDoc(doc(db, "users", "org-owner"), user({globalRole: "user"}));

    await setDoc(doc(db, "systemLogs", "diagnostics-log"), diagnosticsLog());
    await setDoc(doc(db, "systemLogs", "moderation-log"), moderationLog());
    await setDoc(doc(db, "systemLogs", "organization-log"), organizationLog());
    await setDoc(doc(db, "systemLogs", "security-log"), securityLog());
    await setDoc(doc(db, "systemLogs", "owner-actor-log"), ownerActorLog());
    await setDoc(doc(db, "systemLogs", "authorization-log"), authorizationLog());
  });
}

function user({globalRole}) {
  return {
    id: crypto.randomUUID(),
    globalRole,
    accountStatus: "active",
    blockState: "active",
  };
}

function baseLog(overrides = {}) {
  return {
    id: overrides.id ?? "log-id",
    createdAt: new Date("2026-06-07T10:00:00Z"),
    category: "diagnostics",
    severity: "error",
    severityRank: 4,
    eventType: "dataValidationFailed",
    actorRole: "system",
    targetType: "event",
    summary: "System log test fixture",
    isReviewed: false,
    metadata: {
      fixture: "systemLogsRules",
    },
    retentionPolicy: "technicalError",
    ...overrides,
  };
}

function diagnosticsLog() {
  return baseLog({
    id: "diagnostics-log",
    category: "diagnostics",
    actorRole: "system",
    retentionPolicy: "technicalError",
  });
}

function moderationLog() {
  return baseLog({
    id: "moderation-log",
    category: "moderation",
    severity: "notice",
    severityRank: 2,
    eventType: "contentRejected",
    actorRole: "admin",
    targetType: "newsPost",
    outcome: "rejected",
    retentionPolicy: "moderationDispute",
  });
}

function organizationLog() {
  return baseLog({
    id: "organization-log",
    category: "organization",
    severity: "info",
    severityRank: 1,
    eventType: "organizationRequestApproved",
    actorRole: "admin",
    targetType: "organizationRequest",
    organizationId: "org-1",
    outcome: "approved",
    retentionPolicy: "normalAudit",
  });
}

function securityLog() {
  return baseLog({
    id: "security-log",
    category: "userAccount",
    severity: "critical",
    severityRank: 5,
    eventType: "accountBlocked",
    actorRole: "admin",
    targetType: "account",
    outcome: "blocked",
    retentionPolicy: "security",
  });
}

function ownerActorLog() {
  return baseLog({
    id: "owner-actor-log",
    category: "diagnostics",
    actorRole: "owner",
    retentionPolicy: "technicalError",
  });
}

function authorizationLog() {
  return baseLog({
    id: "authorization-log",
    category: "authorization",
    severity: "warning",
    severityRank: 3,
    eventType: "permissionDenied",
    actorRole: "admin",
    targetType: "organizationRequest",
    outcome: "blocked",
    retentionPolicy: "security",
  });
}

function diagnosticsCreate(id = "created-diagnostics-log") {
  return {
    ...diagnosticsLog(),
    id,
    createdAt: new Date("2026-06-07T11:00:00Z"),
    isReviewed: false,
  };
}

function auditCreate({id, actorUserId, actorRole}) {
  return {
    id,
    createdAt: new Date("2026-06-07T11:05:00Z"),
    category: "audit",
    severity: "info",
    severityRank: 1,
    eventType: "contentCreated",
    actorUserId,
    actorRole,
    targetType: "newsPost",
    targetId: "news-1",
    targetTitle: "Community update",
    summary: "News post created",
    moduleName: "News",
    operationName: "createNews",
    outcome: "success",
    isReviewed: false,
    metadata: {},
    retentionPolicy: "normalAudit",
  };
}

function moderationCreate({id, actorUserId, actorRole, eventType = "contentApproved", outcome = "approved"}) {
  return {
    id,
    createdAt: new Date("2026-06-07T11:10:00Z"),
    category: "moderation",
    severity: "notice",
    severityRank: 2,
    eventType,
    actorUserId,
    actorRole,
    targetType: "newsPost",
    targetId: "news-1",
    targetTitle: "Community update",
    summary: "Новину схвалено",
    moduleName: "Moderation",
    operationName: "approveNewsPost",
    outcome,
    isReviewed: false,
    metadata: {
      newStatus: "approved",
    },
    retentionPolicy: "moderationDispute",
  };
}

function securityCreate({
  id,
  actorUserId,
  actorRole,
  eventType = "roleAssigned",
  outcome = "success",
  severity = "notice",
}) {
  return {
    id,
    createdAt: new Date("2026-06-07T11:15:00Z"),
    category: "authorization",
    severity,
    severityRank: severity === "error" ? 4 : severity === "warning" ? 3 : 2,
    eventType,
    actorUserId,
    actorRole,
    targetType: "userProfile",
    targetId: "target-user",
    summary: "Платформну роль призначено",
    moduleName: "Security",
    operationName: "assignAppAdmin",
    outcome,
    isReviewed: false,
    metadata: {
      functionName: "assignAppAdmin",
      targetUserId: "target-user",
    },
    retentionPolicy: "security",
  };
}

async function markReviewed(db, logID, reviewerID) {
  await updateDoc(doc(db, "systemLogs", logID), {
    isReviewed: true,
    reviewedAt: new Date("2026-06-07T12:00:00Z"),
    reviewedByUserId: reviewerID,
  });
}

describe("systemLogs owner access", () => {
  test("owner can read diagnostics, security, and owner actor logs", async () => {
    const db = auth("owner");

    await assertSucceeds(getDoc(doc(db, "systemLogs", "diagnostics-log")));
    await assertSucceeds(getDoc(doc(db, "systemLogs", "security-log")));
    await assertSucceeds(getDoc(doc(db, "systemLogs", "owner-actor-log")));
  });

  test("owner can mark any log reviewed and cannot delete logs", async () => {
    const db = auth("owner");

    await assertSucceeds(markReviewed(db, "security-log", "owner"));
    await assertSucceeds(markReviewed(db, "owner-actor-log", "owner"));
    await assertFails(deleteDoc(doc(db, "systemLogs", "diagnostics-log")));
  });
});

describe("systemLogs app admin access", () => {
  test("admin can read allowed diagnostics, moderation, and organization logs", async () => {
    const db = auth("admin");

    await assertSucceeds(getDoc(doc(db, "systemLogs", "diagnostics-log")));
    await assertSucceeds(getDoc(doc(db, "systemLogs", "moderation-log")));
    await assertSucceeds(getDoc(doc(db, "systemLogs", "organization-log")));
  });

  test("admin cannot read security, owner actor, or authorization logs", async () => {
    const db = auth("admin");

    await assertFails(getDoc(doc(db, "systemLogs", "security-log")));
    await assertFails(getDoc(doc(db, "systemLogs", "owner-actor-log")));
    await assertFails(getDoc(doc(db, "systemLogs", "authorization-log")));
  });

  test("admin can mark reviewed only on readable allowed logs", async () => {
    const db = auth("admin");

    await assertSucceeds(markReviewed(db, "diagnostics-log", "admin"));
    await assertFails(markReviewed(db, "security-log", "admin"));
    await assertFails(markReviewed(db, "owner-actor-log", "admin"));
  });

  test("admin cannot update arbitrary fields or delete logs", async () => {
    const db = auth("admin");

    await assertFails(updateDoc(doc(db, "systemLogs", "diagnostics-log"), {
      summary: "Changed summary",
    }));
    await assertFails(deleteDoc(doc(db, "systemLogs", "diagnostics-log")));
  });
});

describe("systemLogs normal user access", () => {
  test("normal user cannot read, update, or delete any system log", async () => {
    const db = auth("normal-user");

    await assertFails(getDoc(doc(db, "systemLogs", "diagnostics-log")));
    await assertFails(markReviewed(db, "diagnostics-log", "normal-user"));
    await assertFails(deleteDoc(doc(db, "systemLogs", "diagnostics-log")));
  });

  test("normal user cannot create audit, security, moderation, or diagnostics logs", async () => {
    const db = auth("normal-user");

    await assertFails(setDoc(doc(db, "systemLogs", "normal-diagnostics"), diagnosticsCreate("normal-diagnostics")));
    await assertFails(setDoc(doc(db, "systemLogs", "normal-security"), securityLog()));
    await assertFails(setDoc(doc(db, "systemLogs", "normal-moderation"), moderationLog()));
    await assertFails(setDoc(doc(db, "systemLogs", "normal-audit"), auditCreate({
      id: "normal-audit",
      actorUserId: "normal-user",
      actorRole: "admin",
    })));
  });

  test("unauthenticated users cannot read logs", async () => {
    const db = unauthenticated();

    await assertFails(getDoc(doc(db, "systemLogs", "diagnostics-log")));
  });
});

describe("systemLogs client create restrictions", () => {
  test("owner and admin can create diagnostics, audit, and constrained moderation logs only", async () => {
    const ownerDb = auth("owner");
    const adminDb = auth("admin");

    await assertSucceeds(setDoc(doc(ownerDb, "systemLogs", "owner-created-diagnostics"), diagnosticsCreate("owner-created-diagnostics")));
    await assertSucceeds(setDoc(doc(adminDb, "systemLogs", "admin-created-diagnostics"), diagnosticsCreate("admin-created-diagnostics")));
    await assertSucceeds(setDoc(doc(ownerDb, "systemLogs", "owner-created-audit"), auditCreate({
      id: "owner-created-audit",
      actorUserId: "owner",
      actorRole: "owner",
    })));
    await assertSucceeds(setDoc(doc(adminDb, "systemLogs", "admin-created-audit"), auditCreate({
      id: "admin-created-audit",
      actorUserId: "admin",
      actorRole: "admin",
    })));
    await assertSucceeds(setDoc(doc(ownerDb, "systemLogs", "owner-created-moderation"), moderationCreate({
      id: "owner-created-moderation",
      actorUserId: "owner",
      actorRole: "owner",
    })));
    await assertSucceeds(setDoc(doc(adminDb, "systemLogs", "admin-created-moderation"), moderationCreate({
      id: "admin-created-moderation",
      actorUserId: "admin",
      actorRole: "admin",
      eventType: "organizationRequestRejected",
      outcome: "rejected",
    })));

    await assertFails(setDoc(doc(ownerDb, "systemLogs", "owner-created-security"), {
      ...securityLog(),
      id: "owner-created-security",
    }));
    await assertFails(setDoc(doc(adminDb, "systemLogs", "admin-created-owner-audit"), auditCreate({
      id: "admin-created-owner-audit",
      actorUserId: "admin",
      actorRole: "owner",
    })));
  });

  test("moderator can create constrained moderation logs but cannot create audit or diagnostics logs", async () => {
    const db = auth("moderator");

    await assertSucceeds(setDoc(doc(db, "systemLogs", "moderator-created-moderation"), moderationCreate({
      id: "moderator-created-moderation",
      actorUserId: "moderator",
      actorRole: "moderator",
      eventType: "contentRejected",
      outcome: "rejected",
    })));
    await assertFails(setDoc(doc(db, "systemLogs", "moderator-created-audit"), auditCreate({
      id: "moderator-created-audit",
      actorUserId: "moderator",
      actorRole: "moderator",
    })));
    await assertFails(setDoc(doc(db, "systemLogs", "moderator-created-diagnostics"), diagnosticsCreate("moderator-created-diagnostics")));
  });

  test("moderation create rejects spoofed actors and security-style event types", async () => {
    const adminDb = auth("admin");

    await assertFails(setDoc(doc(adminDb, "systemLogs", "spoofed-moderation"), moderationCreate({
      id: "spoofed-moderation",
      actorUserId: "admin",
      actorRole: "owner",
    })));
    await assertFails(setDoc(doc(adminDb, "systemLogs", "security-style-moderation"), moderationCreate({
      id: "security-style-moderation",
      actorUserId: "admin",
      actorRole: "admin",
      eventType: "accountBlocked",
      outcome: "success",
    })));
  });

  test("owner and admin can create constrained security logs", async () => {
    const ownerDb = auth("owner");
    const adminDb = auth("admin");

    await assertSucceeds(setDoc(doc(ownerDb, "systemLogs", "owner-created-security-log"), securityCreate({
      id: "owner-created-security-log",
      actorUserId: "owner",
      actorRole: "owner",
      eventType: "roleAssigned",
      outcome: "success",
    })));
    await assertSucceeds(setDoc(doc(adminDb, "systemLogs", "admin-created-permission-denied-log"), securityCreate({
      id: "admin-created-permission-denied-log",
      actorUserId: "admin",
      actorRole: "admin",
      eventType: "permissionDenied",
      outcome: "blocked",
      severity: "error",
    })));
  });

  test("security create rejects normal users, moderators, and spoofed actors", async () => {
    const normalDb = auth("normal-user");
    const moderatorDb = auth("moderator");
    const adminDb = auth("admin");

    await assertFails(setDoc(doc(normalDb, "systemLogs", "normal-created-security-log"), securityCreate({
      id: "normal-created-security-log",
      actorUserId: "normal-user",
      actorRole: "admin",
    })));
    await assertFails(setDoc(doc(moderatorDb, "systemLogs", "moderator-created-security-log"), securityCreate({
      id: "moderator-created-security-log",
      actorUserId: "moderator",
      actorRole: "moderator",
    })));
    await assertFails(setDoc(doc(adminDb, "systemLogs", "spoofed-security-log"), securityCreate({
      id: "spoofed-security-log",
      actorUserId: "admin",
      actorRole: "owner",
    })));
  });
});

describe("systemLogs queries", () => {
  test("owner broad query succeeds", async () => {
    const db = auth("owner");

    const snapshot = await assertSucceeds(getDocs(collection(db, "systemLogs")));
    assert.ok(snapshot.size >= 6);
  });

  test("admin constrained query for allowed diagnostics succeeds", async () => {
    const db = auth("admin");
    const allowedDiagnostics = query(
      collection(db, "systemLogs"),
      where("category", "==", "diagnostics"),
      where("retentionPolicy", "==", "technicalError"),
      where("eventType", "==", "dataValidationFailed"),
      where("actorRole", "==", "system"),
    );

    const snapshot = await assertSucceeds(getDocs(allowedDiagnostics));
    assert.equal(snapshot.docs.some((item) => item.id === "diagnostics-log"), true);
  });

  test("admin broad query fails when mixed forbidden logs exist", async () => {
    const db = auth("admin");

    await assertFails(getDocs(collection(db, "systemLogs")));
  });
});
