// Explicit operator maintenance. Dry-run by default; never invokes other cleanup policies.
import {readFileSync,writeFileSync,mkdtempSync,rmSync,realpathSync} from "node:fs";
import {createRequire} from "node:module";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {createHash} from "node:crypto";
import {initializeApp,applicationDefault} from "firebase-admin/app";
import {getFirestore,Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const argv=process.argv.slice(2);
function option(name) { const i=argv.indexOf(name);return i<0 ? undefined:argv[i+1]; }
const project=option("--project"),planPath=option("--plan"),apply=argv.includes("--apply"),verify=argv.includes("--verify");
if (apply && verify) throw new Error("Choose apply or verification");
if (project!=="ukrainiancommunity-dbd5f" || !planPath) throw new Error("Explicit UAC project and --plan are required");
if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error("Production maintenance cannot use an emulator override");
const storageBucket="ukrainiancommunity-dbd5f.firebasestorage.app";
// Reuse the existing Firebase CLI session through standard ADC. The temporary
// owner-readable credential copy is removed on exit and is never logged.
const firebaseRequire=createRequire(realpathSync("/opt/homebrew/bin/firebase"));
const account=firebaseRequire("../auth").getProjectDefaultAccount(fileURLToPath(new URL("../..",import.meta.url)));
if (!account?.tokens?.refresh_token) throw new Error("Existing Firebase CLI session required");
const api=firebaseRequire("../api"),credentialDirectory=mkdtempSync(join(tmpdir(),"uac-retention-"));
process.on("exit",()=>rmSync(credentialDirectory,{recursive:true,force:true}));
process.on("SIGINT",()=>process.exit(130));process.on("SIGTERM",()=>process.exit(143));
const credentialPath=join(credentialDirectory,"adc.json");
writeFileSync(credentialPath,JSON.stringify({type:"authorized_user",client_id:api.clientId(),client_secret:api.clientSecret(),refresh_token:account.tokens.refresh_token}),{mode:0o600});
process.env.GOOGLE_APPLICATION_CREDENTIALS=credentialPath;
initializeApp({projectId:project,storageBucket,credential:applicationDefault()});
const db=getFirestore();
const {deleteEventContent}=await import("../lib/content/contentDeletion.js");
const {eventRetentionDays,isContentRetentionEligible,subtractUtcDays}=await import("../lib/retention/dataRetention.js");
const {contentReferencePoliciesFor,referenceDataMatchesPolicy,contentStoragePrefixes}=await import("../lib/content/contentDeletionPolicy.js");
if (eventRetentionDays!==30) throw new Error("Unexpected event policy");
const fingerprint=plan=>createHash("sha256").update(JSON.stringify(plan)).digest("hex");
async function candidates(cutoff) {
  const snapshot=await db.collection("events").where("moderationStatus","in",["approved","archived"])
    .where("endDate","<=",Timestamp.fromDate(cutoff)).orderBy("endDate").limit(2001).get();
  if (snapshot.size>2000) throw new Error("Candidate count exceeds maintenance bound");
  return snapshot.docs.map(doc=>({id:doc.id,updateTime:doc.updateTime.toDate().toISOString(),
    updateSeconds:doc.updateTime.seconds,updateNanos:doc.updateTime.nanoseconds,
    endDate:doc.get("endDate").toDate().toISOString(),moderationStatus:doc.get("moderationStatus"),
    ...(typeof doc.get("organizationId")==="string" ? {organizationId:doc.get("organizationId")}:{}),
  }));
}
if (verify) {
  const plan=JSON.parse(readFileSync(planPath,"utf8"));
  if (plan.project!==project || plan.retentionDays!==30 || plan.format!=="uac-event-retention30-v1" || plan.events.length>2000 || plan.events.some(x=>!x.id || x.id.includes("/"))) throw new Error("Invalid verification plan");
  const report={project,verifiedAt:new Date().toISOString(),targetCount:plan.events.length,remainingRoots:[],remainingSubcollections:[],remainingReferences:[],remainingMediaPrefixes:[]};
  async function bounded(items,task,width=8) { for (let i=0;i<items.length;i+=width) await Promise.all(items.slice(i,i+width).map(task)); }
  await bounded(plan.events,async item=>{
    const ref=db.collection("events").doc(item.id);
    if ((await ref.get()).exists) report.remainingRoots.push(item.id);
    if ((await ref.listCollections()).length) report.remainingSubcollections.push(item.id);
    for (const prefix of contentStoragePrefixes("events",item.id,item.organizationId)) {
      const [files]=await getStorage().bucket().getFiles({prefix,maxResults:1,autoPaginate:false});
      if (files.length) report.remainingMediaPrefixes.push(prefix);
    }
  });
  const queries=[];
  for (const policy of contentReferencePoliciesFor("events")) {
    for (let offset=0;offset<plan.events.length;offset+=30) queries.push({policy,ids:plan.events.slice(offset,offset+30).map(x=>x.id)});
  }
  await bounded(queries,async({policy,ids})=>{
    const collection=policy.source==="collection" ? db.collection(policy.collectionId):db.collectionGroup(policy.collectionId);
    const snapshot=await collection.where(policy.field,"in",ids).get();
    for (const doc of snapshot.docs) if (referenceDataMatchesPolicy(doc.data(),policy)) report.remainingReferences.push(doc.ref.path);
  });
  writeFileSync(option("--result"),JSON.stringify(report,null,2)+"\n",{flag:"wx"});
  console.log(JSON.stringify(report));
  if (report.remainingRoots.length || report.remainingSubcollections.length || report.remainingReferences.length || report.remainingMediaPrefixes.length) process.exitCode=1;
} else if (!apply) {
  const now=new Date(),cutoff=subtractUtcDays(now,eventRetentionDays);
  const plan={format:"uac-event-retention30-v1",project,storageBucket,createdAt:now.toISOString(),cutoff:cutoff.toISOString(),retentionDays:30,events:await candidates(cutoff)};
  writeFileSync(planPath,JSON.stringify(plan,null,2)+"\n",{flag:"wx"});
  console.log(JSON.stringify({mode:"dry-run",cutoff:plan.cutoff,count:plan.events.length,planSHA256:fingerprint(plan)}));
} else {
  const plan=JSON.parse(readFileSync(planPath,"utf8")),resultPath=option("--result"),expected=Number(option("--expected-count"));
  if (!resultPath || !Number.isInteger(expected) || expected!==plan.events?.length ||
      option("--plan-sha256")!==fingerprint(plan) || plan.project!==project || plan.storageBucket!==storageBucket ||
      plan.format!=="uac-event-retention30-v1" || plan.retentionDays!==30 || expected>2000 ||
      new Set(plan.events.map(x=>x.id)).size!==expected || plan.events.some(x=>!x.id || x.id.includes("/")) ||
      Date.now()-Date.parse(plan.createdAt)>7200000 || Date.parse(plan.createdAt)>Date.now() ||
      !Number.isFinite(Date.parse(plan.cutoff)) || Date.parse(plan.cutoff)>Date.now()-30*86400000) throw new Error("Plan/explicit count/hash guard failed");
  const cutoff=new Date(plan.cutoff),result={project,cutoff:plan.cutoff,planSHA256:fingerprint(plan),startedAt:new Date().toISOString(),deleted:[],alreadyAbsent:[],changedSkipped:[],failed:[]};
  if (plan.events.length) await getStorage().bucket().getFiles({prefix:`events/${plan.events[0].id}/`,maxResults:1,autoPaginate:false});
  writeFileSync(resultPath,JSON.stringify(result,null,2)+"\n",{flag:"wx"});
  async function removePlanned(item) {
    try {
    const current=await db.collection("events").doc(item.id).get();
    if (!current.exists) { result.alreadyAbsent.push(item.id); }
    else if (current.updateTime.seconds!==item.updateSeconds || current.updateTime.nanoseconds!==item.updateNanos || !isContentRetentionEligible("events",current.data(),cutoff)) { result.changedSkipped.push(item.id); }
    else {
        await deleteEventContent(item.id,current.data());
        if ((await current.ref.get()).exists) throw new Error("Root still exists after deletion");
        result.deleted.push(item.id);
    }
    } catch(error) { result.failed.push({id:item.id,code:String(error.code??error.name??"unknown")}); }
    writeFileSync(resultPath,JSON.stringify(result,null,2)+"\n");
  }
  for (let offset=0;offset<plan.events.length;offset+=6) {
    await Promise.all(plan.events.slice(offset,offset+6).map(removePlanned));
  }
  result.remainingAtFixedCutoff=(await candidates(cutoff)).map(x=>x.id);result.finishedAt=new Date().toISOString();
  writeFileSync(resultPath,JSON.stringify(result,null,2)+"\n");
  console.log(JSON.stringify({mode:"apply",deleted:result.deleted.length,alreadyAbsent:result.alreadyAbsent.length,changedSkipped:result.changedSkipped.length,failed:result.failed.length,remaining:result.remainingAtFixedCutoff.length}));
  if (result.failed.length || result.changedSkipped.length || result.remainingAtFixedCutoff.length) process.exitCode=1;
}
