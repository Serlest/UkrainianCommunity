import {test} from "node:test";
import {strict as assert} from "node:assert";
import {db} from "../firebase/admin";
import {getDirectoryRecentAdditions, recordDirectoryAdditions, recentRequest} from "./directoryRecent";

const enabled = Boolean(process.env.FIRESTORE_EMULATOR_HOST);
test("recent feed is guest readable, correction-stable, paginated, and filters current hidden content", {skip:!enabled}, async()=>{
 const id = "recent-integration";
 const text={ukrainian:"Тест",german:"Test"};
 const section={id:"section-one",title:text,isHidden:false};
 const topic={id:"topic-one",groupID:"general",title:text,isHidden:false,sections:[section],regionalSections:{}};
 const category={id,title:text,isHidden:false,groups:[{id:"general",isHidden:false}],topics:[topic]};
 const ref=db.collection("directoryCategories").doc(id);
 await db.recursiveDelete(db.collection("directoryRecentAdditions"));
 await db.recursiveDelete(ref);
 async function publish(revision:number) {
   await db.runTransaction(async tx=>{
     const old=await tx.get(ref);
     await recordDirectoryAdditions(tx,id,old.data()?.payload,JSON.stringify(category),revision);
     tx.set(ref,{payload:JSON.stringify(category),revision});
   });
 }
 const read=async(data:unknown)=>getDirectoryRecentAdditions.run({data} as never);
 await publish(1);
 assert.equal((await read({limit:1})).items.length,1);
 category.title={ukrainian:"Виправлено",german:"Korrigiert"};await publish(2);
 assert.equal((await db.collection("directoryRecentAdditions").get()).size,1);
 category.topics[0].sections.push({...section,id:"section-two"});await publish(3);
 const first=await read({limit:1});assert.equal(first.hasMore,true);
 const second=await read({limit:1,cursor:first.nextCursor});
 assert.equal(second.items.length,1);assert.notEqual(first.items[0].id,second.items[0].id);
 assert.equal(second.hasMore,false);
 category.isHidden=true;await publish(4);
 assert.equal((await read({limit:20})).items.length,0);
 category.isHidden=false;await publish(5);
 assert.equal((await read({limit:20})).items.length,2);
 await ref.update({isDeleted:true});
 assert.equal((await read({limit:20})).items.length,0);
});
test("recent cursor and request reject malformed input",()=>{
 for(const input of [null,[],{limit:0},{limit:51},{cursor:{}},{cursor:{seconds:1,nanoseconds:1e9,id:"a".repeat(64)}},{unexpected:true}]) {
  assert.throws(()=>recentRequest(input));
 }
});
