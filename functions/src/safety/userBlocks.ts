import {Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuth} from "../auth/context";
import {db} from "../firebase/admin";
import {getUserPermissions, isActiveUser} from "../permissions/userPermissions";

export interface UserBlockRequest {
  targetUserId: string;
  isBlocked: boolean;
}

interface UserBlockResponse {
  targetUserId: string;
  isBlocked: boolean;
  displayName: string;
  avatarURL?: string;
  updatedAt: string;
}

const callableOptions = {
  region: "europe-west3",
  maxInstances: 20,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function userId(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string.`);
  }
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > 256 || normalized.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} must be a valid user ID.`);
  }
  return normalized;
}

export function parseUserBlockRequest(value: unknown): UserBlockRequest {
  if (!isRecord(value)) {
    throw new HttpsError("invalid-argument", "The block request must be an object.");
  }
  const unsupportedFields = Object.keys(value).filter(
    (key) => key !== "targetUserId" && key !== "isBlocked"
  );
  if (unsupportedFields.length > 0) {
    throw new HttpsError("invalid-argument", "The block request contains unsupported fields.");
  }
  if (typeof value.isBlocked !== "boolean") {
    throw new HttpsError("invalid-argument", "isBlocked must be a boolean.");
  }
  return {
    targetUserId: userId(value.targetUserId, "targetUserId"),
    isBlocked: value.isBlocked,
  };
}

export function userBlockDocumentPath(actorUserId: string, targetUserId: string): string {
  return `users/${actorUserId}/blockedUsers/${targetUserId}`;
}

function normalizedDisplayName(value: unknown): string {
  if (typeof value !== "string") {
    return "Community member";
  }
  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 0 ? normalized.slice(0, 120) : "Community member";
}

function optionalAvatarURL(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= 2_048 ? normalized : undefined;
}

export const setUserBlocked = onCall(
  callableOptions,
  async (request): Promise<UserBlockResponse> => {
    const actor = requireAuth(request);
    if (actor.token.email_verified !== true) {
      throw new HttpsError("permission-denied", "A verified email address is required.");
    }
    const input = parseUserBlockRequest(request.data);
    if (input.targetUserId === actor.uid) {
      throw new HttpsError("failed-precondition", "You cannot block your own account.");
    }

    const [permissions, targetSnapshot, publicProfileSnapshot] = await Promise.all([
      getUserPermissions(actor.uid),
      db.collection("users").doc(input.targetUserId).get(),
      db.collection("publicProfiles").doc(input.targetUserId).get(),
    ]);
    if (!isActiveUser(permissions)) {
      throw new HttpsError("permission-denied", "Only active users can manage blocked users.");
    }
    if (!targetSnapshot.exists) {
      throw new HttpsError("not-found", "The target user does not exist.");
    }

    const target = targetSnapshot.data() ?? {};
    const publicProfile = publicProfileSnapshot.data() ?? {};
    const targetIsDeactivated = target.accountStatus === "deactivated"
      || target.blockState === "deactivated";
    if (targetIsDeactivated) {
      throw new HttpsError("not-found", "The target user is no longer active.");
    }

    const displayName = normalizedDisplayName(
      publicProfile.displayName ?? target.displayName ?? target.fullName
    );
    const avatarURL = optionalAvatarURL(publicProfile.avatarURL ?? target.avatarURL);
    const reference = db.doc(userBlockDocumentPath(actor.uid, input.targetUserId));
    const updatedAt = Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(reference);
      if (!input.isBlocked) {
        if (existing.exists) {
          transaction.delete(reference);
        }
        return;
      }

      transaction.set(reference, {
        id: input.targetUserId,
        targetUserId: input.targetUserId,
        displayName,
        avatarURL: avatarURL ?? null,
        blockedAt: existing.data()?.blockedAt ?? updatedAt,
        updatedAt,
      });
    });

    return {
      targetUserId: input.targetUserId,
      isBlocked: input.isBlocked,
      displayName,
      avatarURL,
      updatedAt: updatedAt.toDate().toISOString(),
    };
  }
);
