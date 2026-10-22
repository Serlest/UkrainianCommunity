import {createHash} from "node:crypto";
import {FieldValue, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {auditLogRef, buildAuditLog} from "../audit/auditLog";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {buildUserNotificationDocument, userNotificationRef} from "../notifications/notificationPayloads";
import {canManageOrganizationRoles, type OrganizationRoleSnapshot} from "../permissions/organizationPermissions";
import {isOwner, isActiveUser, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {assertUsableTargetUser, getTargetAuthSnapshot} from "../users/targetUserValidation";

type Role = "none" | "communityAdmin" | "communityModerator" | "communityOwner";
type Action = "assignAdmin" | "removeAdmin" | "assignModerator" | "removeModerator" | "transferOwner";
interface RoleRequest {
  organizationId: string; targetUserId: string; reason?: string;
  operationId?: string; principalId?: string; expectedRevision?: string | null; expectedRole?: Role;
}
const options = {region: "europe-west3", maxInstances: 10, enforceAppCheck: false};
function parse(data: unknown): RoleRequest {
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new HttpsError("invalid-argument", "Invalid request.");
  const value = data as Record<string, unknown>;
  const id = (key: string, optional = false): string | undefined => {
    const raw = value[key]; if (optional && raw == null) return undefined;
    if (typeof raw !== "string" || !raw.trim() || raw.length > 200 || raw.includes("/")) throw new HttpsError("invalid-argument", `Invalid ${key}.`);
    return raw.trim();
  };
  if (value.reason != null && (typeof value.reason !== "string" || value.reason.length > 2000)) throw new HttpsError("invalid-argument", "Invalid reason.");
  if (value.expectedRevision != null && (typeof value.expectedRevision !== "string" || !/^\d+:\d+$/.test(value.expectedRevision))) throw new HttpsError("invalid-argument", "Invalid revision.");
  if (value.expectedRole !== undefined && !["none", "communityOwner", "communityAdmin", "communityModerator"].includes(String(value.expectedRole))) throw new HttpsError("invalid-argument", "Invalid expected role.");
  const result: RoleRequest = {organizationId: id("organizationId")!, targetUserId: id("targetUserId")!, reason: typeof value.reason === "string" ? value.reason.trim() || undefined : undefined,
    operationId: id("operationId", true), principalId: id("principalId", true), expectedRole: value.expectedRole as Role | undefined};
  if (Object.hasOwn(value, "expectedRevision")) result.expectedRevision = value.expectedRevision as string | null;
  if (result.principalId && (!result.operationId || !Object.hasOwn(result, "expectedRevision") || !result.expectedRole)) throw new HttpsError("invalid-argument", "Reviewed revision, role and operation are required.");
  return result;
}
function roles(id: string, data: DocumentData): OrganizationRoleSnapshot {
  return {organizationId: id, ownerId: typeof data.ownerId === "string" ? data.ownerId : undefined,
    adminIds: Array.isArray(data.adminIds) ? data.adminIds : [], moderatorIds: Array.isArray(data.moderatorIds) ? data.moderatorIds : []};
}
function roleFor(snapshot: OrganizationRoleSnapshot, uid: string): Role {
  return snapshot.ownerId === uid ? "communityOwner" : snapshot.adminIds.includes(uid) ? "communityAdmin" : snapshot.moderatorIds.includes(uid) ? "communityModerator" : "none";
}
function roleLabel(role: Role): string { return role === "communityOwner" ? "organization owner" : role === "communityAdmin" ? "organization admin" : role === "communityModerator" ? "organization moderator" : "organization"; }
function revision(data: DocumentData): string | null { const time = data.updatedAt; return time instanceof Timestamp ? `${time.seconds}:${time.nanoseconds}` : null; }
function createRoleCallable(action: Action) {
  return onCall(options, async request => {
    const actor = await requireVerifiedActiveUser(request), input = parse(request.data);
    if (input.principalId !== undefined && input.principalId !== actor.uid) throw new HttpsError("permission-denied", "Account changed.");
    const organization = db.doc(`organizations/${input.organizationId}`), target = db.doc(`users/${input.targetUserId}`);
    const operationID = input.operationId ? createHash("sha256").update(`${actor.uid}\0${input.organizationId}\0${input.operationId}`).digest("hex") : undefined;
    const receipt = operationID ? db.doc(`organizationRoleOperations/${operationID}`) : undefined;
    const fingerprint = createHash("sha256").update(JSON.stringify([action,input.targetUserId,input.reason??null,input.expectedRevision??null,input.expectedRole??null])).digest("hex");
    const notification = operationID ? db.doc(`users/${input.targetUserId}/notificationInbox/organizationRole_${operationID}`) : userNotificationRef(input.targetUserId);
    const committedAt = new Date().toISOString();
    return db.runTransaction(async transaction => {
      const [orgDoc, actorDoc, targetDoc, receiptDoc] = await Promise.all([
        transaction.get(organization), transaction.get(db.doc(`users/${actor.uid}`)), transaction.get(target), receipt ? transaction.get(receipt) : undefined,
      ]);
      const permissions = userPermissionSnapshotFromData(actor.uid, actorDoc.data());
      const snapshot = roles(input.organizationId, orgDoc.data() ?? {});
      if (!actorDoc.exists || !isActiveUser(permissions) || (action === "transferOwner" ? !isOwner(permissions) : !canManageOrganizationRoles(permissions, snapshot))) throw new HttpsError("permission-denied", "Current organization role permissions required.");
      if (receiptDoc?.exists) {
        if (receiptDoc.get("fingerprint") !== fingerprint) throw new HttpsError("already-exists", "Operation ID was used for a different action.");
        return receiptDoc.get("response") as Record<string, unknown>;
      }
      if (!orgDoc.exists) throw new HttpsError("not-found", "Organization does not exist.");
      const previousRole = roleFor(snapshot, input.targetUserId), previousOwnerId = snapshot.ownerId ?? null;
      const removal = action === "removeAdmin" || action === "removeModerator";
      const newRole: Role = action === "transferOwner" ? "communityOwner" : removal ? "none" : action === "assignAdmin" ? "communityAdmin" : "communityModerator";
      if (Object.hasOwn(input, "expectedRevision") && revision(orgDoc.data()!) !== input.expectedRevision || input.expectedRole !== undefined && input.expectedRole !== previousRole) throw new HttpsError("aborted", "The organization or role changed. Reload before confirming.");
      if (action !== "transferOwner" && previousRole === "communityOwner") throw new HttpsError("permission-denied", "Use ownership transfer to change the owner.");
      // Legacy clients have no reviewed revision. A stale remove-admin command must
      // never remove a different role, while an identical retry is a harmless no-op.
      const requestedRemovalRole = action === "removeAdmin" ? "communityAdmin" : "communityModerator";
      if (removal && previousRole !== "none" && previousRole !== requestedRemovalRole) throw new HttpsError("aborted", "The target role changed.");
      const changed = previousRole !== newRole;
      if (changed && !removal) {
        if (!targetDoc.exists) throw new HttpsError("not-found", "Target profile does not exist.");
        assertUsableTargetUser(await getTargetAuthSnapshot(input.targetUserId), userPermissionSnapshotFromData(input.targetUserId, targetDoc.data()));
      }
      const response: Record<string, unknown> = action === "transferOwner"
        ? {organizationId: input.organizationId, previousOwnerId: changed ? previousOwnerId : null, newOwnerId: input.targetUserId, updatedAt: committedAt}
        : {organizationId: input.organizationId, targetUserId: input.targetUserId, previousRole, newRole, updatedAt: committedAt};
      if (changed) {
        const without = (values: string[], ...ids: string[]) => [...new Set(values.filter(uid => !ids.includes(uid)))].sort();
        const adminIds = without(snapshot.adminIds,input.targetUserId,...(action === "transferOwner" && previousOwnerId ? [previousOwnerId] : []));
        const moderatorIds = without(snapshot.moderatorIds,input.targetUserId,...(action === "transferOwner" && previousOwnerId ? [previousOwnerId] : []));
        if (newRole === "communityAdmin") adminIds.push(input.targetUserId);
        if (newRole === "communityModerator") moderatorIds.push(input.targetUserId);
        transaction.update(organization,{adminIds:adminIds.sort(),moderatorIds:moderatorIds.sort(),...(action === "transferOwner" ? {ownerId:input.targetUserId} : {}),updatedAt:FieldValue.serverTimestamp()});
        transaction.set(auditLogRef(),buildAuditLog({actionType:action === "transferOwner" ? "organizationOwnerChanged" : removal ? "organizationRoleRemoved" : "organizationRoleAssigned",targetUserId:input.targetUserId,performedBy:actor.uid,reason:input.reason??"Organization team management",
          previousValue:action === "transferOwner" ? {organizationId:input.organizationId,ownerId:previousOwnerId??"none"} : {organizationId:input.organizationId,role:previousRole},newValue:action === "transferOwner" ? {organizationId:input.organizationId,ownerId:input.targetUserId} : {organizationId:input.organizationId,role:newRole}}));
        if (targetDoc.exists) transaction.set(notification,buildUserNotificationDocument({notificationId:notification.id,targetUserId:input.targetUserId,type:removal?"organizationRoleRemoved":"organizationRoleAssigned",
          title:action === "transferOwner" ? "Organization ownership transferred" : removal ? "Organization role removed" : "Organization role assigned",
          message:removal?`Your ${roleLabel(previousRole)} role was removed.`:`You were assigned as ${roleLabel(newRole)}.`,severity:"info",actionType:"openOrganization",actionTargetId:input.organizationId,requiresPopup:false,actorUserId:actor.uid,sourceType:"organization",sourceId:input.organizationId,
          metadata:{organizationId:input.organizationId,previousRole,newRole,...(action === "transferOwner" ? {previousOwnerId,newOwnerId:input.targetUserId} : {}),reason:input.reason??"Organization team management",updatedAt:committedAt},dedupeKey:`organizationRole:${notification.id}`}));
        if (action === "transferOwner" && previousOwnerId) {
          const oldNotice = operationID ? db.doc(`users/${previousOwnerId}/notificationInbox/organizationOwnershipRemoved_${operationID}`) : userNotificationRef(previousOwnerId);
          transaction.set(oldNotice,buildUserNotificationDocument({notificationId:oldNotice.id,targetUserId:previousOwnerId,type:"organizationRoleRemoved",title:"Organization ownership transferred",message:"Ownership of your organization was transferred.",severity:"warning",actionType:"openOrganization",actionTargetId:input.organizationId,requiresPopup:false,actorUserId:actor.uid,sourceType:"organization",sourceId:input.organizationId,metadata:{organizationId:input.organizationId,previousOwnerId,newOwnerId:input.targetUserId,previousRole:"communityOwner",newRole:"none",reason:input.reason??"Organization owner changed",updatedAt:committedAt},dedupeKey:`organizationOwnershipRemoved:${oldNotice.id}`}));
        }
      }
      if (receipt) transaction.set(receipt,{fingerprint,response,createdAt:FieldValue.serverTimestamp(),expiresAt:Timestamp.fromMillis(Date.now()+90*86400000)});
      return response;
    });
  });
}
export const assignOrganizationAdmin = createRoleCallable("assignAdmin");
export const removeOrganizationAdmin = createRoleCallable("removeAdmin");
export const assignOrganizationModerator = createRoleCallable("assignModerator");
export const removeOrganizationModerator = createRoleCallable("removeModerator");
export const transferOrganizationOwnership = createRoleCallable("transferOwner");
