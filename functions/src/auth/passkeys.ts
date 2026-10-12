import {createHash, randomUUID} from "node:crypto";

import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type RegistrationResponseJSON,
} from "@simplewebauthn/server";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

import {adminAuth, db} from "../firebase/admin";
import {isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {
  canManagePasskeyCredentials,
  requireVerifiedActiveUser,
} from "./context";

// This domain is served by Firebase Hosting and has the app's webcredentials
// association. Never accept an RP ID or origin supplied by the client.
const rpID = "ukrainiancommunity-dbd5f.web.app";
const origin = `https://${rpID}`;
const challengeLifetimeMs = 5 * 60 * 1000;
const options = {region: "europe-west3", maxInstances: 5, enforceAppCheck: true};
const challenges = db.collection("passkeyChallenges");
const credentials = db.collection("passkeyCredentials");

function stringField(value: unknown, maxLength = 4096): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maxLength) {
    throw new HttpsError("invalid-argument", "Invalid passkey response.");
  }
  return value;
}

function credentialKey(id: string): string {
  return createHash("sha256").update(id).digest("hex");
}

function registrationResponse(value: unknown): RegistrationResponseJSON {
  const input = value as Record<string, unknown> | null;
  const response = input?.response as Record<string, unknown> | undefined;
  const id = stringField(input?.id, 2048);
  if (stringField(input?.rawId, 2048) !== id) {
    throw new HttpsError("invalid-argument", "Passkey ID mismatch.");
  }
  return {
    id,
    rawId: id,
    type: "public-key",
    response: {
      clientDataJSON: stringField(response?.clientDataJSON, 8192),
      attestationObject: stringField(response?.attestationObject, 32768),
    },
    clientExtensionResults: {},
  };
}

function authenticationResponse(value: unknown): AuthenticationResponseJSON {
  const input = value as Record<string, unknown> | null;
  const response = input?.response as Record<string, unknown> | undefined;
  const id = stringField(input?.id, 2048);
  if (stringField(input?.rawId, 2048) !== id) {
    throw new HttpsError("invalid-argument", "Passkey ID mismatch.");
  }
  return {
    id,
    rawId: id,
    type: "public-key",
    response: {
      clientDataJSON: stringField(response?.clientDataJSON, 8192),
      authenticatorData: stringField(response?.authenticatorData, 8192),
      signature: stringField(response?.signature, 8192),
      userHandle: typeof response?.userHandle === "string" ? response.userHandle : undefined,
    },
    clientExtensionResults: {},
  };
}

function validChallenge(data: FirebaseFirestore.DocumentData | undefined, kind: string): string {
  if (data?.kind !== kind || typeof data.challenge !== "string"
      || !(data.expiresAt instanceof Timestamp)
      || data.expiresAt.toMillis() <= Date.now()) {
    throw new HttpsError("failed-precondition", "Passkey request expired. Try again.");
  }
  return data.challenge;
}

export const beginPasskeyRegistration = onCall(options, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  if (!canManagePasskeyCredentials(auth.token, auth.permissions)) {
    throw new HttpsError("permission-denied", "Sign in again to add a passkey.");
  }
  const profile = await db.collection("users").doc(auth.uid).get();
  if (!profile.exists || !isActiveUser(userPermissionSnapshotFromData(auth.uid, profile.data()!))) {
    throw new HttpsError("permission-denied", "An active account is required.");
  }
  const record = await adminAuth.getUser(auth.uid);
  if (!record.emailVerified || record.disabled || !record.email) {
    throw new HttpsError("permission-denied", "A verified active account is required.");
  }
  const existing = await credentials.where("uid", "==", auth.uid).get();
  const generated = await generateRegistrationOptions({
    rpName: "Ukrainian Community",
    rpID,
    userName: record.email,
    userID: createHash("sha256").update(auth.uid).digest(),
    attestationType: "none",
    excludeCredentials: existing.docs.map((item) => ({id: item.get("id") as string})),
    authenticatorSelection: {
      authenticatorAttachment: "platform",
      residentKey: "required",
      userVerification: "required",
    },
    supportedAlgorithmIDs: [-7],
    timeout: challengeLifetimeMs,
  });
  const requestID = randomUUID();
  await challenges.doc(requestID).create({
    kind: "registration", uid: auth.uid, challenge: generated.challenge,
    expiresAt: Timestamp.fromMillis(Date.now() + challengeLifetimeMs),
  });
  return {requestID, challenge: generated.challenge, userID: generated.user.id,
    userName: record.email, rpID};
});

export const finishPasskeyRegistration = onCall(options, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  if (!canManagePasskeyCredentials(auth.token, auth.permissions)) {
    throw new HttpsError("permission-denied", "Sign in again to add a passkey.");
  }
  const requestID = stringField(request.data?.requestID, 80);
  const response = registrationResponse(request.data?.credential);
  const challengeRef = challenges.doc(requestID);
  const challenge = await challengeRef.get();
  const expectedChallenge = validChallenge(challenge.data(), "registration");
  if (challenge.get("uid") !== auth.uid) {
    throw new HttpsError("permission-denied", "Passkey request belongs to another account.");
  }
  let verification;
  try {
    verification = await verifyRegistrationResponse({
      response, expectedChallenge, expectedOrigin: origin, expectedRPID: rpID,
      requireUserVerification: true, supportedAlgorithmIDs: [-7],
    });
  } catch {
    throw new HttpsError("invalid-argument", "Passkey verification failed.");
  }
  if (!verification.verified) {
    throw new HttpsError("invalid-argument", "Passkey verification failed.");
  }
  const account = await adminAuth.getUser(auth.uid);
  if (account.disabled || !account.emailVerified) {
    throw new HttpsError("permission-denied", "Account is not available.");
  }
  const key = verification.registrationInfo.credential;
  const credentialRef = credentials.doc(credentialKey(key.id));
  await db.runTransaction(async (tx) => {
    const [freshChallenge, existingKey, profile] = await Promise.all([
      tx.get(challengeRef), tx.get(credentialRef), tx.get(db.collection("users").doc(auth.uid)),
    ]);
    validChallenge(freshChallenge.data(), "registration");
    if (freshChallenge.get("uid") !== auth.uid || !profile.exists ||
        !isActiveUser(userPermissionSnapshotFromData(auth.uid, profile.data()!))) {
      throw new HttpsError("permission-denied", "Account is no longer eligible.");
    }
    if (existingKey.exists) {
      throw new HttpsError("already-exists", "This passkey is already registered.");
    }
    if (typeof profile.get("passkeyEpoch") !== "string") {
      tx.update(profile.ref, {passkeyEpoch: randomUUID()});
    }
    tx.create(credentialRef, {
      uid: auth.uid, id: key.id, publicKey: Buffer.from(key.publicKey).toString("base64"),
      counter: key.counter, createdAt: FieldValue.serverTimestamp(),
    });
    tx.delete(challengeRef);
  });
  return {registered: true};
});

export const beginPasskeySignIn = onCall(options, async () => {
  const generated = await generateAuthenticationOptions({
    rpID, userVerification: "required", timeout: challengeLifetimeMs,
  });
  const requestID = randomUUID();
  await challenges.doc(requestID).create({
    kind: "authentication", challenge: generated.challenge,
    expiresAt: Timestamp.fromMillis(Date.now() + challengeLifetimeMs),
  });
  return {requestID, challenge: generated.challenge, rpID};
});

export const finishPasskeySignIn = onCall(options, async (request) => {
  const requestID = stringField(request.data?.requestID, 80);
  const response = authenticationResponse(request.data?.credential);
  const challengeRef = challenges.doc(requestID);
  const credentialRef = credentials.doc(credentialKey(response.id));
  const [challenge, key] = await Promise.all([challengeRef.get(), credentialRef.get()]);
  const expectedChallenge = validChallenge(challenge.data(), "authentication");
  if (!key.exists || key.get("id") !== response.id) {
    throw new HttpsError("permission-denied", "Passkey is not registered.");
  }
  const uid = stringField(key.get("uid"), 128);
  const profile = await db.collection("users").doc(uid).get();
  const account = await adminAuth.getUser(uid);
  if (!profile.exists || !isActiveUser(userPermissionSnapshotFromData(uid, profile.data()!)) ||
      account.disabled || !account.emailVerified) {
    throw new HttpsError("permission-denied", "Account is not available.");
  }
  const passkeyEpoch = stringField(profile.get("passkeyEpoch"), 80);
  let verification;
  try {
    verification = await verifyAuthenticationResponse({
      response, expectedChallenge, expectedOrigin: origin, expectedRPID: rpID,
      credential: {
        id: response.id,
        publicKey: Buffer.from(stringField(key.get("publicKey"), 8192), "base64"),
        counter: key.get("counter") as number,
      },
      requireUserVerification: true,
    });
  } catch {
    throw new HttpsError("permission-denied", "Passkey verification failed.");
  }
  if (!verification.verified) {
    throw new HttpsError("permission-denied", "Passkey verification failed.");
  }
  await db.runTransaction(async (tx) => {
    const [freshChallenge, freshKey, freshProfile] = await Promise.all([
      tx.get(challengeRef), tx.get(credentialRef), tx.get(db.collection("users").doc(uid)),
    ]);
    validChallenge(freshChallenge.data(), "authentication");
    if (!freshKey.exists || freshKey.get("uid") !== uid ||
        freshKey.get("counter") !== key.get("counter") ||
        !freshProfile.exists || !isActiveUser(userPermissionSnapshotFromData(uid, freshProfile.data()!))) {
      throw new HttpsError("failed-precondition", "Passkey request changed. Try again.");
    }
    tx.update(credentialRef, {
      counter: verification.authenticationInfo.newCounter,
      lastUsedAt: FieldValue.serverTimestamp(),
    });
    tx.delete(challengeRef);
  });
  // This claim belongs to the signed-in session. It is never set as a
  // persistent user claim, which would unlock other devices without a passkey.
  const token = await adminAuth.createCustomToken(uid, {
    uac_passkey_verified: true, uac_passkey_epoch: passkeyEpoch,
  });
  return {token};
});

export const listMyPasskeys = onCall(options, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  const keys = await credentials.where("uid", "==", auth.uid).get();
  return {
    count: keys.size,
    passkeys: keys.docs.map((key) => ({
      id: key.id,
      createdAt: (key.get("createdAt") as Timestamp | undefined)?.toDate().toISOString() ?? null,
    })),
  };
});

export const removeMyPasskey = onCall(options, async (request) => {
  const auth = await requireVerifiedActiveUser(request);
  if (!canManagePasskeyCredentials(auth.token, auth.permissions)) {
    throw new HttpsError("permission-denied", "Sign in again to remove a passkey.");
  }
  const id = stringField(request.data?.id, 64);
  if (!/^[0-9a-f]{64}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Invalid passkey ID.");
  }
  const keyRef = credentials.doc(id);
  const userRef = db.collection("users").doc(auth.uid);
  await db.runTransaction(async (tx) => {
    const [key, user] = await Promise.all([tx.get(keyRef), tx.get(userRef)]);
    if (!key.exists || key.get("uid") !== auth.uid || !user.exists ||
        !isActiveUser(userPermissionSnapshotFromData(auth.uid, user.data()!))) {
      throw new HttpsError("not-found", "Passkey not found.");
    }
    tx.delete(keyRef);
    // All passkey sessions become invalid in Rules and Functions immediately.
    tx.update(userRef, {passkeyEpoch: randomUUID()});
  });
  return {removed: true};
});

export const cleanupExpiredPasskeyChallenges = onSchedule(
  {schedule: "every 60 minutes", region: "europe-west3", maxInstances: 1},
  async () => {
    for (let page = 0; page < 10; page++) {
      const expired = await challenges.where("expiresAt", "<=", Timestamp.now()).limit(500).get();
      if (expired.empty) break;
      const batch = db.batch();
      expired.docs.forEach((item) => batch.delete(item.ref));
      await batch.commit();
      if (expired.size < 500) break;
    }
  }
);
