import {createHash, randomUUID} from "node:crypto";
import {FieldPath, Timestamp, type DocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {assertActiveUser, assertPrivilegedMFA, hasCurrentLegalAcknowledgements, requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {isAppOwner, userPermissionSnapshotFromData} from "../permissions/userPermissions";
import {buildAuditLog} from "../audit/auditLog";
import {buildUserNotificationDocument, userNotificationRef} from "../notifications/notificationPayloads";

function id(value: unknown): string {
  if (typeof value !== "string" || !value.length || value.length > 128 || value.includes("/")) throw new HttpsError("invalid-argument", "Invalid ID.");
  return value;
}
export function directoryGrantState(snapshot: DocumentSnapshot) {
  const data = snapshot.data();
  return {id:snapshot.id, enabled:data?.enabled === true,
    revision:snapshot.exists ? (typeof data?.revision === "string" ? data.revision : `${snapshot.updateTime!.seconds}:${snapshot.updateTime!.nanoseconds}`) : null,
    grantedAt:data?.grantedAt instanceof Timestamp ? data.grantedAt.toMillis() : null};
}

export const manageDirectoryEditorAccess = onCall({region:"europe-west3", maxInstances:10, enforceAppCheck:false}, async request => {
  const actor = await requireVerifiedActiveUser(request);
  if (!isAppOwner(actor.permissions)) throw new HttpsError("permission-denied", "App owner access is required.");
  const input = request.data ?? {};
  if (input.principalId !== actor.uid) throw new HttpsError("permission-denied", "Account changed.");
  if (input.action === "list") {
    let query = db.collection("directoryEditors").where("enabled","==",true).orderBy(FieldPath.documentId()).limit(41);
    if (input.cursor != null) query = query.startAfter(id(input.cursor));
    const page = await query.get();
    return {grants:page.docs.slice(0,40).map(directoryGrantState), cursor:page.size > 40 ? page.docs[39].id : null};
  }
  if (input.action === "inspect") {
    if (!Array.isArray(input.userIds) || input.userIds.length < 1 || input.userIds.length > 40) throw new HttpsError("invalid-argument", "Invalid user IDs.");
    const ids = [...new Set<string>(input.userIds.map(id))];
    return {grants:(await db.getAll(...ids.map(uid=>db.collection("directoryEditors").doc(uid)))).map(directoryGrantState)};
  }
  if (input.action !== "set" || typeof input.enabled !== "boolean" ||
      !(input.expectedRevision === null || typeof input.expectedRevision === "string" && input.expectedRevision.length < 150)) throw new HttpsError("invalid-argument", "Invalid grant request.");
  const targetID = id(input.userId), operationID = id(input.operationId);
  const key = createHash("sha256").update(`${actor.uid}\0${operationID}`).digest("hex");
  const fingerprint = createHash("sha256").update(JSON.stringify([targetID,input.enabled,input.expectedRevision])).digest("hex");
  const grantRef = db.collection("directoryEditors").doc(targetID), receiptRef = db.collection("directoryEditorOperations").doc(key);
  const nextRevision = randomUUID(), now = Timestamp.now();
  return db.runTransaction(async transaction => {
    const [owner, target, grant, receipt, terms, privacy] = await transaction.getAll(
      db.collection("users").doc(actor.uid),db.collection("users").doc(targetID),grantRef,receiptRef,db.doc("legalDocuments/terms"),db.doc("legalDocuments/privacy"));
    const permissions = userPermissionSnapshotFromData(actor.uid,owner.data());
    assertActiveUser(permissions); assertPrivilegedMFA(actor.token,permissions);
    if (!owner.exists || !isAppOwner(permissions)) throw new HttpsError("permission-denied", "App owner access is required.");
    if (!hasCurrentLegalAcknowledgements(permissions,{terms:terms.get("activeVersion"),privacy:privacy.get("activeVersion")})) throw new HttpsError("failed-precondition", "Current legal documents must be acknowledged.");
    const current = directoryGrantState(grant);
    if (receipt.exists) {
      if (receipt.get("fingerprint") !== fingerprint) throw new HttpsError("invalid-argument", "Operation ID was reused.");
      const result = receipt.get("result");
      if (result.revision !== current.revision || result.enabled !== current.enabled) throw new HttpsError("aborted", "Access changed. Review it again.");
      return result;
    }
    if (current.revision !== input.expectedRevision) throw new HttpsError("aborted", "Access changed. Review it again.");
    const targetPermissions = userPermissionSnapshotFromData(targetID,target.data());
    if (isAppOwner(targetPermissions) || targetID === actor.uid) throw new HttpsError("failed-precondition", "The app owner always has access.");
    if (input.enabled) {
      if (!target.exists) throw new HttpsError("not-found", "User profile does not exist.");
      assertActiveUser(targetPermissions);
    }
    const result = {id:targetID, enabled:input.enabled, revision:current.revision, grantedAt:current.grantedAt};
    if (current.enabled !== input.enabled) {
      result.revision = nextRevision;
      result.grantedAt = input.enabled ? now.toMillis() : null;
      // A disabled tombstone prevents revoke/regrant ABA races. Old apps already check enabled.
      transaction.set(grantRef,{enabled:input.enabled,revision:nextRevision,grantedBy:actor.uid,grantedAt:input.enabled ? now : null,updatedAt:now});
      const displayName = target.get("displayName") || target.get("fullName") || targetID;
      const title = input.enabled ? "Доступ до довідника надано" : "Доступ до довідника відкликано";
      const message = input.enabled ? "Власник застосунку надав вам право публікувати, змінювати й приховувати всі матеріали. Відкрийте вкладку «Довідник»." : "Власник застосунку відкликав ваше право редагувати довідник. Перегляд матеріалів залишається доступним.";
      const language = ["language","appLanguage","locale","preferredLocale","preferredLanguage"].map(k=>target.get(k)).find(v=>typeof v === "string");
      const german = typeof language === "string" && /^(de|german)/i.test(language);
      if (target.exists) transaction.create(userNotificationRef(targetID,`directory-access-${key}`),buildUserNotificationDocument({
        notificationId:`directory-access-${key}`,targetUserId:targetID,type:"systemAnnouncement",
        title:german ? (input.enabled ? "Ratgeberzugriff erteilt" : "Ratgeberzugriff entzogen") : title,
        message:german ? (input.enabled ? "Der App-Eigentümer hat Ihnen Zugriff zum Veröffentlichen, Bearbeiten und Ausblenden aller Inhalte erteilt. Öffnen Sie den Tab Ratgeber." : "Der App-Eigentümer hat Ihren Bearbeitungszugriff auf den Ratgeber entzogen. Inhalte können Sie weiterhin lesen.") : message,
        actionType:"none",severity:input.enabled ? "success" : "warning",sourceType:"account",sourceId:targetID,actorUserId:actor.uid,
        metadata:{scope:"directoryEditorAccess",enabled:String(input.enabled)},dedupeKey:key,
      }));
      transaction.create(db.collection("auditLogs").doc(`directory-access-${key}`),buildAuditLog({actionType:input.enabled ? "directoryEditorGranted" : "directoryEditorRevoked",targetUserId:targetID,performedBy:actor.uid,reason:title,previousValue:{directoryEditorEnabled:current.enabled},newValue:{directoryEditorEnabled:input.enabled}}));
      transaction.create(db.collection("systemLogs").doc(`directory-access-${key}`),{
        id:`directory-access-${key}`,createdAt:now,category:"authorization",severity:"info",severityRank:1,eventType:input.enabled ? "roleAssigned" : "roleRemoved",
        actorUserId:actor.uid,actorDisplayName:owner.get("displayName") || owner.get("fullName") || actor.uid,actorRole:"owner",targetType:"user",targetId:targetID,targetTitle:displayName,
        summary:`${title}: ${displayName}`,outcome:"success",isReviewed:false,isAppAdminReadable:false,retentionPolicy:"normalAudit",moduleName:"DirectoryAccess",operationName:input.enabled ? "grantDirectoryEditor" : "revokeDirectoryEditor",metadata:{scope:"directoryEditorAccess",enabled:String(input.enabled),operationId:operationID},
      });
    }
    transaction.create(receiptRef,{fingerprint,result,createdAt:now,expiresAt:Timestamp.fromMillis(now.toMillis()+90*86400000)});
    return result;
  });
});
