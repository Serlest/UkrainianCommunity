import {FieldPath, FieldValue, type DocumentData, type Firestore, type Query} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireVerifiedActiveUser} from "../auth/context";
import {db} from "../firebase/admin";
import {isOwner, type UserPermissionSnapshot} from "../permissions/userPermissions";
import {adminSearchAnchor, adminSearchDocuments, adminSearchOverflow, buildAdminSearchGrams, normalizeAdminSearch} from "../users/adminUserSearch";
export const workspaceIndexState = "internalSearchState/organizationsWorkspaceV1";
const statuses = ["draft","pendingReview","needsRevision","approved","rejected","archived"];
const regions = ["burgenland","kaernten","niederoesterreich","oberoesterreich","salzburg","steiermark","tirol","vorarlberg","wien"];
const sourceFields = ["name","localizations","city","federalState"];
function string(value: unknown): string { return typeof value === "string" ? value : ""; }
export function organizationSearchText(id: string, data: DocumentData): string {
  const localized = Object.values(data.localizations ?? {}).map(value => string((value as DocumentData)?.name));
  return normalizeAdminSearch([id,data.name,...localized,data.city,data.federalState].map(string).join(" "));
}
export function organizationSearchGrams(id: string, data: DocumentData): string[] {
  return buildAdminSearchGrams(id,{displayName:organizationSearchText(id,data)});
}
export async function reconcileWorkspaceIndex(firestore: Firestore, id: string): Promise<boolean> {
  return firestore.runTransaction(async tx=>{
    const ref=firestore.doc(`organizations/${id}`), doc=await tx.get(ref);if(!doc.exists)return false;
    const grams=organizationSearchGrams(id,doc.data()!);if(JSON.stringify(doc.get("workspaceSearchV1"))===JSON.stringify(grams))return false;
    tx.update(ref,{workspaceSearchV1:grams});return true;
  });
}
export const maintainOrganizationWorkspaceIndex=onDocumentWritten({document:"organizations/{organizationId}",region:"europe-west3",retry:true,maxInstances:4},async event=>{
 if(!event.data?.after.exists)return;
 const before=event.data.before.data(),after=event.data.after.data()!;
 if(before && sourceFields.every(key=>JSON.stringify(before[key])===JSON.stringify(after[key])) && JSON.stringify(after.workspaceSearchV1)===JSON.stringify(organizationSearchGrams(event.params.organizationId,after)))return;
 try{await reconcileWorkspaceIndex(db,event.params.organizationId)}catch(error){await db.doc(workspaceIndexState).set({ready:false,failedAt:FieldValue.serverTimestamp()},{merge:true});throw error;}
});
function member(data: DocumentData, uid: string): boolean { return data.ownerId===uid||data.adminIds?.includes(uid)||data.moderatorIds?.includes(uid); }
function validID(value:unknown):value is string{return typeof value==="string"&&value.length>0&&value.length<=200&&!value.includes("/");}
export async function readOrganizationWorkspace(firestore: Firestore, actor: UserPermissionSnapshot, input: Record<string,unknown>) {
 const action=input.action; const search=normalizeAdminSearch(string(input.search));
 if(string(input.search).length>160 || input.search!==undefined&&typeof input.search!=="string")throw new HttpsError("invalid-argument","Search too long.");
 const cursor=input.cursor==null?undefined:input.cursor;
 if(cursor!==undefined&&!validID(cursor))throw new HttpsError("invalid-argument","Invalid cursor.");
 const limit=30;
 if(action==="list"){
  if(input.region!=null&&!regions.includes(String(input.region)))throw new HttpsError("invalid-argument","Invalid region.");
  if(input.organizationId!==undefined){
   if(!validID(input.organizationId))throw new HttpsError("invalid-argument","Invalid organization ID.");
   const selected=await firestore.doc(`organizations/${input.organizationId}`).get(),data=selected.data();
   if(!data)return {ids:[],cursor:null};
   if(!isOwner(actor)&&!member(data,actor.uid))throw new HttpsError("permission-denied","Organization access required.");
   return {ids:data.moderationStatus==="approved"?[selected.id]:[],cursor:null};
  }
  const base=firestore.collection("organizations").where("moderationStatus","==","approved");
  const owner=isOwner(actor),ready=(await firestore.doc(workspaceIndexState).get()).get("ready")===true,anchor=adminSearchAnchor(search);
  const queries:Query[]=owner?[base]:[base.where("ownerId","==",actor.uid),base.where("adminIds","array-contains",actor.uid),base.where("moderatorIds","array-contains",actor.uid)];
  const pages=await Promise.all(queries.map(async baseQuery=>{
   let query=baseQuery;
   if(input.region)query=query.where("federalState","==",input.region);
   if(owner&&ready&&anchor)query=query.where("workspaceSearchV1","array-contains-any",[anchor,adminSearchOverflow]);
   const ids:string[]=[];let after=cursor as string|undefined;
   // Stream only enough ordered candidates for one page. No offset or client-wide snapshot.
   while(ids.length<limit+1){
    let page=query.orderBy(FieldPath.documentId());if(after)page=page.startAfter(after);
    const docs=(await page.limit(search?100:limit+1).get()).docs;if(!docs.length)break;
    for(const doc of docs){if(search.split(/\s+/).every(token=>organizationSearchText(doc.id,doc.data()).includes(token)))ids.push(doc.id);if(ids.length===limit+1)break;}
    after=docs.at(-1)!.id;if(docs.length<(search?100:limit+1))break;
   }
   return ids;
  }));
  const ids=[...new Set(pages.flat())].sort();const more=ids.length>limit;const selected=ids.slice(0,limit);
  return {ids:selected,cursor:more?selected.at(-1):null};
 }
 if(!validID(input.organizationId))throw new HttpsError("invalid-argument","Organization ID required.");
 const org=(await firestore.doc(`organizations/${input.organizationId}`).get()).data();
 if(!org)throw new HttpsError("not-found","Organization unavailable.");
 if(!isOwner(actor)&&!member(org,actor.uid))throw new HttpsError("permission-denied","Current organization access required.");
 if(org.moderationStatus!=="approved")throw new HttpsError("failed-precondition","Organization is not approved.");
 if(action==="stats"){
  const counts:Record<string,number>={};await Promise.all(["news","events"].map(async collection=>{
   counts[collection]=(await firestore.collection(collection).where("organizationId","==",input.organizationId).where("sourceType","==","organization").where("moderationStatus","in",statuses).count().get()).data().count;
  }));return {counts};
 }
 if(action==="content"){
  const type=input.contentType;if(type!=="news"&&type!=="event")throw new HttpsError("invalid-argument","Invalid content type.");
  const collection=type==="news"?"news":"events";
  let query:Query=firestore.collection(collection).where("organizationId","==",input.organizationId).where("sourceType","==","organization");
  if(input.status!=null){if(!statuses.includes(String(input.status)))throw new HttpsError("invalid-argument","Invalid status.");query=query.where("moderationStatus","==",input.status);}
  query=query.orderBy(FieldPath.documentId());if(cursor)query=query.startAfter(cursor);
  const docs=(await query.limit(limit+1).get()).docs,selected=docs.slice(0,limit);
  const counts:Record<string,number>={};await Promise.all(statuses.map(async status=>{counts[status]=(await firestore.collection(collection).where("organizationId","==",input.organizationId).where("sourceType","==","organization").where("moderationStatus","==",status).count().get()).data().count;}));
  return {items:selected.map(doc=>({id:doc.id,title:string(doc.get(`localizations.${input.language === "de" ? "de" : "uk"}.title`))||string(doc.get("title")),status:string(doc.get("moderationStatus")),reason:string(doc.get("moderationReason"))})),counts,cursor:docs.length>limit?selected.at(-1)?.id:null};
 }
 if(action==="candidates"||action==="subscribers"){
  if(action==="candidates"&&!isOwner(actor)&&org.ownerId!==actor.uid)throw new HttpsError("permission-denied","Team management required.");
  const excluded=action==="subscribers"?[]:input.transfer===true?[org.ownerId]:[org.ownerId,...(org.adminIds??[]),...(org.moderatorIds??[])];
  const users:Array<{id:string;displayName:string;city:string;federalState:string|null;avatarURL:string|null}>=[];
  const allUsers=action==="candidates"&&isOwner(actor);
  if(allUsers||search){
   // Use the existing user index; only public fields are matched/returned to organization owners.
   const stream=adminSearchDocuments(firestore,search,["displayName","city","selectedFederalState","accountStatus","blockState"]);
   for await(const doc of stream){
    if(cursor&&doc.id<=cursor||excluded.includes(doc.id))continue;const data=doc.data();
    if(!["active","warned"].includes(data.accountStatus??"active")||!["active","warned"].includes(data.blockState??"active"))continue;
    const publicText=normalizeAdminSearch([data.displayName,data.city,data.selectedFederalState].map(string).join(" "));
    if(!search.split(/\s+/).every(token=>publicText.includes(token)))continue;
    if(!allUsers&&(await firestore.collection("likes").where("subscribedOrganizationId","==",input.organizationId).where("userId","==",doc.id).limit(1).get()).empty)continue;
    users.push({id:doc.id,displayName:string(data.displayName),city:string(data.city),federalState:typeof data.selectedFederalState==="string"?data.selectedFederalState:null,avatarURL:null});if(users.length>limit)break;
   }
  }else{
   let query:Query=firestore.collection("likes").where("subscribedOrganizationId","==",input.organizationId).orderBy(FieldPath.documentId());
   if(cursor)query=query.startAfter(cursor);
   const docs=(await query.limit(limit+1).get()).docs;
   const selected=docs.slice(0,limit),refs=selected.map(doc=>string(doc.get("userId"))).filter(id=>validID(id)&&!excluded.includes(id));
   const profiles=refs.length?await firestore.getAll(...refs.map(id=>firestore.doc(`publicProfiles/${id}`))):[];
   profiles.filter(doc=>doc.exists).forEach(doc=>{const data=doc.data()!;users.push({id:doc.id,displayName:string(data.displayName),city:string(data.city),federalState:typeof data.federalState==="string"?data.federalState:null,avatarURL:typeof data.avatarURL==="string"?data.avatarURL:null});});
   return {users,cursor:docs.length>limit?selected.at(-1)?.id:null};
  }
  const more=users.length>limit,selected=users.slice(0,limit);return {users:selected,cursor:more?selected.at(-1)?.id:null};
 }
 throw new HttpsError("invalid-argument","Unsupported action.");
}
export const manageOrganizationWorkspace=onCall({region:"europe-west3",maxInstances:6,timeoutSeconds:60,enforceAppCheck:false,invoker:"public"},async request=>{
 const actor=await requireVerifiedActiveUser(request);const data=request.data;
 if(!data||typeof data!=="object"||Array.isArray(data)||data.principalId!==actor.uid)throw new HttpsError("permission-denied","Account changed.");
 return readOrganizationWorkspace(db,actor.permissions,data);
});
