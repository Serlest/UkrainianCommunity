import fs from 'node:fs';
import {createHash} from 'node:crypto';
const [source,output]=process.argv.slice(2);
if(!source || !output) throw Error('Usage: generateDirectoryRecentBaseline.mjs exported-catalog.json output.ts');
const raw=fs.readFileSync(source,'utf8');
const catalog=JSON.parse(raw);
const hash=(values)=>createHash('sha256').update(JSON.stringify(values)).digest('hex');
const baseline={};
for(const category of catalog){
 const ids=[];
 for(const topic of category.topics){
  ids.push(hash(['topic',category.id,topic.id,'','']));
  const add=(sections,region)=>{for(const s of sections)ids.push(hash(['section',category.id,topic.id,s.id,region]));};
  add(topic.sections,'');
  for(const [region,sections] of Object.entries(topic.regionalSections))add(sections,region);
 }
 baseline[category.id]=[...new Set(ids)].sort();
}
fs.writeFileSync(output,'// Generated from the authoritative bundled Directory export; historical IDs have no invented publication date.\n// Source SHA-256: '+createHash('sha256').update(raw).digest('hex')+'\nexport const directoryRecentBaseline: Record<string, readonly string[]> = '+JSON.stringify(baseline)+';\n');
