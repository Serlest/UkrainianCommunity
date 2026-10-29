import {strict as assert} from "node:assert";
import {test} from "node:test";
import {deleteListedContentStorageObjects} from "./contentStorageDeletion";

test("concurrent per-object absence is harmless and deletion work is bounded",async()=>{
  let active=0,peak=0,deleted=0;
  async function* files() {
    for(let i=0;i<27;i++) yield {delete:async(options:{ignoreNotFound:true})=>{
      assert.equal(options.ignoreNotFound,true);active++;peak=Math.max(peak,active);
      await new Promise(resolve=>setTimeout(resolve,1));active--;deleted++;
    }};
  }
  await deleteListedContentStorageObjects(files());
  assert.equal(deleted,27);assert.ok(peak<=10);
});
test("a missing bucket/listing and a forbidden object remain real failures",async()=>{
  const absent=Object.assign(new Error("bucket absent"),{code:404});
  async function* brokenListing(){throw absent;}
  await assert.rejects(deleteListedContentStorageObjects(brokenListing()),error=>error===absent);
  const forbidden=Object.assign(new Error("forbidden"),{code:403});
  async function* forbiddenObject(){yield {delete:async()=>{throw forbidden;}};}
  await assert.rejects(deleteListedContentStorageObjects(forbiddenObject()),error=>error===forbidden);
});
