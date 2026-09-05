import {
  authRetentionSkipReason, profileRetentionSkipReason, retentionIdentityFingerprint,
  type RetentionAuthIdentity, type RetentionSkipReason,
} from "./unverifiedAccountRetentionPolicy";
import type {DocumentData} from "firebase-admin/firestore";

export interface RetentionProfileSnapshot {
  data?: DocumentData;
  /** Exact seconds/nanoseconds, not a Date round-trip. null means absent. */
  version: string | null;
}

export interface RetentionDeletionJob {
  uid: string;
  identityFingerprint: string;
  profileVersion: string | null;
  status: "authDeletePending" | "authDeleted" | "completed" | "cancelled" | "manualReview";
}

export interface UnverifiedRetentionDependencies {
  now(): number;
  getIdentity(uid: string): Promise<RetentionAuthIdentity | undefined>;
  getProfile(uid: string): Promise<RetentionProfileSnapshot>;
  hasRelatedData(uid: string): Promise<boolean>;
  /** Must atomically claim the job and compare the exact profile version. */
  claimJob(job: RetentionDeletionJob): Promise<boolean>;
  setJobStatus(uid: string, status: RetentionDeletionJob["status"]): Promise<void>;
  /** Rechecks the run lease before any destructive request. */
  assertLease(): Promise<void>;
  deleteIdentity(uid: string): Promise<void>;
  /** Deletes only the unchanged root document, never recursively. */
  deleteProfileIfUnchanged(uid: string, version: string | null): Promise<boolean>;
}

export type RetentionInspection =
  | {eligible: false; reason: RetentionSkipReason}
  | {eligible: true; job: RetentionDeletionJob};

export async function inspectUnverifiedAccount(
  uid: string, dependencies: UnverifiedRetentionDependencies
): Promise<RetentionInspection> {
  const identity = await dependencies.getIdentity(uid);
  if (!identity) return {eligible: false, reason: "missingIdentity"};
  const authReason = authRetentionSkipReason(identity, dependencies.now());
  if (authReason) return {eligible: false, reason: authReason};
  const profile = await dependencies.getProfile(uid);
  const profileReason = profileRetentionSkipReason(identity, profile.data, dependencies.now());
  if (profileReason) return {eligible: false, reason: profileReason};
  if (await dependencies.hasRelatedData(uid)) return {eligible: false, reason: "relatedData"};
  return {eligible: true, job: {
    uid, identityFingerprint: retentionIdentityFingerprint(identity),
    profileVersion: profile.version, status: "authDeletePending",
  }};
}

/** Auth is removed first: Firestore data is never erased while Auth deletion
 * is uncertain. A persisted job lets the next run finish an interrupted cleanup.
 * Auth has no compare-and-delete API: the last fresh read reduces, but cannot
 * eliminate, a concurrent email-verification race. See the deployment gate. */
export async function executeUnverifiedDeletion(
  job: RetentionDeletionJob, dependencies: UnverifiedRetentionDependencies,
  resume = false
): Promise<"completed" | "skipped" | "manualReview"> {
  if (job.status !== "authDeletePending" && job.status !== "authDeleted") return "skipped";
  if (!resume && !await dependencies.claimJob(job)) return "skipped";
  await dependencies.assertLease();
  let identity = await dependencies.getIdentity(job.uid);
  if (identity && job.status === "authDeleted") {
    // Never delete a recreated Auth identity while finishing an older job.
    await dependencies.setJobStatus(job.uid, "manualReview");
    return "manualReview";
  }
  if (identity) {
    const fresh = await inspectUnverifiedAccount(job.uid, dependencies);
    if (!fresh.eligible || fresh.job.identityFingerprint !== job.identityFingerprint
        || fresh.job.profileVersion !== job.profileVersion) {
      await dependencies.setJobStatus(job.uid, "cancelled");
      return "skipped";
    }
    await dependencies.assertLease();
    // This is deliberately the last remote read before the delete request.
    identity = await dependencies.getIdentity(job.uid);
    if (identity && (authRetentionSkipReason(identity, dependencies.now())
        || retentionIdentityFingerprint(identity) !== job.identityFingerprint)) {
      await dependencies.setJobStatus(job.uid, "cancelled");
      return "skipped";
    }
    if (identity) await dependencies.deleteIdentity(job.uid);
  }
  // A timed-out Auth deletion is not success. Reread on this or the next run.
  if (await dependencies.getIdentity(job.uid)) throw new Error("Auth deletion read-back failed");
  await dependencies.setJobStatus(job.uid, "authDeleted");
  await dependencies.assertLease();
  if (await dependencies.hasRelatedData(job.uid)
      || await dependencies.getIdentity(job.uid)
      || !await dependencies.deleteProfileIfUnchanged(job.uid, job.profileVersion)) {
    await dependencies.setJobStatus(job.uid, "manualReview");
    return "manualReview";
  }
  const profile = await dependencies.getProfile(job.uid);
  if (profile.data !== undefined || await dependencies.getIdentity(job.uid)) {
    await dependencies.setJobStatus(job.uid, "manualReview");
    return "manualReview";
  }
  await dependencies.setJobStatus(job.uid, "completed");
  return "completed";
}
