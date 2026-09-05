import {randomUUID} from "node:crypto";
import type {UserRecord} from "firebase-admin/auth";
import type {Query} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {adminAuth, adminStorage, db} from "../firebase/admin";
import {analyticsUserActivityCollection} from "../analytics/analyticsUserActivity";
import {accountDeletionReferencePolicies, type AccountDeletionReferencePolicy} from "./accountDeletionPolicy";
import {
  authRetentionSkipReason, type RetentionAuthIdentity,
  unverifiedAccountQuietDays, unverifiedAccountRetentionDays,
} from "./unverifiedAccountRetentionPolicy";
import {UnverifiedRetentionStore} from "./unverifiedAccountRetentionStore";
import {
  executeUnverifiedDeletion, inspectUnverifiedAccount,
  type UnverifiedRetentionDependencies,
} from "./unverifiedAccountRetentionWorker";

export type UnverifiedRetentionMode = "off" | "report" | "apply";

export function retentionMode(value: string | undefined): UnverifiedRetentionMode {
  const mode = value ?? "off";
  if (mode !== "off" && mode !== "report" && mode !== "apply") {
    throw new Error("Invalid UNVERIFIED_ACCOUNT_RETENTION_MODE");
  }
  return mode;
}

export function retentionIdentity(user: UserRecord): RetentionAuthIdentity {
  return {
    uid: user.uid, email: user.email, emailVerified: user.emailVerified, disabled: user.disabled,
    createdAt: user.metadata.creationTime, lastSignInAt: user.metadata.lastSignInTime || undefined,
    lastRefreshAt: user.metadata.lastRefreshTime || undefined,
    providerIds: user.providerData.map((provider) => provider.providerId),
    hasCustomClaims: Object.keys(user.customClaims ?? {}).length > 0,
    hasMFA: (user.multiFactor?.enrolledFactors.length ?? 0) > 0,
    hasPhone: Boolean(user.phoneNumber), hasPhoto: Boolean(user.photoURL),
  };
}

function isMissingUser(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error
    && error.code === "auth/user-not-found";
}

async function getIdentity(uid: string): Promise<RetentionAuthIdentity | undefined> {
  try { return retentionIdentity(await adminAuth.getUser(uid)); }
  catch (error) { if (isMissingUser(error)) return undefined; throw error; }
}

/** Errors (including missing indexes/permissions) propagate; never infer absence. */
export async function hasUnverifiedAccountRelatedData(uid: string): Promise<boolean> {
  for (const collection of ["publicProfiles", analyticsUserActivityCollection]) {
    if ((await db.collection(collection).doc(uid).get()).exists) return true;
  }
  // listCollections also finds child collections under an absent parent document.
  if ((await db.collection("users").doc(uid).listCollections()).length > 0) return true;
  const directReferences = [
    ["organizations", "ownerId"], ["organizationCreationProofs", "userId"],
    ["likes", "userId"], ["registrations", "userId"], ["feedback", "userId"],
  ];
  for (const [collection, field] of directReferences) {
    if (!(await db.collection(collection).where(field, "==", uid).limit(1).get()).empty) return true;
  }
  for (const policy of accountDeletionReferencePolicies as readonly AccountDeletionReferencePolicy[]) {
    let query: Query = policy.scope === "collection" ? db.collection(policy.collection)
      : db.collectionGroup(policy.collection);
    query = query.where(policy.field, policy.operator, uid);
    for (const filter of policy.filters ?? []) query = query.where(filter.field, filter.operator, filter.value);
    if (!(await query.limit(1).get()).empty) return true;
  }
  for (const prefix of [`profileImages/${uid}/`, `users/${uid}/`]) {
    const [files] = await adminStorage.bucket().getFiles({prefix, maxResults: 1, autoPaginate: false});
    if (files.length > 0) return true;
  }
  return false;
}

function dependencies(store: UnverifiedRetentionStore): UnverifiedRetentionDependencies {
  return {
    now: Date.now, getIdentity, getProfile: (uid) => store.getProfile(uid),
    hasRelatedData: hasUnverifiedAccountRelatedData,
    claimJob: (job) => store.claimJob(job), setJobStatus: (uid, status) => store.setJobStatus(uid, status),
    assertLease: () => store.assertLease(),
    deleteIdentity: async (uid) => {
      try { await adminAuth.deleteUser(uid); }
      catch (error) { if (!isMissingUser(error)) throw error; }
    },
    deleteProfileIfUnchanged: (uid, version) => store.deleteProfileIfUnchanged(uid, version),
  };
}

export interface UnverifiedRetentionResult {
  mode: UnverifiedRetentionMode;
  scanned: number;
  candidates: number;
  completed: number;
  resumed: number;
  manualReview: number;
  skipped: Record<string, number>;
  scanComplete: boolean;
  busy: boolean;
  /** Opaque continuation for a read-only preflight, deliberately excluded from logs. */
  continuationToken?: string;
}

/** report is strictly read-only; off does not even enumerate Auth identities. */
export async function runUnverifiedAccountRetention(
  mode: UnverifiedRetentionMode, reportPageToken?: string
): Promise<UnverifiedRetentionResult> {
  retentionMode(mode);
  const result: UnverifiedRetentionResult = {mode, scanned: 0, candidates: 0, completed: 0,
    resumed: 0, manualReview: 0, skipped: {}, scanComplete: false, busy: false};
  if (mode === "off") return result;
  const store = new UnverifiedRetentionStore(db, randomUUID());
  let cursor: string | undefined = mode === "report" ? reportPageToken : undefined;
  if (mode === "apply") {
    const lease = await store.acquire();
    if (!lease) return {...result, busy: true};
    cursor = lease.cursor;
  }
  const worker = dependencies(store);
  result.continuationToken = cursor;
  const deadline = Date.now() + 4 * 60_000;
  const skip = (reason: string) => { result.skipped[reason] = (result.skipped[reason] ?? 0) + 1; };
  try {
    if (mode === "apply") {
      for (const job of await store.pendingJobs()) {
        if (Date.now() >= deadline) return result;
        const outcome = await executeUnverifiedDeletion(job, worker, true);
        result.resumed += 1;
        if (outcome === "completed") result.completed += 1;
        if (outcome === "manualReview") result.manualReview += 1;
      }
      await store.pruneReceipts();
    }
    // At most 500 Auth records per invocation. Apply persists complete pages;
    // an interrupted page is revisited, with journaled work resumed first.
    for (let page = 0; page < 5; page += 1) {
      const batch = await adminAuth.listUsers(100, cursor);
      for (const user of batch.users) {
        if (Date.now() >= deadline) return result;
        result.scanned += 1;
        const reason = authRetentionSkipReason(retentionIdentity(user), Date.now());
        if (reason) { skip(reason); continue; }
        const candidate = await inspectUnverifiedAccount(user.uid, worker);
        if (!candidate.eligible) { skip(candidate.reason); continue; }
        result.candidates += 1;
        if (mode === "report") continue;
        const outcome = await executeUnverifiedDeletion(candidate.job, worker);
        if (outcome === "completed") result.completed += 1;
        else if (outcome === "manualReview") result.manualReview += 1;
        else skip("changedOrJournaled");
      }
      cursor = batch.pageToken;
      result.continuationToken = cursor;
      if (mode === "apply") await store.checkpoint(cursor);
      if (!cursor) { result.scanComplete = true; break; }
    }
    return result;
  } finally {
    if (mode === "apply") await store.release();
  }
}

export const cleanupUnverifiedAccounts = onSchedule({
  schedule: "43 4 * * *", timeZone: "Europe/Vienna", region: "europe-west3",
  timeoutSeconds: 540, memory: "256MiB", maxInstances: 1, concurrency: 1, retryCount: 0,
}, async () => {
  const mode = retentionMode(process.env.UNVERIFIED_ACCOUNT_RETENTION_MODE);
  const result = await runUnverifiedAccountRetention(mode);
  const {continuationToken: _continuationToken, ...summary} = result;
  logger.info("Unverified account retention cycle", {
    ...summary, retentionDays: unverifiedAccountRetentionDays, quietDays: unverifiedAccountQuietDays,
  });
  if (result.manualReview > 0) logger.error("Unverified retention needs manual reconciliation", {
    count: result.manualReview,
  });
});
