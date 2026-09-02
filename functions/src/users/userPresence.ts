import {type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";

import {requireVerifiedAuth, requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {assertCanManageUsers, isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";

// The client heartbeats every 90 seconds. A two-interval lease absorbs a
// transient failed call without returning to the previous 30-second write rate.
export const presenceLeaseMs = 180_000;
const sessionRetentionMs = 10 * 60_000;
const maxSessions = 32;

interface PresenceUpdate {
  userId: string;
  sessionId: string;
  sequence: number;
  active: boolean;
}
interface PresenceSession {
  sequence: number;
  active: boolean;
  updatedAt: number;
}
interface PresenceState {
  lastSeenAt: number | null;
  sessions: Record<string, PresenceSession>;
}

export function parsePresenceUpdate(value: unknown, uid: string): PresenceUpdate {
  const data = value as Partial<PresenceUpdate> | undefined;
  if (!data || data.userId !== uid) {
    throw new HttpsError("permission-denied", "Presence may only be updated for the authenticated account.");
  }
  if (typeof data.sessionId !== "string" || !/^[a-f0-9-]{36}$/i.test(data.sessionId)
      || !Number.isSafeInteger(data.sequence) || Number(data.sequence) < 1
      || typeof data.active !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid presence update.");
  }
  return data as PresenceUpdate;
}

export function presenceState(data: DocumentData | undefined): PresenceState {
  const sessions: Record<string, PresenceSession> = {};
  for (const [key, value] of Object.entries(data?.sessions ?? {})) {
    const session = value as PresenceSession;
    if (session && Number.isSafeInteger(session.sequence)
        && typeof session.active === "boolean" && Number.isFinite(session.updatedAt)) {
      sessions[key] = session;
    }
  }
  return {lastSeenAt: Number.isFinite(data?.lastSeenAt) ? data!.lastSeenAt : null, sessions};
}

// Sequence numbers make delayed foreground/background requests harmless.
// Sessions are per app process/account; one device going offline cannot hide another.
export function applyPresenceUpdate(state: PresenceState, update: PresenceUpdate, now: number): PresenceState {
  const previous = state.sessions[update.sessionId];
  if (previous && previous.sequence >= update.sequence) return state;
  const sessions = Object.fromEntries(Object.entries(state.sessions)
    .filter(([, session]) => session.updatedAt > now - sessionRetentionMs));
  if (!sessions[update.sessionId] && Object.keys(sessions).length >= maxSessions) {
    throw new HttpsError("resource-exhausted", "Too many presence sessions.");
  }
  sessions[update.sessionId] = {sequence: update.sequence, active: update.active, updatedAt: now};
  return {lastSeenAt: Math.max(state.lastSeenAt ?? 0, now), sessions};
}

export function presenceResponse(targetUserId: string, state: PresenceState, now: number, usable = true) {
  const onlineUntil = usable ? Math.max(0, ...Object.values(state.sessions)
    .filter((session) => session.active && session.updatedAt <= now)
    .map((session) => session.updatedAt + presenceLeaseMs)) : 0;
  return {
    targetUserId,
    lastSeenAt: state.lastSeenAt,
    onlineUntil: onlineUntil > now ? onlineUntil : null,
    serverTime: now,
  };
}

export async function writeUserPresence(uid: string, update: PresenceUpdate): Promise<void> {
  const user = db.collection("users").doc(uid);
  const presence = user.collection("privatePresence").doc("current");
  await db.runTransaction(async (transaction) => {
    const [profile, snapshot] = await transaction.getAll(user, presence);
    // Read the profile in this transaction so deletion/deactivation cannot race a heartbeat.
    if (!profile.exists || !isActiveUser(userPermissionSnapshotFromData(uid, profile.data()))
        || profile.data()?.deletionState === "inProgress") {
      throw new HttpsError("permission-denied", "An active account is required.");
    }
    const current = presenceState(snapshot.data());
    const next = applyPresenceUpdate(current, update, Date.now());
    if (next !== current) transaction.set(presence, next);
  });
}

const options = {
  region: "europe-west3",
  maxInstances: 10,
  timeoutSeconds: 30,
  enforceAppCheck: false,
};

export const updateUserPresence = onCall(options, async (request) => {
  const auth = requireVerifiedAuth(request);
  const update = parsePresenceUpdate(request.data, auth.uid);
  await writeUserPresence(auth.uid, update);
  return {accepted: true};
});

export const getManagedUserPresence = onCall(options, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  assertCanManageUsers(auth.permissions);
  const targetUserId = request.data?.targetUserId;
  if (typeof targetUserId !== "string" || !targetUserId.length || targetUserId.includes("/")
      || targetUserId.length > 128) {
    throw new HttpsError("invalid-argument", "A valid targetUserId is required.");
  }
  const user = db.collection("users").doc(targetUserId);
  const [profile, snapshot] = await db.getAll(user, user.collection("privatePresence").doc("current"));
  if (!profile.exists) throw new HttpsError("not-found", "User profile does not exist.");
  return presenceResponse(targetUserId, presenceState(snapshot.data()), Date.now(),
    isActiveUser(userPermissionSnapshotFromData(targetUserId, profile.data())));
});
