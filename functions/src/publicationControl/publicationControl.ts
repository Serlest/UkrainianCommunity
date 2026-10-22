import {FieldPath, Timestamp, type DocumentData} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onCall,HttpsError} from "firebase-functions/v2/https";
import {db} from "../firebase/admin";
import {requireVerifiedActiveUser} from "../auth/context";
import {isAppOwner} from "../permissions/userPermissions";
import {dailyDocumentIDFor} from "../analytics/analyticsDate";

export const publicationRegions = ["austria","burgenland","kaernten","niederoesterreich","oberoesterreich","salzburg","steiermark","tirol","vorarlberg","wien","unknown"];
export function publicationProjection(kind:string,id:string,data:DocumentData,firstPublicAt:Timestamp,timingSource:string) {
  const region = data.regionScope === "austria" || data.federalState === "austria" ? "austria" : publicationRegions.includes(data.federalState) ? data.federalState : "unknown";
  return {kind,contentId:id,title:String(data.title || id).slice(0,500),titleUK:String(data.localizations?.uk?.title || data.title || id).slice(0,500),titleDE:String(data.localizations?.de?.title || data.title || id).slice(0,500),region,firstPublicAt,day:dailyDocumentIDFor(firstPublicAt.toDate()),timingSource,expiresAt:Timestamp.fromMillis(firstPublicAt.toMillis()+45*86400000),sourceState:data.moderationStatus ?? "unknown"};
}
export async function updatePublicationIndex(kind:string,id:string,observed:DocumentData|undefined,before:DocumentData|undefined,eventTime:Timestamp) {
  const source = db.collection(kind === "news" ? "news":"events").doc(id), reference=db.collection("publicationControlItems").doc(`${kind}_${id}`);
  await db.runTransaction(async tx=>{
    const [current,existing]=await tx.getAll(source,reference);
    const wasPublic=observed?.moderationStatus === "approved";
    if (!existing.exists && (!wasPublic || before?.moderationStatus === "approved")) return;
    if (!existing.exists) {
      const createdPublic = !before && observed?.createdAt instanceof Timestamp;
      const time=createdPublic ? observed!.createdAt as Timestamp : eventTime;
      tx.create(reference,{...publicationProjection(kind,id,observed!,time,createdPublic?"creation":"approvalEvent"),sourceState:current.exists ? current.get("moderationStatus") ?? "unknown":"removed",updatedAt:Timestamp.now()});
    } else {
      // Read canonical content in the transaction, so late/replayed events cannot restore stale state.
      const data=current.data();
      tx.update(reference,{sourceState:data?.moderationStatus ?? "removed",...(data ? {title:String(data.title || id).slice(0,500),titleUK:String(data.localizations?.uk?.title || data.title || id).slice(0,500),titleDE:String(data.localizations?.de?.title || data.title || id).slice(0,500)}:{}),updatedAt:Timestamp.now()});
    }
  });
}
const trigger=(collection:"news"|"events")=>onDocumentWritten({document:`${collection}/{contentId}`,region:"europe-west3",retry:true,maxInstances:4},async event=>{
  if (!event.data) return;
  const before=event.data.before.data(),after=event.data.after.data();
  // Ordinary view/counter writes need no extra index transaction.
  if (before?.moderationStatus === after?.moderationStatus && before?.title === after?.title && JSON.stringify(before?.localizations) === JSON.stringify(after?.localizations)) return;
  await updatePublicationIndex(collection === "news"?"news":"event",event.params.contentId,after,before,Timestamp.fromDate(new Date(event.time)));
});
export const maintainPublicationControlNews=trigger("news");
export const maintainPublicationControlEvents=trigger("events");
function dto(data:DocumentData,id:string) {
  const result:DocumentData={id,...data};
  for (const key of ["firstPublicAt","endedAt","syncedAt","lastCompleteAt"]) result[key]=data[key] instanceof Timestamp ? data[key].toMillis():null;
  return result;
}
export const getPublicationControl=onCall({region:"europe-west3",maxInstances:6,enforceAppCheck:false},async request=>{
  const actor=await requireVerifiedActiveUser(request);
  if (!isAppOwner(actor.permissions) || request.data?.principalId !== actor.uid) throw new HttpsError("permission-denied","App owner access is required.");
  const input=request.data??{}, today=dailyDocumentIDFor(new Date()),day=input.day??today;
  if (typeof day!=="string" || !/^\d{4}-\d{2}-\d{2}$/.test(day) || day>today || day<dailyDocumentIDFor(new Date(Date.now()-30*86400000))) throw new HttpsError("invalid-argument","Select a day within the last 30 days.");
  if (input.region != null && !publicationRegions.includes(input.region) || input.kind != null && !["news","event"].includes(input.kind)) throw new HttpsError("invalid-argument","Invalid filter.");
  if (input.action === "overview" || input.action === "items") {
    const documents=await db.collection("publicationControlItems").where("day","==",day).get();
    const all=documents.docs.map(d=>dto(d.data(),d.id));
    const items=all.filter(d=>(!input.region || d.region===input.region)&&(!input.kind || d.kind===input.kind)).sort((a,b)=>b.firstPublicAt-a.firstPublicAt || a.id.localeCompare(b.id));
    let start=0;
    if (input.cursor!=null) {
      if (typeof input.cursor!=="string" || input.cursor.length>500) throw new HttpsError("invalid-argument","Invalid cursor.");
      const anchor=items.findIndex(d=>d.id===input.cursor);
      if (anchor<0) throw new HttpsError("aborted","The list changed. Refresh it.");
      start=anchor+1;
    }
    const page=items.slice(start,start+30);
    if (input.action === "items") return {items:page,cursor:items.length>start+30?page.at(-1)!.id:null,total:items.length};
    const [sources,meta]=await Promise.all([db.collection("publicationControlSources").get(),db.doc("publicationControlMeta/importer").get()]);
    return {day,serverTime:Date.now(),legacyTimeCount:all.filter(d=>d.timingSource==="legacyCreation").length,news:all.filter(d=>d.kind==="news").length,events:all.filter(d=>d.kind==="event").length,
      regions:publicationRegions.map(region=>({region,news:all.filter(d=>d.kind==="news"&&d.region===region).length,events:all.filter(d=>d.kind==="event"&&d.region===region).length})),sources:sources.docs.map(d=>dto(d.data(),d.id)),syncErrors:Number(meta.get("errors")??0),syncedAt:meta.get("syncedAt") instanceof Timestamp?meta.get("syncedAt").toMillis():null};
  }
  if (input.action === "runs") {
    let query=db.collection("publicationControlRuns").orderBy("endedAt","desc").orderBy(FieldPath.documentId()).limit(80);
    if (input.cursor!=null) {
      if (typeof input.cursor!=="string" || !/^[a-f0-9]{40}$/.test(input.cursor)) throw new HttpsError("invalid-argument","Invalid cursor.");
      const cursor=await db.collection("publicationControlRuns").doc(input.cursor).get();
      if (!cursor.exists) throw new HttpsError("aborted","History changed. Refresh it.");
      query=query.startAfter(cursor);
    }
    // Compact bounded pages; the UI applies the selected region to these history rows.
    const result=await query.get();
    return {runs:result.docs.map(d=>dto(d.data(),d.id)),cursor:result.size===80?result.docs.at(-1)!.id:null};
  }
  throw new HttpsError("invalid-argument","Invalid action.");
});
