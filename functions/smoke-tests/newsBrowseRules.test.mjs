import {before, after, test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {initializeTestEnvironment, assertFails, assertSucceeds} from "@firebase/rules-unit-testing";
import {collection, doc, setDoc, query, where, or, and, orderBy, documentId, limit, startAfter, getDocs, Timestamp} from "firebase/firestore";
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId:"demo-news-browse",firestore:{
    rules:readFileSync(new URL("../../Firebase/firestore.rules",import.meta.url),"utf8")}});
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async ctx => {
    const db=ctx.firestore();
    for(const [id,topic,additional,region,status] of [
      ["a","housing",["housing"],"wien","approved"],
      ["b","work",["housing"],"austria","approved"],
      ["c","housing",[],"tirol","approved"],
      ["private","housing",[],"wien","pending"]]) {
      await setDoc(doc(db,"news",id),{sourceType:"organization",moderationStatus:status,
        category:topic,additionalCategories:additional,
        regionScope:region==="austria"?"austria":"federalState",federalState:region,
        publishedAt:Timestamp.fromMillis(100000)});
    }
  });
});
after(async()=>{await env?.cleanup();});
test("guest topic OR additional category with region OR national and date bounds paginates both ways",async()=>{
 const db=env.unauthenticatedContext().firestore();
 for(const direction of ["asc","desc"]){
  const constraints=[
   where("sourceType","==","organization"),where("moderationStatus","==","approved"),
   or(where("category","==","housing"),where("additionalCategories","array-contains","housing")),
   or(where("federalState","==","wien"),where("regionScope","==","austria")),
   where("publishedAt",">=",Timestamp.fromMillis(0)),where("publishedAt","<",Timestamp.fromMillis(200000)),
  ];
  const base=query(collection(db,"news"),and(...constraints),orderBy("publishedAt",direction),orderBy(documentId(),direction));
  const first=await assertSucceeds(getDocs(query(base,limit(1))));
  const second=await assertSucceeds(getDocs(query(base,startAfter(first.docs[0]),limit(1))));
  assert.deepEqual([...first.docs,...second.docs].map(d=>d.id),direction==="asc"?["a","b"]:["b","a"]);
  assert.equal((await getDocs(query(base,startAfter(second.docs[0]),limit(1)))).empty,true);
 }
});
test("topic filter cannot grant guests access to unpublished news",async()=>{
 const db=env.unauthenticatedContext().firestore();
 await assertFails(getDocs(query(collection(db,"news"),where("category","==","housing"))));
});
