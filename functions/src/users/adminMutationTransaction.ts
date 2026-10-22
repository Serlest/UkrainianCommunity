import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type DocumentSnapshot, type Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {assertActiveUser, assertPrivilegedMFA, hasCurrentLegalAcknowledgements, type VerifiedActiveUserContext} from "../auth/context";
import {db} from "../firebase/admin";
import {assertCanManageUsers, canAssignAppAdmin, userPermissionSnapshotFromData} from "../permissions/userPermissions";

export function adminReviewRevision(data: Record<string,unknown>): string {
  const stamp = (key: string) => { const t = data[key] as Timestamp | undefined; return t?.seconds !== undefined ? `${t.seconds}:${t.nanoseconds}` : ""; };
  const parts = ["globalRole","accountStatus","blockState"].map(k=>typeof data[k] === "string" ? String(data[k]) : "");
  parts.push(String(data.warningCount ?? 0),String(data.isBlocked === true),stamp("banExpiresAt"),stamp("statusUpdatedAt"),stamp("roleUpdatedAt"));
  return createHash("sha256").update(parts.join("\0")).digest("hex");
}
/** Optional reviewed contract preserves old builds. New clients pin the exact
 * reviewed target document and use a stable receipt across network retries. */
export async function runAdminMutation<T extends object>(raw: unknown, auth: VerifiedActiveUserContext, action: string, targetId: string,
  mutate: (transaction: Transaction, target: DocumentSnapshot) => Promise<void>, response: () => T): Promise<T> {
  const data = raw as Record<string,unknown>;
  const modern = data.operationId !== undefined || data.principalId !== undefined || data.expectedRevision !== undefined;
  if (modern && (data.principalId !== auth.uid || typeof data.operationId !== "string" || !/^[a-zA-Z0-9-]{1,128}$/.test(data.operationId)
      || typeof data.expectedRevision !== "string" || !/^[a-f0-9]{64}$/.test(data.expectedRevision))) {
    throw new HttpsError("invalid-argument","Reviewed account revision and operation are required.");
  }
  const operation = modern ? createHash("sha256").update(`${auth.uid}\0${data.operationId}`).digest("hex") : undefined;
  const receipt = operation ? db.doc(`adminMutationOperations/${operation}`) : undefined;
  const fingerprint = createHash("sha256").update(JSON.stringify([action,targetId,data.reason??null,data.until??null,data.expectedRevision??null])).digest("hex");
  return db.runTransaction(async transaction => {
    const [actor,target,terms,privacy,saved] = await Promise.all([
      transaction.get(db.doc(`users/${auth.uid}`)),transaction.get(db.doc(`users/${targetId}`)),
      transaction.get(db.doc("legalDocuments/terms")),transaction.get(db.doc("legalDocuments/privacy")),receipt ? transaction.get(receipt) : undefined]);
    if (!actor.exists || auth.uid === targetId) throw new HttpsError("permission-denied","Current administrative permissions required.");
    const permissions = userPermissionSnapshotFromData(auth.uid,actor.data());
    assertActiveUser(permissions); assertPrivilegedMFA(auth.token,permissions); assertCanManageUsers(permissions);
    if (action.startsWith("appAdmin") && !canAssignAppAdmin(permissions)) throw new HttpsError("permission-denied","App owner permissions required.");
    if (!hasCurrentLegalAcknowledgements(permissions,{terms:terms.get("activeVersion"),privacy:privacy.get("activeVersion")})) throw new HttpsError("failed-precondition","Current legal documents must be acknowledged.");
    if (!target.exists) throw new HttpsError("not-found","Target user does not exist.");
    // Current hierarchy applies to receipt replays as well as first attempts.
    if (target.get("globalRole") === "owner" || target.get("globalRole") === "admin" && permissions.globalRole !== "owner") throw new HttpsError("permission-denied","Only the app owner can change an app admin account.");
    if (saved?.exists) {
      if (saved.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists","Operation was used for a different action.");
      const prior = saved.get("response") as T & {newAccountStatus?:string;newBlockState?:string;newGlobalRole?:string};
      // Resume token revocation only while the committed restriction is current.
      // A delayed retry must never revoke a subsequently restored account.
      if (prior.newAccountStatus && (target.get("accountStatus") !== prior.newAccountStatus || target.get("blockState") !== prior.newBlockState)
          || prior.newGlobalRole && target.get("globalRole") !== prior.newGlobalRole) throw new HttpsError("aborted","The account changed. Reload before confirming.");
      return prior;
    }
    if (modern && adminReviewRevision(target.data()!) !== data.expectedRevision) throw new HttpsError("aborted","The account changed. Reload before confirming.");
    await mutate(transaction,target);
    const result = response();
    if (receipt) transaction.set(receipt,{fingerprint,response:result,createdAt:FieldValue.serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+90*86400000)});
    return result;
  });
}
