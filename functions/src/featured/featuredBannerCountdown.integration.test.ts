import {strict as assert} from "node:assert";
import {test} from "node:test";
import {randomUUID} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {db} from "../firebase/admin";
import {seedCurrentLegalForIntegration} from "../auth/legalIntegrationFixture";
import {saveFeaturedBanner, setFeaturedBannerActive, deleteFeaturedBanner, getFeaturedBannerPresentations, parseFeaturedBannerDraft, canonicalFeaturedBannerData} from "./featuredBannerMutations";

const target = "2027-03-28T01:30:00.000Z";
const draft = (id: string, overrides: Record<string, unknown> = {}) => ({id, imageURL:"https://example.com/banner.jpg", title:"Подія", actionType:"none", regionScope:"allAustria", visibleSections:["home"], displayDurationSeconds:6, priority:0, isActive:true, presentationVersion:1, countdown:{targetDate:target,label:"До події",germanLabel:"Bis zum Ereignis",completion:"hideBanner"},...overrides});
const req = (uid: string | undefined, data: unknown, totp=true) => ({data,auth:uid?{uid,token:{email_verified:true,firebase:{sign_in_second_factor:totp?"totp":undefined}}}:undefined}) as never;

test("countdown validates limits and completion without adding unknown legacy banner fields",()=>{
 const parsed = parseFeaturedBannerDraft(draft("validation"));
 const data = canonicalFeaturedBannerData(parsed,"owner",Timestamp.now());
 assert.equal(data.endsAt.toDate().toISOString(),target);
 for (const key of ["countdown","presentationVersion","operationID"]) assert.equal(key in data,false);
 assert.throws(()=>parseFeaturedBannerDraft(draft("invalid",{countdown:{targetDate:target,label:"😀".repeat(21),completion:"showStarted"}})));
 assert.throws(()=>parseFeaturedBannerDraft(draft("invalid",{countdown:{targetDate:target,completion:"arbitrary"}})));
 assert.throws(()=>parseFeaturedBannerDraft(draft("invalid",{countdown:{targetDate:"bad",completion:"showStarted"}})));
 assert.throws(()=>parseFeaturedBannerDraft(draft("invalid",{startsAt:target})));
 const legacy=draft("legacy"); delete (legacy as Record<string,unknown>).presentationVersion; delete (legacy as Record<string,unknown>).countdown;
 assert.equal(parseFeaturedBannerDraft(legacy).presentationVersion,undefined);
});

test("real owner CRUD preserves old binary schema, replay, revision, private metadata and completion",{skip:!process.env.FIRESTORE_EMULATOR_HOST},async()=>{
 assert.match(process.env.GCLOUD_PROJECT??"",/^demo-/);
 const id="countdown-"+randomUUID(),owner="b14-owner",member="b14-member",admin="b14-admin";
 for (const [uid,role] of [[owner,"owner"],[member,"user"],[admin,"admin"]]) await db.doc(`users/${uid}`).set({globalRole:role,accountStatus:"active",createdAt:Timestamp.now(),requiresMultiFactorAuth:role==="owner"});
 await seedCurrentLegalForIntegration(owner,member,admin);
 const request={mode:"create",banner:draft(id),operationID:randomUUID(),principalID:owner};
 try {
  for (const uid of [undefined,member,admin]) await assert.rejects(saveFeaturedBanner.run(req(uid,request)));
  await assert.rejects(saveFeaturedBanner.run(req(owner,request,false)));
  await assert.rejects(saveFeaturedBanner.run(req(owner,{...request,principalID:member})),{code:"permission-denied"});
  await saveFeaturedBanner.run(req(owner,request));
  const initial=await db.doc(`featuredBanners/${id}`).get();
  assert.equal(initial.get("countdown"),undefined); assert.equal(initial.get("endsAt").toDate().toISOString(),target);
  await saveFeaturedBanner.run(req(owner,request));
  assert.equal((await db.doc(`featuredBanners/${id}`).get()).get("updatedAt").toMillis(),initial.get("updatedAt").toMillis());
  await assert.rejects(saveFeaturedBanner.run(req(owner,{...request,banner:{...request.banner,title:"Different"}})),{code:"aborted"});
  const visible=await getFeaturedBannerPresentations.run(req(undefined,{ids:[id,"missing"]}));
  assert.equal(visible.presentations.length,1); assert.equal(visible.presentations[0].countdown!.targetDate,target);
  assert.equal(JSON.stringify(visible).includes(owner),false); assert.equal(JSON.stringify(visible).includes(request.operationID),false);
  await assert.rejects(getFeaturedBannerPresentations.run(req(member,{ids:[id],includeInactive:true})),{code:"permission-denied"});
  await setFeaturedBannerActive.run(req(owner,{id,isActive:false}));
  assert.equal((await getFeaturedBannerPresentations.run(req(undefined,{ids:[id]}))).presentations.length,0);
  assert.equal((await getFeaturedBannerPresentations.run(req(owner,{ids:[id],includeInactive:true}))).presentations.length,1);
  await assert.rejects(saveFeaturedBanner.run(req(owner,{mode:"update",banner:draft(id),expectedUpdatedAt:initial.get("updatedAt").toDate().toISOString(),operationID:randomUUID()})),{code:"aborted"});
  const legacy=draft(id,{isActive:false}); delete (legacy as Record<string,unknown>).presentationVersion; delete (legacy as Record<string,unknown>).countdown;
  await saveFeaturedBanner.run(req(owner,{mode:"update",banner:legacy}));
  assert.equal((await getFeaturedBannerPresentations.run(req(owner,{ids:[id],includeInactive:true}))).presentations.length,1);
  await saveFeaturedBanner.run(req(owner,{mode:"update",banner:draft(id,{countdown:null}),operationID:randomUUID()}));
  assert.equal((await getFeaturedBannerPresentations.run(req(undefined,{ids:[id]}))).presentations[0].countdown,undefined);
  await deleteFeaturedBanner.run(req(owner,{id}));
  assert.equal((await db.doc(`featuredBannerPresentations/${id}`).get()).exists,false);
  assert.equal((await db.doc(`featuredBanners/${id}`).get()).exists,false);
 } finally {
  for (const path of [`featuredBanners/${id}`,`featuredBannerPresentations/${id}`,`bannerMeasurementHistory/${id}`,...[owner,member,admin].map(uid=>`users/${uid}`)]) await db.doc(path).delete();
 }
});
