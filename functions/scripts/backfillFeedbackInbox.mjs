#!/usr/bin/env node
// Derive search metadata only; do not alter source timestamps, replies or complaint evidence.
import {createRequire} from "node:module";
import {execFileSync} from "node:child_process";
import {Firestore, FieldPath, FieldValue} from "firebase-admin/firestore";
import {OAuth2Client} from "google-auth-library";
const args=process.argv.slice(2), project=args.find(x=>x.startsWith("--project="))?.slice(10);
const apply=args.includes("--apply"),activate=args.includes("--activate");
if (!project || (apply && activate) || ((apply||activate) && !args.includes(`--confirm-project=${project}`)) ||
 args.some(x=> !x.startsWith("--project=")&&!x.startsWith("--confirm-project=")&&!["--apply","--activate"].includes(x))) throw Error("Explicit project required; --apply or --activate requires --confirm-project=ID. Default is read-only.");
if(process.env.FIRESTORE_EMULATOR_HOST&&!project.startsWith("demo-"))throw Error("Emulator requires demo project.");
process.env.GCLOUD_PROJECT=project;
const require=createRequire(import.meta.url);
const {feedbackIndex,reconcileFeedbackIndex,feedbackIndexState}=require("../lib/feedback/feedbackInbox.js");
const token=execFileSync("gcloud",["auth","print-access-token"],{encoding:"utf8"}).trim();
const authClient=new OAuth2Client();authClient.setCredentials({access_token:token,expiry_date:Date.now()+3000000});
const db=new Firestore({projectId:project,authClient});
try {
 if(apply)await db.doc(feedbackIndexState).set({ready:false,version:1},{merge:true});
 let scanned=0,mismatched=0,written=0;
 const stream=db.collection("feedback").orderBy(FieldPath.documentId()).stream();
 try{for await(const doc of stream){
  scanned++;const expected=feedbackIndex(doc.id,doc.data());
  if(Object.entries(expected).every(([k,v])=>JSON.stringify(doc.get(k))===JSON.stringify(v)))continue;
  mismatched++;if(apply && await reconcileFeedbackIndex(db,doc.id))written++;
 }}finally{stream.destroy();}
 if(activate){
  if(mismatched)throw Error("Separate clean verification required before activation.");
  const response=await fetch(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/europe-west3/functions/maintainFeedbackInboxIndex`,{headers:{Authorization:`Bearer ${token}`}});
  if(!response.ok)throw Error(`Cannot verify writer: HTTP ${response.status}`);
  const writer=await response.json();
  if(writer.state!=="ACTIVE"||writer.eventTrigger?.retryPolicy!=="RETRY_POLICY_RETRY"||writer.eventTrigger?.eventFilters?.find(f=>f.attribute==="document")?.value!=="feedback/{feedbackId}")throw Error("Writer must be ACTIVE with retries and the correct trigger.");
  for(const bucket of ["open","answered","closed"])for(const direction of ["asc","desc"]){
   await db.collection("feedback").where("inboxBucketV1","==",bucket).orderBy("inboxActivityV1",direction).orderBy(FieldPath.documentId(),direction).limit(1).get();
  }
  await db.collection("feedback").where("inboxGramsV1","array-contains-any",["a","!overflow"]).orderBy(FieldPath.documentId()).limit(1).get();
  await db.doc(feedbackIndexState).set({ready:true,version:1,verifiedAt:FieldValue.serverTimestamp()},{merge:true});
 }
 console.log(JSON.stringify({mode:apply?"apply":activate?"activate":"verify",scanned,mismatched,written,ready:(await db.doc(feedbackIndexState).get()).get("ready")===true}));
}finally{await db.terminate();}
