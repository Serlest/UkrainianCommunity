import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {parseBannerTextAppearance, parseFeaturedBannerDraft, canonicalFeaturedBannerData, saveFeaturedBanner, getFeaturedBannerPresentations, deleteFeaturedBanner} from "./featuredBannerMutations";

const draft = (id: string, extra: Record<string, unknown> = {}) => ({id, imageURL:"https://example.com/banner.jpg", title:"Подія", actionType:"none", regionScope:"allAustria", visibleSections:["home"], displayDurationSeconds:6, priority:0, isActive:true, presentationVersion:2, textAppearance:{titleColorHex:"#2458a6",subtitleColorHex:"#ffd43b"},...extra});
const request = (uid: string | undefined, data: unknown) => ({data,auth:uid?{uid,token:{email_verified:true,firebase:{sign_in_second_factor:"totp"}}}:undefined}) as never;

test("text colors validate independently and never enter strict legacy banner documents",()=>{
 assert.deepEqual(parseBannerTextAppearance({titleColorHex:"#ff00aA"}),{titleColorHex:"#FF00AA"});
 assert.deepEqual(parseBannerTextAppearance({subtitleColorHex:null}),{});
 for (const value of [[],{titleColorHex:5},{subtitleColorHex:"#fff"},{titleColorHex:"#FFFFFF00"},{titleColorHex:"transparent"},{titleColorHex:"#FFFFFF",actorID:"x"}]) assert.throws(()=>parseBannerTextAppearance(value));
 const data=canonicalFeaturedBannerData(parseFeaturedBannerDraft(draft("style-validation")),"owner",Timestamp.now());
 for (const key of ["textAppearance","titleColorHex","subtitleColorHex","presentationVersion","countdown"]) assert.equal(key in data,false);
 assert.equal(parseFeaturedBannerDraft(draft("v1",{presentationVersion:1})).textAppearance,undefined);
 assert.throws(()=>parseFeaturedBannerDraft(draft("v3",{presentationVersion:3})));
});

test("real owner save/read/reset preserves custom colors across v1 and legacy clients",{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
 assert.match(process.env.GCLOUD_PROJECT??"",/^demo-/);
 const id="style-"+randomUUID(),owner="style-owner-"+randomUUID(),member="style-member-"+randomUUID();
 for (const [uid,role] of [[owner,"owner"],[member,"user"]]) await db.doc(`users/${uid}`).set({globalRole:role,accountStatus:"active",createdAt:Timestamp.now(),requiresMultiFactorAuth:role==="owner"});
 await seedCurrentLegalForIntegration(owner,member);
 const data=draft(id),operationID=randomUUID(),command={mode:"create",banner:data,operationID,principalID:owner};
 try {
  for (const uid of [undefined,member]) await assert.rejects(saveFeaturedBanner.run(request(uid,command)));
  await saveFeaturedBanner.run(request(owner,command));
  await saveFeaturedBanner.run(request(owner,command));
  await assert.rejects(saveFeaturedBanner.run(request(owner,{...command,banner:draft(id,{textAppearance:{titleColorHex:"#000000"}})})),{code:"aborted"});
  const read=async()=>await getFeaturedBannerPresentations.run(request(undefined,{ids:[id]}));
  assert.deepEqual((await read()).presentations[0].textAppearance,{titleColorHex:"#2458A6",subtitleColorHex:"#FFD43B"});
  const core=(await db.doc(`featuredBanners/${id}`).get()).data()!;
  for (const field of ["textAppearance","presentationVersion","countdown"]) assert.equal(field in core,false);
  assert.equal(JSON.stringify(await read()).includes(owner),false);
  assert.equal(JSON.stringify(await read()).includes(operationID),false);
  const old=draft(id,{presentationVersion:1,countdown:null});delete (old as Record<string,unknown>).textAppearance;
  await saveFeaturedBanner.run(request(owner,{mode:"update",banner:old}));
  assert.equal((await read()).presentations[0].textAppearance!.subtitleColorHex,"#FFD43B");
  delete (old as Record<string,unknown>).presentationVersion;
  await saveFeaturedBanner.run(request(owner,{mode:"update",banner:old}));
  assert.equal((await read()).presentations[0].textAppearance!.titleColorHex,"#2458A6");
  await saveFeaturedBanner.run(request(owner,{mode:"update",banner:draft(id,{textAppearance:{subtitleColorHex:"#E53935"}})}));
  assert.deepEqual((await read()).presentations[0].textAppearance,{subtitleColorHex:"#E53935"});
  await saveFeaturedBanner.run(request(owner,{mode:"update",banner:draft(id,{textAppearance:{}})}));
  assert.deepEqual((await read()).presentations[0].textAppearance,{});
  await db.doc(`featuredBannerPresentations/${id}`).update({textAppearance:{titleColorHex:"invalid"}});
  assert.deepEqual((await read()).presentations[0].textAppearance,{});
  await deleteFeaturedBanner.run(request(owner,{id}));
  assert.equal((await db.doc(`featuredBannerPresentations/${id}`).get()).exists,false);
 } finally {
  for (const path of [`featuredBanners/${id}`,`featuredBannerPresentations/${id}`,`bannerMeasurementHistory/${id}`,`users/${owner}`,`users/${member}`]) await db.doc(path).delete();
 }
});
