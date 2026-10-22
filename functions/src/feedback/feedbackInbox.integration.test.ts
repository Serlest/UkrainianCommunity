import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {feedbackIndex, feedbackIndexState, readFeedbackInbox, reconcileFeedbackIndex, listFeedbackInbox} from "./feedbackInbox";
import {dsaRevisionMatches} from "../safety/dsaCases";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
function local() { assert.match(process.env.FIRESTORE_EMULATOR_HOST ?? "", /^(localhost|127\.0\.0\.1):/); }
test("DSA exact CAS and installed NSDate clients accept only the same stored microsecond", () => {
 const time = new Timestamp(1792670000,123456000);
 assert(dsaRevisionMatches(time,"1792670000:123456000","exact"));
 assert(dsaRevisionMatches(time,"1792670000:123456001"));
 assert(!dsaRevisionMatches(time,"1792670000:123456001","exact"));
 assert(!dsaRevisionMatches(time,"1792670000:123457000"));
 assert(!dsaRevisionMatches(time,"1792670000:1000000000"));
});
test("Inbox searches beyond first100, counts whole matching journal, pages in activity order and handles deletion", {skip:!enabled}, async () => {
 local(); await db.recursiveDelete(db.collection("feedback"));
 const batch=db.batch();
 for(let i=0;i<137;i++) {
  const data={status:i%3===0?"closed":i%3===1?"answered":"open",userDisplayName:"Олена Müller",subject:i===0?"Давнє звернення needle":`Звернення ${i}`,
   message:"Detailed request",createdAt:Timestamp.fromMillis(i*1000),updatedAt:Timestamp.fromMillis(i*1000),lastMessageAt:Timestamp.fromMillis((136-i)*1000)};
  const id=`inbox-${String(i).padStart(3,"0")}`;
  batch.set(db.doc(`feedback/${id}`),{...data,...feedbackIndex(id,data)});
 }
 await batch.commit();
 for (const ready of [false,true]) {
  await db.doc(feedbackIndexState).set({ready});
  const result=await readFeedbackInbox(db,{filter:"closed",search:"NEEDLE"});
  assert.deepEqual(result.ids,["inbox-000"]);assert.equal(result.counts.closed,1);
  const first=await readFeedbackInbox(db,{filter:"open"});
  assert.equal(first.ids.length,30);assert.equal(first.counts.open,45);assert.equal(first.counts.closed,46);assert.equal(first.counts.answered,46);
  assert.equal(first.ids[0],"inbox-002");assert(first.cursor);
  const next=await readFeedbackInbox(db,{filter:"open",cursor:first.cursor});
  assert.equal(next.ids.length,15);assert.equal(new Set([...first.ids,...next.ids]).size,45);assert.equal(next.cursor,null);
  const oldest=await readFeedbackInbox(db,{filter:"open",oldest:true});assert.equal(oldest.ids[0],"inbox-134");
  const multi=await readFeedbackInbox(db,{filter:"answered",search:"олена muller"});assert.equal(multi.counts.answered,46);
 }
 await db.doc("feedback/inbox-002").delete();
 const after=await readFeedbackInbox(db,{filter:"open"});assert.equal(after.counts.open,44);assert(!after.ids.includes("inbox-002"));
});
test("Derived index preserves original timestamps, context and concurrent source fields; never recreates deletions",{skip:!enabled},async()=>{
 local();const ref=db.doc("feedback/reconcile");const timestamp=new Timestamp(1792670000,123456000);
 await ref.set({message:"Initial",updatedAt:timestamp,reportContext:{targetId:"news-1"}});
 assert(await reconcileFeedbackIndex(db,"reconcile"));assert(!await reconcileFeedbackIndex(db,"reconcile"));
 await ref.update({message:"Revised",status:"closed"});await reconcileFeedbackIndex(db,"reconcile");
 const saved=await ref.get();assert.equal(saved.get("updatedAt").nanoseconds,123456000);assert.equal(saved.get("reportContext.targetId"),"news-1");assert.equal(saved.get("inboxBucketV1"),"closed");
 await ref.delete();assert(!await reconcileFeedbackIndex(db,"reconcile"));assert(!(await ref.get()).exists);
});
test("Inbox endpoint rejects ordinary users, wrong principal and invalid cursors",{skip:!enabled},async()=>{
 local();for(const [uid,role] of [["feedback-owner","owner"],["feedback-user","user"]]){
  await db.doc(`users/${uid}`).set({globalRole:role,accountStatus:"active",blockState:"active"});await seedCurrentLegalForIntegration(uid);
 }
 const request=(uid:string,data:unknown)=>({auth:{uid,token:{email_verified:true}},data} as never);
 await assert.rejects(listFeedbackInbox.run(request("feedback-user",{principalId:"feedback-user"})),{code:"permission-denied"});
 await assert.rejects(listFeedbackInbox.run(request("feedback-owner",{principalId:"other"})),{code:"permission-denied"});
 await assert.rejects(readFeedbackInbox(db,{cursor:{seconds:1,nanoseconds:1e9,id:"x"}}),{code:"invalid-argument"});
 const result=await listFeedbackInbox.run(request("feedback-owner",{principalId:"feedback-owner",filter:"closed",search:"needle"}));assert.deepEqual(result.ids,["inbox-000"]);
});

test("Real report-decision-appeal flow notifies the affected author and preserves exact CAS and replay safety", {skip:!enabled}, async()=>{
 local();
 const {submitContentReport}=await import("../safety/contentReports");
 const {decideDsaCase,submitDsaAppeal,decideDsaAppeal}=await import("../safety/dsaCases");
 const req=(uid:string,data:unknown)=>({auth:{uid,token:{email_verified:true}},data} as never);
 for(const [uid,role] of [["case-owner","owner"],["case-reporter","user"],["case-author","user"]]){
  await db.doc(`users/${uid}`).set({globalRole:role,accountStatus:"active",blockState:"active",displayName:uid});await seedCurrentLegalForIntegration(uid);
 }
 await db.doc("news/feedback-flow").set({moderationStatus:"approved",title:"Reported article",authorId:"case-author"});
 const report=await submitContentReport.run(req("case-reporter",{targetType:"news",targetId:"feedback-flow",reason:"other",
  illegalExplanation:"A detailed explanation requiring human review",goodFaithConfirmed:true,evidence:"Evidence retained"}));
 const ref=db.doc(`feedback/${report.reportId}`);
 const revision=async()=>{const value=(await ref.get()).get("updatedAt") as Timestamp;return `${value.seconds}:${value.nanoseconds}`;};
 const decision={reportId:report.reportId,outcome:"noAction",factsAndCircumstances:"The notice was reviewed in full by a human reviewer",legalBasis:"Community terms",territorialScope:"Austria",duration:"Permanent",redressInformation:"Submit an appeal",humanReviewConfirmed:true,operationId:"full-flow-decision",expectedRevision:await revision(),revisionFormat:"exact",principalId:"case-owner"};
 await assert.rejects(decideDsaCase.run(req("case-owner",{...decision,expectedRevision:"1:0"})),{code:"aborted"});
 const firstDecision=await decideDsaCase.run(req("case-owner",decision));
 assert.equal((await ref.get()).get("status"),"closed");assert.equal((await ref.get()).get("unreadForUser"),true);
 assert((await db.doc(`users/case-author/dsaStatements/${report.reportId}`).get()).exists);
 const inbox=await db.collection("users/case-author/notificationInbox").where("sourceId","==",report.reportId).get();
 assert.equal(inbox.size,1);assert.equal(inbox.docs[0].get("actionTargetId"),report.reportId);
 const replay=await decideDsaCase.run(req("case-owner",decision));assert.equal(replay.decidedAt,firstDecision.decidedAt);
 assert.equal((await db.collection("users/case-author/notificationInbox").where("sourceId","==",report.reportId).get()).size,1);
 await submitDsaAppeal.run(req("case-reporter",{reportId:report.reportId,reason:"Additional specific facts supporting this appeal",operationId:"full-flow-appeal",expectedRevision:await revision(),revisionFormat:"exact",principalId:"case-reporter"}));
 assert.equal((await ref.get()).get("dsaCase.status"),"appealed");assert.equal((await ref.get()).get("unreadForOwner"),true);
 await decideDsaAppeal.run(req("case-owner",{reportId:report.reportId,outcome:"upheld",reason:"The additional facts were verified by a human reviewer",humanReviewConfirmed:true,operationId:"full-flow-appeal-decision",expectedRevision:await revision(),revisionFormat:"exact",principalId:"case-owner"}));
 assert.equal((await ref.get()).get("dsaCase.status"),"appealDecided");assert.equal((await ref.get()).get("status"),"closed");
});
