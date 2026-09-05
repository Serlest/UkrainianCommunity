import {Timestamp, type DocumentSnapshot, type Firestore, type Transaction} from "firebase-admin/firestore";
import type {RetentionDeletionJob, RetentionProfileSnapshot} from "./unverifiedAccountRetentionWorker";

export const unverifiedRetentionCollections = {
  control: "unverifiedAccountRetentionControl",
  jobs: "unverifiedAccountDeletionJobs",
} as const;
const leaseMilliseconds = 15 * 60_000; // Longer than the deployed invocation timeout.
const receiptMilliseconds = 90 * 86_400_000;

export function exactProfileVersion(snapshot: DocumentSnapshot): string | null {
  const version = snapshot.updateTime;
  return version ? `${version.seconds}:${version.nanoseconds}` : null;
}

/** Private Admin-only journal; no recursive deletion and no credentials/email. */
export class UnverifiedRetentionStore {
  private readonly control;
  private readonly jobs;

  constructor(private readonly db: Firestore, private readonly owner: string,
    private readonly now: () => number = Date.now) {
    this.control = db.collection(unverifiedRetentionCollections.control).doc("daily");
    this.jobs = db.collection(unverifiedRetentionCollections.jobs);
  }

  async acquire(): Promise<{cursor: string | undefined} | undefined> {
    return this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(this.control);
      const expires = snapshot.get("expiresAt");
      if (expires instanceof Timestamp && expires.toMillis() > this.now()) return undefined;
      const cursor = snapshot.get("cursor");
      transaction.set(this.control, {
        owner: this.owner, expiresAt: Timestamp.fromMillis(this.now() + leaseMilliseconds),
      }, {merge: true});
      return {cursor: typeof cursor === "string" ? cursor : undefined};
    });
  }

  private validateLease(snapshot: DocumentSnapshot): void {
    const expires = snapshot.get("expiresAt");
    if (snapshot.get("owner") !== this.owner || !(expires instanceof Timestamp)
        || expires.toMillis() <= this.now()) throw new Error("Unverified retention lease lost");
  }

  private async checkTransactionLease(transaction: Transaction): Promise<void> {
    this.validateLease(await transaction.get(this.control));
  }

  async assertLease(): Promise<void> {
    this.validateLease(await this.control.get());
  }

  async checkpoint(cursor: string | undefined): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      await this.checkTransactionLease(transaction);
      transaction.update(this.control, {cursor: cursor ?? null, updatedAt: Timestamp.fromMillis(this.now())});
    });
  }

  async release(): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(this.control);
      if (snapshot.get("owner") !== this.owner) return;
      transaction.update(this.control, {owner: null, expiresAt: Timestamp.fromMillis(0)});
    });
  }

  async getProfile(uid: string): Promise<RetentionProfileSnapshot> {
    const snapshot = await this.db.collection("users").doc(uid).get();
    return {data: snapshot.data(), version: exactProfileVersion(snapshot)};
  }

  async claimJob(job: RetentionDeletionJob): Promise<boolean> {
    return this.db.runTransaction(async (transaction) => {
      await this.checkTransactionLease(transaction);
      const [profile, existing] = await transaction.getAll(
        this.db.collection("users").doc(job.uid), this.jobs.doc(job.uid));
      if (existing.exists || exactProfileVersion(profile) !== job.profileVersion) return false;
      transaction.create(this.jobs.doc(job.uid), {
        ...job, createdAt: Timestamp.fromMillis(this.now()), updatedAt: Timestamp.fromMillis(this.now()),
      });
      return true;
    });
  }

  async setJobStatus(uid: string, status: RetentionDeletionJob["status"]): Promise<void> {
    await this.db.runTransaction(async (transaction) => {
      await this.checkTransactionLease(transaction);
      const reference = this.jobs.doc(uid);
      const snapshot = await transaction.get(reference);
      if (!["authDeletePending", "authDeleted"].includes(snapshot.get("status"))) {
        throw new Error("Unverified retention job is not pending");
      }
      const terminal = status === "completed" || status === "cancelled";
      transaction.update(reference, {
        status, updatedAt: Timestamp.fromMillis(this.now()),
        // Pending/manual-review records MUST survive until reconciled.
        receiptExpiresAt: terminal ? Timestamp.fromMillis(this.now() + receiptMilliseconds) : null,
      });
    });
  }

  async deleteProfileIfUnchanged(uid: string, version: string | null): Promise<boolean> {
    return this.db.runTransaction(async (transaction) => {
      await this.checkTransactionLease(transaction);
      const reference = this.db.collection("users").doc(uid);
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) return true; // Resume after a successful, interrupted deletion.
      if (exactProfileVersion(snapshot) !== version) return false;
      transaction.delete(reference);
      return true;
    });
  }

  async pendingJobs(): Promise<RetentionDeletionJob[]> {
    const snapshot = await this.jobs.where("status", "in", ["authDeletePending", "authDeleted"])
      .limit(100).get();
    return snapshot.docs.map((document) => {
      const data = document.data();
      if (data.uid !== document.id || typeof data.identityFingerprint !== "string"
          || !/^[a-f0-9]{64}$/.test(data.identityFingerprint)
          || !(data.profileVersion === null || typeof data.profileVersion === "string")) {
        throw new Error("Invalid unverified retention job; manual review required");
      }
      return {uid: document.id, identityFingerprint: data.identityFingerprint,
        profileVersion: data.profileVersion, status: data.status} as RetentionDeletionJob;
    });
  }

  /** Bounded deletion of expired *terminal receipts*, never account data. */
  async pruneReceipts(): Promise<number> {
    const snapshot = await this.jobs.where("receiptExpiresAt", "<=", Timestamp.fromMillis(this.now()))
      .limit(100).get();
    let removed = 0;
    for (const document of snapshot.docs) {
      const deleted = await this.db.runTransaction(async (transaction) => {
        await this.checkTransactionLease(transaction);
        const current = await transaction.get(document.ref);
        const expires = current.get("receiptExpiresAt");
        if (!["completed", "cancelled"].includes(current.get("status"))
            || !(expires instanceof Timestamp) || expires.toMillis() > this.now()) return false;
        transaction.delete(document.ref);
        return true;
      });
      if (deleted) removed += 1;
    }
    return removed;
  }
}
