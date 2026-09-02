const privilegedRoles = new Set(["owner", "admin"]);

export function parsePrivilegedMFARecoveryOptions(argumentsList) {
  const values = new Map();
  let apply = false;
  for (const argument of argumentsList) {
    if (argument === "--apply") {
      apply = true;
    } else if (argument.startsWith("--") && argument.includes("=")) {
      const separator = argument.indexOf("=");
      values.set(argument.slice(2, separator), argument.slice(separator + 1));
    } else {
      throw new Error(`Unsupported argument: ${argument}`);
    }
  }

  const projectId = requiredValue(values.get("project"), "--project");
  const actorEmail = normalizedEmail(values.get("actor-email"), "--actor-email");
  const targetEmail = normalizedEmail(values.get("target-email"), "--target-email");
  const reason = requiredValue(values.get("reason"), "--reason");
  if (reason.length < 10 || reason.length > 300) {
    throw new Error("--reason must contain between 10 and 300 characters.");
  }

  let expectations;
  if (apply) {
    if (values.get("confirm-project") !== projectId) {
      throw new Error("--apply requires --confirm-project to exactly match --project.");
    }
    if (normalizedEmail(values.get("confirm-email"), "--confirm-email") !== targetEmail) {
      throw new Error("--apply requires --confirm-email to exactly match --target-email.");
    }
    expectations = {
      uid: requiredValue(values.get("confirm-uid"), "--confirm-uid"),
      factorCount: nonNegativeInteger(values.get("expect-factors"), "--expect-factors"),
      requiresMultiFactorAuth: strictBoolean(
        values.get("expect-required"),
        "--expect-required"
      ),
    };
  }

  const supportedKeys = new Set([
    "project",
    "actor-email",
    "target-email",
    "reason",
    "confirm-project",
    "confirm-email",
    "confirm-uid",
    "expect-factors",
    "expect-required",
  ]);
  for (const key of values.keys()) {
    if (!supportedKeys.has(key)) throw new Error(`Unsupported option: --${key}`);
  }

  return {projectId, actorEmail, targetEmail, reason, apply, expectations};
}

export function inspectPrivilegedMFARecovery(authUser, firestoreUser) {
  const uid = requiredValue(authUser?.localId, "Auth user UID");
  const authEmail = normalizedEmail(authUser?.email, "Auth user email");
  const firestoreEmail = normalizedEmail(firestoreUser?.email, "Firestore user email");
  if (authEmail !== firestoreEmail) {
    throw new Error("Auth and Firestore email addresses do not match.");
  }

  const role = normalizedString(firestoreUser?.globalRole);
  const factors = Array.isArray(authUser?.mfaInfo) ? authUser.mfaInfo : [];
  return {
    uid,
    email: authEmail,
    role,
    accountStatus: normalizedString(firestoreUser?.accountStatus),
    blockState: normalizedString(firestoreUser?.blockState),
    emailVerified: authUser?.emailVerified === true,
    disabled: authUser?.disabled === true,
    requiresMultiFactorAuth: firestoreUser?.requiresMultiFactorAuth === true,
    factorCount: factors.length,
    factorTypes: [...new Set(factors.map(factorType))].sort(),
  };
}

export function assertPrivilegedMFARecoverySafe(snapshot, options) {
  if (snapshot.email !== options.targetEmail) {
    throw new Error("The resolved Auth user does not match --target-email.");
  }
  if (!privilegedRoles.has(snapshot.role)) {
    throw new Error("Recovery is limited to an app owner or admin.");
  }
  if (snapshot.disabled || snapshot.accountStatus !== "active" ||
      (snapshot.blockState && snapshot.blockState !== "active")) {
    throw new Error("Recovery requires an active, unblocked Auth and app account.");
  }
  if (!snapshot.emailVerified) {
    throw new Error("Recovery requires a verified email address.");
  }
  if (!snapshot.requiresMultiFactorAuth && snapshot.factorCount === 0) {
    throw new Error("The account has no privileged MFA protection to recover.");
  }
  if (!options.apply) return;

  if (snapshot.uid !== options.expectations.uid ||
      snapshot.factorCount !== options.expectations.factorCount ||
      snapshot.requiresMultiFactorAuth !== options.expectations.requiresMultiFactorAuth) {
    throw new Error("Recovery preflight changed. No writes were made; run a fresh dry-run.");
  }
}

export function buildPrivilegedMFARecoveryWrite({
  documentName,
  updateTime,
  actorEmail,
  reason,
}) {
  const actor = normalizedEmail(actorEmail, "Firebase CLI actor email");
  const normalizedReason = requiredValue(reason, "Recovery reason");
  if (!documentName?.includes("/documents/users/") || !updateTime) {
    throw new Error("Recovery write requires a current users document.");
  }
  return {
    update: {
      name: documentName,
      fields: {
        requiresMultiFactorAuth: {booleanValue: false},
        multiFactorAuthRecoveryActor: {stringValue: actor},
        multiFactorAuthRecoveryReason: {stringValue: normalizedReason},
      },
    },
    updateMask: {fieldPaths: [
      "requiresMultiFactorAuth",
      "multiFactorAuthRequiredAt",
      "multiFactorAuthRequiredMethod",
      "multiFactorAuthRecoveryActor",
      "multiFactorAuthRecoveryReason",
    ]},
    updateTransforms: [
      {fieldPath: "multiFactorAuthRecoveryAt", setToServerValue: "REQUEST_TIME"},
      {fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME"},
    ],
    currentDocument: {updateTime},
  };
}

export function verifyPrivilegedMFARecovery(snapshot, firestoreUser) {
  return snapshot.factorCount === 0 &&
    snapshot.requiresMultiFactorAuth === false &&
    firestoreUser?.multiFactorAuthRequiredAt === undefined &&
    firestoreUser?.multiFactorAuthRequiredMethod === undefined &&
    typeof firestoreUser?.multiFactorAuthRecoveryAt === "string" &&
    typeof firestoreUser?.multiFactorAuthRecoveryActor === "string" &&
    typeof firestoreUser?.multiFactorAuthRecoveryReason === "string";
}

export function redactEmail(email) {
  const normalized = normalizedEmail(email, "email");
  const [localPart, domain] = normalized.split("@");
  return `${localPart.slice(0, 1)}***@${domain}`;
}

function factorType(value) {
  if (value?.totpInfo) return "totp";
  if (value?.phoneInfo) return "phone";
  return "unknown";
}

function normalizedEmail(value, name) {
  const normalized = requiredValue(value, name).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    throw new Error(`${name} must be a valid email address.`);
  }
  return normalized;
}

function normalizedString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function requiredValue(value, name) {
  const normalized = normalizedString(value);
  if (!normalized) throw new Error(`${name} is required.`);
  return normalized;
}

function nonNegativeInteger(value, name) {
  if (!/^\d+$/.test(value ?? "")) {
    throw new Error(`${name} must be a non-negative integer.`);
  }
  return Number(value);
}

function strictBoolean(value, name) {
  if (value === "true") return true;
  if (value === "false") return false;
  throw new Error(`${name} must be true or false.`);
}
