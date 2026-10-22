#!/usr/bin/env node
import {createRequire} from "node:module";
import {execFileSync} from "node:child_process";
import {Firestore, FieldPath, FieldValue} from "firebase-admin/firestore";
import {OAuth2Client} from "google-auth-library";
const args=process.argv.slice(2),project=args.find(x=>x.startsWith("--project="))?.slice(10),apply=args.includes("--apply"),activate=args.includes("--activate");
if(!project||apply&&activate||(apply||activate)&&!args.includes(`--confirm-project=${project}`)||args.some(x=>!x.startsWith("--project=")&&!x.startsWith("--confirm-project=")&&!["--apply","--activate"].includes(x)))throw Error("Explicit project required; writes require --confirm-project=ID. Default is read-only.");
if(process.env.FIRESTORE_EMULATOR_HOST&&!project.startsWith("demo-"))throw Error("Emulator requires demo project.");
process.env.GCLOUD_PROJECT=project;
const require=createRequire(import.meta.url),{organizationSearchGrams,reconcileWorkspaceIndex,workspaceIndexState}=require("../lib/organizations/managementWorkspace.js");
const token=execFileSync("gcloud",["auth","print-access-token"],{encoding:"utf8"}).trim(),authClient=new OAuth2Client();authClient.setCredentials({access_token:token,expiry_date:Date.now()+3000000});
const db=new Firestore({projectId:project,authClient});
try{
 if(apply)await db.doc(workspaceIndexState).set({ready:false,version:1},{merge:true});
 let scanned=0,mismatched=0,written=0;const stream=db.collection("organizations").orderBy(FieldPath.documentId()).stream();
 try{for await(const doc of stream){scanned++;if(JSON.stringify(doc.get("workspaceSearchV1"))===JSON.stringify(organizationSearchGrams(doc.id,doc.data())))continue;mismatched++;if(apply&&await reconcileWorkspaceIndex(db,doc.id))written++;}}finally{stream.destroy();}
 if(activate){
  if(mismatched)throw Error("Separate clean verification required before activation.");
  const res=await fetch(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/europe-west3/functions/maintainOrganizationWorkspaceIndex`,{headers:{Authorization:`Bearer ${token}`}});if(!res.ok)throw Error(`Writer readback failed: ${res.status}`);const writer=await res.json();
  if(writer.state!=="ACTIVE"||writer.eventTrigger?.retryPolicy!=="RETRY_POLICY_RETRY"||writer.eventTrigger?.eventFilters?.find(f=>f.attribute==="document")?.value!=="organizations/{organizationId}")throw Error("Index writer must be ACTIVE with retries.");
  for(const region of [false,true]){
   const base=db.collection("organizations").where("moderationStatus","==","approved");
   const scoped=region?base.where("federalState","==","tirol"):base;
   for(const query of [scoped,scoped.where("workspaceSearchV1","array-contains-any",["abc","!overflow-v1"]),scoped.where("ownerId","==","workspace-index-verification"),scoped.where("adminIds","array-contains","workspace-index-verification"),scoped.where("moderatorIds","array-contains","workspace-index-verification")])await query.orderBy(FieldPath.documentId()).limit(1).get();
  }
  for(const name of ["news","events"]){
   const base=db.collection(name).where("organizationId","==","workspace-index-verification").where("sourceType","==","organization");
   await base.orderBy(FieldPath.documentId()).limit(1).get();await base.where("moderationStatus","==","needsRevision").orderBy(FieldPath.documentId()).limit(1).get();await base.where("moderationStatus","in",["draft","pendingReview","needsRevision","approved","rejected","archived"]).count().get();
  }
  await db.collection("likes").where("subscribedOrganizationId","==","workspace-index-verification").where("userId","==","workspace-index-verification").limit(1).get();
  await db.doc(workspaceIndexState).set({ready:true,version:1,verifiedAt:FieldValue.serverTimestamp()},{merge:true});
 }
 console.log(JSON.stringify({mode:apply?"apply":activate?"activate":"verify",scanned,mismatched,written,ready:(await db.doc(workspaceIndexState).get()).get("ready")===true}));
}finally{await db.terminate();}
