import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const indexes=JSON.parse(readFileSync(new URL('../../Firebase/firestore.indexes.json',import.meta.url),'utf8')).indexes;
const field=(fieldPath,order)=>({fieldPath,order});
function configured(fields){
  if(fields.length===1)return true; // automatic createdAt index
  return indexes.some(x=>x.collectionGroup==='systemLogs'&&x.queryScope==='COLLECTION'&&JSON.stringify(x.fields)===JSON.stringify(fields));
}
test('journal owner/admin ordering, scalar filters and search have matching deployable indexes',()=>{
  for(const admin of [false,true]){
    const scope=admin?[field('isAppAdminReadable','ASCENDING')]:[];
    for(const sort of ['newestFirst','oldestFirst','severityHighToLow','severityLowToHigh','category']){
      const order=sort.startsWith('severity')?[field('severityRank',sort==='severityHighToLow'?'DESCENDING':'ASCENDING')]:sort==='category'?[field('category','ASCENDING')]:[];
      order.push(field('createdAt',sort==='oldestFirst'?'ASCENDING':'DESCENDING'));
      assert.ok(configured([...scope,...order]),JSON.stringify({admin,sort,search:false}));
      assert.ok(configured([...scope,{fieldPath:'journalSearchGramsV1',arrayConfig:'CONTAINS'},...order]),JSON.stringify({admin,sort,search:true}));
    }
    for(const scalar of ['severity','category','outcome','isReviewed'])for(const direction of ['ASCENDING','DESCENDING']){
      assert.ok(configured([...scope,field(scalar,'ASCENDING'),field('createdAt',direction)]),JSON.stringify({admin,scalar,direction}));
    }
  }
});
