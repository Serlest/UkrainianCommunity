import {
  FieldPath,
  type DocumentData,
  type Query,
  type QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as logger from "firebase-functions/logger";
import {
  HttpsError,
  type CallableRequest,
  onCall,
} from "firebase-functions/v2/https";

import { getUserPermissions, isAppOwner } from "../permissions/userPermissions";
import { requireAuth } from "../auth/context";
import { adminAuth, db } from "../firebase/admin";

interface DeleteUserAccountRequest {
  acknowledged?: boolean;
}

interface DeleteUserAccountResponse {
  deletedUserId: string;
  deletedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 10,
};

const batchSize = 300;
const anonymousDisplayName = "Deleted User";
const anonymousUserId = "deleted-user";
const anonymousEmail = "deleted.user@local.invalid";
const anonymousErrorCodePrefix = "delete-user-account";

const userPrivateSubcollections = [
  "recentViews",
  "activityLog",
  "newsBookmarks",
  "eventBookmarks",
  "organizationBookmarks",
  "notificationInbox",
  "notificationPushTokens",
  "eventViews",
  "newsViews",
  "guideMaterialBookmarks"
] as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseRequest(data: unknown): DeleteUserAccountRequest {
  if (data === undefined || data === null) {
    return {};
  }

  if (!isRecord(data)) {
    throw new HttpsError("invalid-argument", "Request payload must be an object.");
  }

  return {
    acknowledged: data.acknowledged === true,
  };
}

function parseErrorCode(details: unknown): string | null {
  if (typeof details === "string") {
    return details;
  }

  if (isRecord(details) && typeof details.code === "string") {
    return details.code;
  }

  return null;
}

function parseErrorPayload(error: unknown): string | null {
  if (error instanceof HttpsError) {
    return parseErrorCode(error.details);
  }

  return null;
}

function safeErrorContext(error: unknown): { code?: string; message?: string } {
  if (error instanceof Error) {
    const details = parseErrorCode((error as { details?: unknown }).details);
    const code = typeof details === "string" ? details : undefined;
    return {
      code,
      message: error.message,
    };
  }

  if (typeof error === "string") {
    return { message: error };
  }

  return {};
}

function correlationContext(): { correlationId: string } {
  return {
    correlationId: crypto.randomUUID(),
  };
}

async function runCleanupOperation(
  _uid: string,
  correlationId: string,
  stage: string,
  operation: () => Promise<void>
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    const parsedError = safeErrorContext(error);
    logger.error("Account cleanup step failed.", {
      correlationId,
      stage,
      errorCode: parsedError.code,
      errorMessage: parsedError.message?.slice(0, 500),
      category: anonymousErrorCodePrefix,
    });
    throwWithCode(
      `Account cleanup failed at stage: ${stage}.`,
      "cleanup-failed"
    );
  }
}

function requireAuthWithErrorCode(request: CallableRequest): { uid: string } {
  try {
    return requireAuth(request);
  } catch (error) {
    if (error instanceof HttpsError && error.code === "unauthenticated") {
      throw new HttpsError("unauthenticated", "Authentication is required.", {
        code: "requires-auth",
      });
    }

    throw error;
  }
}

function throwWithCode(message: string, code: string): never {
  throw new HttpsError("internal", message, { code });
}

function isAccountBlockedForDeletion(
  accountStatus: string | undefined,
  blockState: string | undefined
): boolean {
  const normalizedAccountStatus = accountStatus ?? "active";
  const normalizedBlockState = blockState ?? "active";

  return !["active", "warned"].includes(normalizedAccountStatus)
    || !["active", "warned"].includes(normalizedBlockState);
}

async function getDeletionPermissions(
  uid: string,
  correlationId: string
) {
  try {
    return await getUserPermissions(uid);
  } catch (error) {
    if (error instanceof HttpsError && error.code === "permission-denied") {
      logger.warn("User profile missing during account deletion retry.", {
        correlationId,
        stage: "ownership-profile-missing",
        category: anonymousErrorCodePrefix,
      });
      return null;
    }

    throw error;
  }
}

function anonymizedUserId(value: unknown): string {
  void value;
  return anonymousUserId;
}

function buildFeedbackAnonymizationUpdate(
  data: DocumentData,
  userId: string
): Record<string, unknown> {
  const update: Record<string, unknown> = {};

  if ("userId" in data && data.userId === userId) {
    update.userId = anonymizedUserId(userId);
  }

  if ("userDisplayName" in data) {
    update.userDisplayName = anonymousDisplayName;
  }

  if ("userEmail" in data) {
    update.userEmail = anonymousEmail;
  }

  if ("lastMessageByUserId" in data && data.lastMessageByUserId === userId) {
    update.lastMessageByUserId = anonymousUserId;
  }

  if ("repliedByUserId" in data && data.repliedByUserId === userId) {
    update.repliedByUserId = anonymousUserId;
  }

  if ("authorUserId" in data && data.authorUserId === userId) {
    update.authorUserId = anonymousUserId;
  }

  if ("authorDisplayName" in data && data.authorUserId === userId) {
    update.authorDisplayName = anonymousDisplayName;
  }

  if ("authorEmail" in data && data.authorUserId === userId) {
    update.authorEmail = anonymousEmail;
  }

  return update;
}

function buildFeedbackMessageAnonymizationUpdate(
  data: DocumentData,
  userId: string
): Record<string, unknown> {
  const update: Record<string, unknown> = {};

  if ("authorUserId" in data && data.authorUserId === userId) {
    update.authorUserId = anonymousUserId;
    if ("authorDisplayName" in data) {
      update.authorDisplayName = anonymousDisplayName;
    }
    if ("authorEmail" in data) {
      update.authorEmail = anonymousEmail;
    }
  }

  if ("senderId" in data && data.senderId === userId) {
    update.senderId = anonymousUserId;
    if ("senderDisplayName" in data) {
      update.senderDisplayName = anonymousDisplayName;
    }
  }

  return update;
}

function buildSystemLogAnonymizationUpdate(
  data: DocumentData,
  userId: string
): Record<string, unknown> {
  const update: Record<string, unknown> = {};

  if ("actorUserId" in data && data.actorUserId === userId) {
    update.actorUserId = anonymousUserId;
  }

  if ("actorDisplayName" in data && data.actorUserId === userId) {
    update.actorDisplayName = anonymousDisplayName;
  }

  if ("reviewedByUserId" in data && data.reviewedByUserId === userId) {
    update.reviewedByUserId = anonymousUserId;
  }

  return update;
}

async function deleteByQuery(query: Query<DocumentData>): Promise<void> {
  const ordered = query.orderBy(FieldPath.documentId());
  let cursor: QueryDocumentSnapshot<DocumentData> | undefined;

  while (true) {
    const pageQuery = cursor
      ? ordered.startAfter(cursor).limit(batchSize)
      : ordered.limit(batchSize);
    const snapshot = await pageQuery.get();

    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((document) => {
      batch.delete(document.ref);
    });

    await batch.commit();

    if (snapshot.size < batchSize) {
      return;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

async function anonymizeByQuery(
  query: Query<DocumentData>,
  buildUpdate: (data: DocumentData, userId: string) => Record<string, unknown>,
  userId: string
): Promise<void> {
  const ordered = query.orderBy(FieldPath.documentId());
  let cursor: QueryDocumentSnapshot<DocumentData> | undefined;

  while (true) {
    const pageQuery = cursor
      ? ordered.startAfter(cursor).limit(batchSize)
      : ordered.limit(batchSize);
    const snapshot = await pageQuery.get();

    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    let hasWrites = false;

    snapshot.docs.forEach((document) => {
      const update = buildUpdate(document.data(), userId);
      if (Object.keys(update).length === 0) {
        return;
      }

      batch.update(document.ref, update);
      hasWrites = true;
    });

    if (hasWrites) {
      await batch.commit();
    }

    if (snapshot.size < batchSize) {
      return;
    }

    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

async function anonymizeFeedbackData(userId: string): Promise<void> {
  await anonymizeByQuery(
    db.collection("feedback").where("userId", "==", userId),
    buildFeedbackAnonymizationUpdate,
    userId
  );

  await anonymizeByQuery(
    db.collectionGroup("messages").where("senderId", "==", userId),
    buildFeedbackMessageAnonymizationUpdate,
    userId
  );

  await anonymizeByQuery(
    db.collectionGroup("messages").where("authorUserId", "==", userId),
    buildFeedbackMessageAnonymizationUpdate,
    userId
  );
}

async function anonymizeSystemLogs(userId: string): Promise<void> {
  await Promise.all([
    anonymizeByQuery(
      db.collection("systemLogs").where("actorUserId", "==", userId),
      buildSystemLogAnonymizationUpdate,
      userId
    ),
    anonymizeByQuery(
      db.collection("systemLogs").where("reviewedByUserId", "==", userId),
      buildSystemLogAnonymizationUpdate,
      userId
    ),
  ]);
}

async function deleteUserPrivateCollections(userId: string): Promise<void> {
  const userReference = db.collection("users").doc(userId);

  await Promise.all([
    ...userPrivateSubcollections.map((subcollection) =>
      deleteByQuery(userReference.collection(subcollection))
    ),
    userReference.collection("notificationPreferences").doc("settings").delete(),
  ]);
}

async function deleteRootUserDocument(userId: string): Promise<void> {
  const userReference = db.collection("users").doc(userId);
  await userReference.delete();
}

async function removeProfileAvatar(userId: string): Promise<void> {
  const bucket = getStorage().bucket();
  const avatarReference = bucket.file(`profileImages/${userId}/avatar.jpg`);
  await avatarReference.delete({ ignoreNotFound: true });
}

async function deleteUserLinkedData(userId: string): Promise<void> {
  const { correlationId } = correlationContext();

  await Promise.all([
    runCleanupOperation(
      userId,
      correlationId,
      "user-private-subcollections",
      () => deleteUserPrivateCollections(userId)
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "likes",
      () => deleteByQuery(db.collection("likes").where("userId", "==", userId))
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "registrations",
      () => deleteByQuery(db.collection("registrations").where("userId", "==", userId))
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "feedback-data",
      () => anonymizeFeedbackData(userId)
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "system-logs",
      () => anonymizeSystemLogs(userId)
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "public-profile",
      async () => {
        await db.collection("publicProfiles").doc(userId).delete();
      }
    ),
    runCleanupOperation(
      userId,
      correlationId,
      "avatar-storage",
      () => removeProfileAvatar(userId)
    ),
  ]);
}

export const deleteUserAccount = onCall(callableOptions, async (request) => {
  const parsed = parseRequest(request.data);
  if (parsed.acknowledged === true) {
    // Compatibility flag for older clients; no additional behavior required server-side.
  }

  const { uid } = requireAuthWithErrorCode(request);
  const { correlationId } = correlationContext();
  logger.info("deleteUserAccount requested.", {
    hasAuth: true,
    correlationId,
    stage: "ownership-check",
    category: anonymousErrorCodePrefix,
  });
  const permissions = await getDeletionPermissions(uid, correlationId);

  if (permissions) {
    if (isAppOwner(permissions)) {
      logger.warn("Blocked app owner deletion attempt.", {
        correlationId,
        stage: "ownership-block-owner",
        category: anonymousErrorCodePrefix,
      });
      throw new HttpsError("permission-denied", "Blocked: app owner account cannot be deleted.", {
        code: "blocked-owner",
      });
    }

    if (isAccountBlockedForDeletion(permissions.accountStatus, permissions.blockState)) {
      logger.warn("Blocked banned/deactivated account deletion attempt.", {
        correlationId,
        stage: "ownership-block-banned",
        category: anonymousErrorCodePrefix,
      });
      throw new HttpsError("permission-denied", "Blocked: banned account deletion blocked.", {
        code: "blocked-banned-user",
      });
    }
  }

  const ownsOrganizationSnapshot = await db.collection("organizations")
    .where("ownerId", "==", uid)
    .limit(1)
    .get();

  if (!ownsOrganizationSnapshot.empty) {
    logger.warn("Blocked organization owner deletion attempt.", {
      correlationId,
      stage: "ownership-block-organization-owner",
      organizationCount: ownsOrganizationSnapshot.size,
      category: anonymousErrorCodePrefix,
    });
    throw new HttpsError("permission-denied", "Blocked: organization owner cannot delete account.", {
      code: "blocked-organization-owner",
    });
  }

  try {
    await deleteUserLinkedData(uid);
    await runCleanupOperation(
      uid,
      correlationId,
      "user-document",
      () => deleteRootUserDocument(uid)
    );
  } catch (error) {
    const cleanupCode = parseErrorPayload(error);
    if (cleanupCode === "cleanup-failed") {
      throw error;
    }

    const parsed = safeErrorContext(error);
    logger.error("Account cleanup failed with unknown error.", {
      correlationId,
      errorCode: parsed.code,
      errorMessage: parsed.message?.slice(0, 500),
      category: anonymousErrorCodePrefix,
    });
    throwWithCode("Account cleanup failed.", "cleanup-failed");
  }

  try {
    await adminAuth.deleteUser(uid);
  } catch (error) {
    const authCode = parseErrorCode((error as { code?: unknown })?.code);
    if (authCode === "auth/user-not-found") {
      logger.warn("Auth user was already deleted before cleanup-auth step.", {
        uid,
        correlationId,
        stage: "auth-delete-already-complete",
        category: anonymousErrorCodePrefix,
      });
    } else {
      const parsed = safeErrorContext(error);
      logger.error("Auth user deletion failed.", {
        correlationId,
        uid,
        stage: "auth-delete-failed",
        errorCode: parsed.code,
        errorMessage: parsed.message?.slice(0, 500),
        category: anonymousErrorCodePrefix,
      });

      throwWithCode("Firebase Auth user deletion failed.", "auth-delete-failed");
    }
  }

  logger.info("Account deletion completed.", {
    correlationId,
    stage: "completed",
    category: anonymousErrorCodePrefix,
  });
  return {
    deletedUserId: uid,
    deletedAt: new Date().toISOString(),
  } satisfies DeleteUserAccountResponse;
});
