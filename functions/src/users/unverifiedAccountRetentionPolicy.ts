import {createHash} from "node:crypto";
import {Timestamp, type DocumentData} from "firebase-admin/firestore";

export const unverifiedAccountRetentionDays = 30;
export const unverifiedAccountQuietDays = 7;
const dayMilliseconds = 86_400_000;

/** Deliberately excludes credentials, password hashes and OAuth tokens. */
export interface RetentionAuthIdentity {
  uid: string;
  email?: string;
  emailVerified: boolean;
  disabled: boolean;
  createdAt: string;
  lastSignInAt?: string;
  lastRefreshAt?: string;
  providerIds: readonly string[];
  hasCustomClaims: boolean;
  hasMFA: boolean;
  hasPhone: boolean;
  hasPhoto: boolean;
}

export type RetentionSkipReason =
  | "verified" | "tooYoung" | "recentSession" | "protectedIdentity"
  | "invalidMetadata" | "changedProfile" | "relatedData" | "missingIdentity";

export function authRetentionSkipReason(
  user: RetentionAuthIdentity, now: number
): RetentionSkipReason | undefined {
  if (user.emailVerified) return "verified";
  if (!user.uid || user.uid.length > 128 || /[\/\u0000]/.test(user.uid)
      || user.uid === "." || user.uid === ".." || /^__.*__$/.test(user.uid)
      || !user.email?.trim()) return "invalidMetadata";
  if (user.disabled || user.hasCustomClaims || user.hasMFA || user.hasPhone || user.hasPhoto
      || user.providerIds.length !== 1 || user.providerIds[0] !== "password") return "protectedIdentity";
  const created = Date.parse(user.createdAt);
  const sessionDates = [user.lastSignInAt, user.lastRefreshAt]
    .filter((value): value is string => value !== undefined).map(Date.parse);
  if (!Number.isFinite(now) || !Number.isFinite(created) || created > now
      || sessionDates.some((value) => !Number.isFinite(value) || value > now
        || value < created - 1_000)) return "invalidMetadata";
  if (created > now - unverifiedAccountRetentionDays * dayMilliseconds) return "tooYoung";
  if (sessionDates.some((value) => value > now - unverifiedAccountQuietDays * dayMilliseconds)) return "recentSession";
  return undefined;
}

// Exact initial registration schema. Unknown/legacy fields are a reason for
// review, not permission to silently delete a previously used account.
const initialProfileFields = new Set([
  "id", "fullName", "displayName", "city", "email", "bio", "telegramUsername",
  "isBlocked", "blockState", "globalRole", "selectedFederalState", "accountStatus",
  "warningCount", "communityMemberships", "acceptedTermsAt", "acceptedPrivacyAt",
  "acceptedTermsVersion", "acceptedPrivacyVersion", "termsVersion", "privacyVersion",
  "minimumAgeConfirmedAt", "minimumAgeVersion", "createdAt", "updatedAt",
]);

export function profileRetentionSkipReason(
  identity: RetentionAuthIdentity, data: DocumentData | undefined, now: number
): RetentionSkipReason | undefined {
  // An Auth identity whose registration never created a profile can also expire.
  // The adapter still checks dangling children, public profiles and references.
  if (data === undefined) return undefined;
  const created = data.createdAt;
  const updated = data.updatedAt;
  if (Object.keys(data).some((key) => !initialProfileFields.has(key))
      || data.id !== identity.uid || typeof data.email !== "string"
      || data.email.trim().toLowerCase() !== identity.email?.trim().toLowerCase()
      || data.globalRole !== "user" || data.accountStatus !== "active"
      || data.blockState !== "active" || data.isBlocked !== false
      || data.warningCount !== 0 || !Array.isArray(data.communityMemberships)
      || data.communityMemberships.length !== 0
      || !(created instanceof Timestamp) || !(updated instanceof Timestamp)
      || !created.isEqual(updated)) return "changedProfile";
  const authCreated = Date.parse(identity.createdAt);
  if (created.toMillis() < authCreated - 60_000
      || created.toMillis() > authCreated + dayMilliseconds
      || created.toMillis() > now - unverifiedAccountRetentionDays * dayMilliseconds) return "changedProfile";
  return undefined;
}

export function retentionIdentityFingerprint(identity: RetentionAuthIdentity): string {
  return createHash("sha256").update(JSON.stringify([
    identity.uid, identity.email?.trim().toLowerCase(), identity.emailVerified,
    identity.disabled, identity.createdAt, identity.lastSignInAt ?? null,
    identity.lastRefreshAt ?? null, [...identity.providerIds].sort(),
    identity.hasCustomClaims, identity.hasMFA, identity.hasPhone, identity.hasPhoto,
  ])).digest("hex");
}
