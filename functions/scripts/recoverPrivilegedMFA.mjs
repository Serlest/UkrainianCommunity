import {firebaseCliCredential} from "./firebaseCliCredential.mjs";
import {
  assertPrivilegedMFARecoverySafe,
  buildPrivilegedMFARecoveryWrite,
  inspectPrivilegedMFARecovery,
  parsePrivilegedMFARecoveryOptions,
  redactEmail,
  verifyPrivilegedMFARecovery,
} from "./privilegedMFARecoveryCore.mjs";

const options = parsePrivilegedMFARecoveryOptions(process.argv.slice(2));
const credential = await firebaseCliCredential({accountEmail: options.actorEmail});
const actorEmail = credential.accountEmail;

const before = await readRecoveryState();
assertPrivilegedMFARecoverySafe(before.snapshot, options);

if (options.apply) {
  await clearFirestoreRequirement(before.document);
  await removeAuthFactorsAndRevokeSessions(before.snapshot.uid);
  const after = await readRecoveryState();
  if (!verifyPrivilegedMFARecovery(after.snapshot, after.document.data)) {
    throw new Error("Privileged MFA recovery read-back failed.");
  }
  printResult("applied", after.snapshot);
} else {
  printResult("dry-run", before.snapshot);
}

async function readRecoveryState() {
  const authUser = await lookupAuthUser(options.targetEmail);
  const document = await getFirestoreUser(authUser.localId);
  const snapshot = inspectPrivilegedMFARecovery(authUser, document.data);
  return {authUser, document, snapshot};
}

async function lookupAuthUser(email) {
  const response = await authorizedRequest(
    `https://identitytoolkit.googleapis.com/v1/projects/${options.projectId}/accounts:lookup`,
    {method: "POST", body: JSON.stringify({email: [email]})}
  );
  if (!Array.isArray(response.users) || response.users.length !== 1) {
    throw new Error("Expected exactly one Firebase Auth user for --target-email.");
  }
  return response.users[0];
}

async function getFirestoreUser(uid) {
  const name = `projects/${options.projectId}/databases/(default)/documents/users/${uid}`;
  const response = await authorizedRequest(`https://firestore.googleapis.com/v1/${name}`);
  if (response.name !== name || typeof response.updateTime !== "string") {
    throw new Error("Firestore returned an unexpected user document.");
  }
  return {
    name: response.name,
    updateTime: response.updateTime,
    data: Object.fromEntries(Object.entries(response.fields ?? {}).map(
      ([key, value]) => [key, decodeFirestoreValue(value)]
    )),
  };
}

async function clearFirestoreRequirement(document) {
  const write = buildPrivilegedMFARecoveryWrite({
    documentName: document.name,
    updateTime: document.updateTime,
    actorEmail,
    reason: options.reason,
  });
  await authorizedRequest(
    `https://firestore.googleapis.com/v1/projects/${options.projectId}` +
      "/databases/(default)/documents:commit",
    {method: "POST", body: JSON.stringify({writes: [write]})}
  );
}

async function removeAuthFactorsAndRevokeSessions(uid) {
  await authorizedRequest(
    `https://identitytoolkit.googleapis.com/v1/projects/${options.projectId}/accounts:update`,
    {
      method: "POST",
      body: JSON.stringify({
        localId: uid,
        mfa: {},
        validSince: Math.floor(Date.now() / 1000),
      }),
    }
  );
}

async function authorizedRequest(url, settings = {}) {
  const token = await credential.getAccessToken();
  const headers = new Headers(settings.headers ?? {});
  headers.set("Authorization", `Bearer ${token.access_token}`);
  if (settings.body) headers.set("Content-Type", "application/json");
  const response = await fetch(url, {...settings, headers});
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Recovery request failed (${response.status}): ${safeErrorText(text)}`);
  }
  return response.json();
}

function decodeFirestoreValue(value) {
  if (!value || typeof value !== "object") return undefined;
  if ("nullValue" in value) return null;
  if ("stringValue" in value) return value.stringValue;
  if ("timestampValue" in value) return value.timestampValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeFirestoreValue);
  }
  if ("mapValue" in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(
      ([key, item]) => [key, decodeFirestoreValue(item)]
    ));
  }
  return undefined;
}

function safeErrorText(value) {
  return String(value).replace(/Bearer\s+[^\s"']+/gi, "Bearer [redacted]").slice(0, 800);
}

function printResult(mode, snapshot) {
  console.log(JSON.stringify({
    projectId: options.projectId,
    mode,
    actor: redactEmail(actorEmail),
    target: {
      email: redactEmail(snapshot.email),
      uid: snapshot.uid,
      role: snapshot.role,
      accountStatus: snapshot.accountStatus,
      emailVerified: snapshot.emailVerified,
      disabled: snapshot.disabled,
      requiresMultiFactorAuth: snapshot.requiresMultiFactorAuth,
      factorCount: snapshot.factorCount,
      factorTypes: snapshot.factorTypes,
    },
    next: mode === "dry-run"
      ? "Repeat with --apply and the exact confirmation values from this dry-run."
      : "All enrolled MFA factors were removed and existing sessions were revoked.",
  }, null, 2));
}
