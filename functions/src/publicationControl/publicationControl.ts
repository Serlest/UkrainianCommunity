import {FieldPath, Timestamp, type DocumentData, type Query} from "firebase-admin/firestore";
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
      const projection=publicationProjection(kind,id,observed!,time,createdPublic?"creation":"approvalEvent");
      const dayRef=db.doc(`publicationControlDays/${projection.day}`),daySnapshot=await tx.get(dayRef);
      let summary=daySnapshot.data();
      if(!summary) {
        const older=await tx.get(db.collection("publicationControlItems").where("day","==",projection.day).limit(1));
        summary={news:0,events:0,legacyTimeCount:0,regions:{},ready:older.empty};
      }
      const counter=kind==="news"?"news":"events",regions={...summary.regions};
      regions[projection.region]={news:0,events:0,...regions[projection.region]};
      regions[projection.region][counter]+=1;
      tx.set(dayRef,{...summary,[counter]:(summary[counter]??0)+1,regions,updatedAt:Timestamp.now()});
      tx.create(reference,{...projection,sourceState:current.exists ? current.get("moderationStatus") ?? "unknown":"removed",updatedAt:Timestamp.now()});
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
/** Transactional migration/reconciliation; never modifies a publication or its index. */
export async function rebuildPublicationDay(day:string) {
  return db.runTransaction(async tx=>{
    const ref=db.doc(`publicationControlDays/${day}`);
    await tx.get(ref);
    const rows=await tx.get(db.collection("publicationControlItems").where("day","==",day));
    const summary:DocumentData={news:0,events:0,legacyTimeCount:0,regions:{},ready:true,updatedAt:Timestamp.now()};
    for(const doc of rows.docs) {
      const row=doc.data(),key=row.kind==="news"?"news":"events",region=publicationRegions.includes(row.region)?row.region:"unknown";
      summary[key]++; if(row.timingSource==="legacyCreation")summary.legacyTimeCount++;
      summary.regions[region]??={news:0,events:0};summary.regions[region][key]++;
    }
    tx.set(ref,summary);return summary;
  });
}
export function validPublicationDay(day:unknown,today:string):day is string {
  if(typeof day!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(day))return false;
  const date=new Date(day+"T12:00:00Z");
  return Number.isFinite(date.getTime())&&date.toISOString().slice(0,10)===day&&day<=today
    &&day>=new Date(new Date(today+"T12:00:00Z").getTime()-30*86400000).toISOString().slice(0,10);
}
function dto(data:DocumentData,id:string) {
  const result:DocumentData={...data,id};
  for (const key of ["firstPublicAt","endedAt","scheduledAt","syncedAt","lastCompleteAt","lastAttemptAt","lastSuccessfulCheckAt","lastImportedAt","lastReportAt","nextExpectedAt"]) result[key]=data[key] instanceof Timestamp ? data[key].toMillis():null;
  return result;
}
export const getPublicationControl=onCall({region:"europe-west3",maxInstances:6,enforceAppCheck:false},async request=>{
  const actor=await requireVerifiedActiveUser(request);
  if (!isAppOwner(actor.permissions) || request.data?.principalId !== actor.uid) throw new HttpsError("permission-denied","App owner access is required.");
  const input=request.data??{}, today=dailyDocumentIDFor(new Date()),day=input.day??today;
  if (!validPublicationDay(day,today)) throw new HttpsError("invalid-argument","Select a day within the last 30 days.");
  if (input.region != null && !publicationRegions.includes(input.region) || input.kind != null && !["news","event"].includes(input.kind)) throw new HttpsError("invalid-argument","Invalid filter.");
  if(input.action==="overview") {
    const [daily,sources,meta]=await Promise.all([db.doc(`publicationControlDays/${day}`).get(),db.collection("publicationControlSources").limit(30).get(),db.doc("publicationControlMeta/importer").get()]);
    // Compatibility fallback is used only until historical day summaries are rebuilt.
    let counts=daily.data();
    if(!counts?.ready)counts=await rebuildPublicationDay(day);
    const metadata=dto(meta.data()??{},"importer");
    return {day,serverTime:Date.now(),news:counts.news,events:counts.events,legacyTimeCount:counts.legacyTimeCount,
      regions:publicationRegions.map(region=>({region,news:counts!.regions?.[region]?.news??0,events:counts!.regions?.[region]?.events??0})),
      sources:sources.docs.map(d=>dto(d.data(),d.id)),syncErrors:Number(meta.get("errors")??0),
      syncedAt:metadata.lastSuccessfulCheckAt??metadata.syncedAt,
      lastAttemptAt:metadata.lastAttemptAt,lastSuccessfulCheckAt:metadata.lastSuccessfulCheckAt,
      lastImportedAt:metadata.lastImportedAt,lastReportAt:metadata.lastReportAt,
      syncIssues:meta.get("issues")??[]};
  }
  if(input.action==="items") {
    let query:Query=db.collection("publicationControlItems").where("day","==",day);
    if(input.region!=null)query=query.where("region","==",input.region);
    if(input.kind!=null)query=query.where("kind","==",input.kind);
    const total=(await query.count().get()).data().count;
    query=query.orderBy("firstPublicAt","desc").orderBy(FieldPath.documentId());
    if(input.cursor!=null) {
      if(typeof input.cursor!=="string"||input.cursor.length>500||input.cursor.includes("/"))throw new HttpsError("invalid-argument","Invalid cursor.");
      const anchor=await db.doc(`publicationControlItems/${input.cursor}`).get();
      if(!anchor.exists||anchor.get("day")!==day||(input.region!=null&&anchor.get("region")!==input.region)||(input.kind!=null&&anchor.get("kind")!==input.kind))throw new HttpsError("aborted","The list changed. Refresh it.");
      query=query.startAfter(anchor);
    }
    const result=await query.limit(31).get(),rows=result.docs.slice(0,30);
    return {items:rows.map(d=>dto(d.data(),d.id)),cursor:result.size>30?rows.at(-1)!.id:null,total};
  }
  if(input.action==="runs") {
    let query:Query=db.collection("publicationControlRuns");
    if(input.region!=null)query=query.where("region","==",input.region);
    query=query.orderBy("endedAt","desc").orderBy(FieldPath.documentId());
    if(input.cursor!=null) {
      if(typeof input.cursor!=="string"||input.cursor.length>1000)throw new HttpsError("invalid-argument","Invalid cursor.");
      let anchorID=input.cursor, expectedTime:number[]|null=null;
      // Existing clients may still hold a plain document-ID cursor. New pages bind
      // the anchor timestamp and region, so a revised report cannot silently skip rows.
      if(!/^[a-f0-9]{40}$/.test(anchorID)) {
        try {
          if(!input.cursor.startsWith("v2.")||!/^v2\.[A-Za-z0-9_-]+$/.test(input.cursor))throw Error();
          const cursor=JSON.parse(Buffer.from(input.cursor.slice(3),"base64url").toString("utf8"));
          if(cursor.v!==2||typeof cursor.id!=="string"||!/^[a-f0-9]{40}$/.test(cursor.id)||cursor.region!==(input.region??null)
            ||!Array.isArray(cursor.time)||cursor.time.length!==2||!cursor.time.every(Number.isSafeInteger)
            ||cursor.time[0]<-62135596800||cursor.time[0]>253402300799||cursor.time[1]<0||cursor.time[1]>=1000000000)throw Error();
          anchorID=cursor.id;expectedTime=cursor.time;
        }catch{throw new HttpsError("invalid-argument","Invalid cursor.");}
      }
      const anchor=await db.doc(`publicationControlRuns/${anchorID}`).get(),time=anchor.get("endedAt");
      if(!anchor.exists||(input.region!=null&&anchor.get("region")!==input.region)
        ||expectedTime&&(!(time instanceof Timestamp)||time.seconds!==expectedTime[0]||time.nanoseconds!==expectedTime[1]))throw new HttpsError("aborted","History changed. Refresh it.");
      query=query.startAfter(anchor);
    }
    const result=await query.limit(81).get(),rows=result.docs.slice(0,80);
    const last=rows.at(-1),time=last?.get("endedAt");
    const cursor=result.size>80&&last ? time instanceof Timestamp ? "v2."+Buffer.from(JSON.stringify({v:2,id:last.id,time:[time.seconds,time.nanoseconds],region:input.region??null})).toString("base64url") : last.id : null;
    return {runs:rows.map(d=>dto(d.data(),d.id)),cursor};
  }
  throw new HttpsError("invalid-argument","Invalid action.");
});
