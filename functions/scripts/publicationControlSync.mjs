#!/usr/bin/env node
// Read-only local report observer. Its only remote writes are compact owner-only control records.
import {watch} from "node:fs";
import {readFile,readdir,stat,mkdir,writeFile,rename} from "node:fs/promises";
import {join,resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
import {contentAutomationCredential} from "./contentAutomationCredential.mjs";
const regions=["austria","burgenland","kaernten","niederoesterreich","oberoesterreich","salzburg","steiermark","tirol","vorarlberg","wien"];
const bounded=(v)=>Number.isInteger(v)&&v>=0?v:null;
const clean=(v)=>String(v??"").replace(/(?:Bearer\s+|token[=:]\s*)\S+/gi,"[redacted]").replace(/\/(?:Users|tmp)\/[^\s,;]+/g,"[local evidence]").slice(0,600);
export function issueCode(text) {
  if (/lock|quota|gate_busy|capacity/i.test(text)) return "capacity";
  if (/access.?restrict|paywall|403/i.test(text)) return "restrictedSource";
  if (/404|502|fetch|HTTP|timeout|unavailable/i.test(text)) return "sourceUnavailable";
  if (/uncertain|ambiguous|reconcil/i.test(text)) return "uncertainPublication";
  return "incompleteCoverage";
}
export function normalizeControlReport(report,{kind,region,mtime,now=new Date()}) {
  if (!["news","event"].includes(kind)||!regions.includes(region)||typeof report.runId!=="string"||report.runId.length>200||!report.runId.startsWith(kind==="event"?"events-v4-":"news-")&&!report.runId.startsWith("emergency-")) throw Error("Unsupported report identity");
  if ((report.region??report.scope??region)!==region) throw Error("Report scope does not match its path");
  const raw=[...(report.sourceErrors??[]),...(report.coverageErrors??[]),...(report.partialReasons??[]),...(report.coverage?.gaps??[])];
  if (report.reason) raw.push(report.reason);
  const issues=raw.map(row=>typeof row==="string"?row:row.explanation??row.message??row.reason??JSON.stringify(row)).filter(Boolean).map(detail=>({code:issueCode(detail),detail:clean(detail)}));
  const supplied=report.completedAt??report.finishedAt??report.endedAt;
  let date=new Date(supplied??mtime);
  const invalidTime=!Number.isFinite(date.getTime())||date>new Date(now.getTime()+300000);
  if(invalidTime) {
    date=new Date(mtime);
    if(!Number.isFinite(date.getTime())||date>new Date(now.getTime()+300000))throw Error("Invalid report and file times");
    issues.push({code:"invalidReportTime",detail:"The report completion timestamp is invalid. File modification time is shown; the original report has not been changed."});
  }
  let status=["complete","partial","blocked","failed"].includes(report.status)?report.status:"unknown";
  if (status==="complete"&&issues.length) status="partial";
  const published=bounded(report.sourceMetrics?.publishedCount??(typeof report.published==="number"?report.published:null)??report.newPublications?.length??report.publicationIds?.length);
  const candidates=bounded(report.decidedCandidates??report.candidateDecisions?.length);
  const rejected=bounded(report.rejected??(Array.isArray(report.candidateDecisions)?report.candidateDecisions.filter(row=>!["published","alreadyExisted"].includes(row.status)).length:null));
  if (status!=="complete"&&!issues.length) issues.push({code:status==="unknown"?"unsupportedReport":"incompleteCoverage",detail:status==="unknown"?"Report status is missing or unsupported.":"The pass did not report complete coverage."});
  const contentIds=[...new Set([...(report.publicationIds??[]),...(report.newPublications??[]).map(row=>row.contentId??row.id),...(report.publications??[]).map(row=>row.contentId)].filter(v=>typeof v==="string"&&!v.includes("/")&&v.length<=128))];
  const runId=report.runId,id=createHash("sha256").update(`${kind}\0${region}\0${runId}`).digest("hex").slice(0,40);
  return {id,kind,region,runId,status,endedAt:date, timestampBasis:supplied&&!invalidTime?"reportCompletedAt":"reportFileModifiedAt",published,candidates,rejected,sourcesExpected:bounded(report.expectedSources),sourcesChecked:bounded(report.observedSources??report.sourceMetrics?.sourcesAttempted),issues:issues.slice(0,8),issueCount:issues.length,contentIds:contentIds.slice(0,100),publicationOnly:report.publicationOnly===true,expiresAt:new Date(date.getTime()+45*86400000)};
}
export function encode(value) {
  if(value===null||value===undefined)return {nullValue:null};
  if(value instanceof Date)return {timestampValue:value.toISOString()};
  if(Array.isArray(value))return {arrayValue:{values:value.map(encode)}};
  if(typeof value==="object")return {mapValue:{fields:Object.fromEntries(Object.entries(value).map(([k,v])=>[k,encode(v)]))}};
  if(typeof value==="boolean")return {booleanValue:value};
  if(typeof value==="number")return Number.isInteger(value)?{integerValue:String(value)}:{doubleValue:value};
  return {stringValue:String(value)};
}
export function decode(value) {
  if(!value)return null;
  if("timestampValue"in value)return new Date(value.timestampValue);
  if("mapValue"in value)return Object.fromEntries(Object.entries(value.mapValue.fields??{}).map(([k,v])=>[k,decode(v)]));
  if("arrayValue"in value)return (value.arrayValue.values??[]).map(decode);
  if("integerValue"in value)return Number(value.integerValue);
  return Object.values(value)[0];
}
export async function discoverReports(base) {
  const result=[];
  const news=join(base,"progress-v3/news-scopes/reports");
  for(const folder of await readdir(news,{withFileTypes:true}).catch(()=>[])) {
    if(!folder.isDirectory())continue;
    for(const entry of await readdir(join(news,folder.name)))if(entry.endsWith(".json")&&regions.includes(entry.slice(0,-5)))result.push({path:join(news,folder.name,entry),kind:"news",region:entry.slice(0,-5)});
  }
  for(const region of regions.filter(r=>r!=="austria")) {
    const runs=join(base,"artifacts",`events-${region}`,"runs");
    for(const folder of await readdir(runs,{withFileTypes:true}).catch(()=>[]))if(folder.isDirectory()&&folder.name.startsWith("events-v4-"))result.push({path:join(runs,folder.name,"report.json"),kind:"event",region});
  }
  return result;
}
export async function createControlWriter({project=process.env.UAC_FIREBASE_PROJECT_ID??"ukrainiancommunity-dbd5f",fetchImpl=fetch,credential}={}) {
  const identity=credential??await contentAutomationCredential();
  const root=`projects/${project}/databases/(default)/documents`,url=`https://firestore.googleapis.com/v1/${root}`;
  async function request(path,body) {
    const token=await identity.getAccessToken();
    const result=await fetchImpl(url+path,{method:body?"POST":"GET",headers:{Authorization:`Bearer ${token.access_token}`,"Content-Type":"application/json"},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)});
    if(result.status===404)return null;
    if(!result.ok) {const error=Error(`Control sync HTTP ${result.status}`);error.status=result.status;throw error;}
    return result.json();
  }
  const update=(path,data,existing)=>({update:{name:`${root}/${path}`,fields:encode(data).mapValue.fields},currentDocument:existing?{updateTime:existing.updateTime}:{exists:false}});
  return {async write(report,digest) {
    for(let attempt=0;attempt<4;attempt++) {
      const runPath=`publicationControlRuns/${report.id}`,sourcePath=`publicationControlSources/${report.kind}_${report.region}`;
      const [previous,source]=await Promise.all([request('/'+runPath),request('/'+sourcePath)]);
      if(previous) {
        if(decode(previous.fields?.digest)!==digest) throw Error("An imported immutable report changed; review its evidence");
        return false;
      }
      const last=source?decode({mapValue:{fields:source.fields}}):null;
      const writes=[update(runPath,{...report,digest,syncedAt:new Date()},null)];
      const complete=report.status==="complete"?report.endedAt:null;
      if(!last||report.endedAt>=last.endedAt) writes.push(update(sourcePath,{...report,digest,syncedAt:new Date(),lastCompleteAt:complete&&(!last?.lastCompleteAt||complete>last.lastCompleteAt)?complete:last?.lastCompleteAt??null},source));
      else if(complete&&(!last.lastCompleteAt||complete>last.lastCompleteAt))writes.push(update(sourcePath,{...last,lastCompleteAt:complete},source));
      try {await request(':commit',{writes});return true;}catch(error){if(![409,412].includes(error.status)||attempt===3)throw error;}
    }
  }, async heartbeat(imported,errors) {
    await request(':commit',{writes:[{update:{name:`${root}/publicationControlMeta/importer`,fields:encode({syncedAt:new Date(),imported,errors,mode:"localReportObserver",schemaVersion:1}).mapValue.fields}}]});
  }};
}
export async function synchronize({base,writer,cache={},now=new Date(),days=14}) {
  let imported=0,errors=0,skipped=0;
  const entries=await discoverReports(base);
  for(const entry of entries) {
    let metadata;try{metadata=await stat(entry.path);}catch{continue;}
    if(metadata.mtimeMs<now.getTime()-days*86400000||cache[entry.path]===metadata.mtimeMs){skipped++;continue;}
    try {
      const raw=await readFile(entry.path,"utf8"),report=normalizeControlReport(JSON.parse(raw),{...entry,mtime:metadata.mtime,now});
      if(report.endedAt<new Date(now.getTime()-days*86400000)){skipped++;continue;}
      const changed=await writer.write(report,createHash("sha256").update(raw).digest("hex"));
      cache[entry.path]=metadata.mtimeMs;if(changed)imported++;
    } catch(error) {errors++;console.error(JSON.stringify({operation:"publicationControlSync",kind:entry.kind,region:entry.region,error:clean(error.message)}));}
  }
  await writer.heartbeat(imported,errors);
  return {imported,errors,skipped};
}
async function main() {
  const base=resolve(process.env.UAC_AUTOMATION_ROOT??"/Users/serlest/.codex/uac-content-automation"),watchMode=process.argv.includes("--watch");
  const cachePath=join(base,"publication-control-sync-cache.json");
  const cache=JSON.parse(await readFile(cachePath,"utf8").catch(()=>"{}"));
  const writer=await createControlWriter();let running=false,pending=false,retry=0,timer;
  async function sync() {
    if(running){pending=true;return;}running=true;
    try {
      const result=await synchronize({base,writer,cache});
      await mkdir(base,{recursive:true});const temporary=cachePath+".tmp";await writeFile(temporary,JSON.stringify(cache));await rename(temporary,cachePath);
      console.log(JSON.stringify({at:new Date().toISOString(),...result}));
      if(result.errors)throw Error("Some reports remain unsynchronized");retry=0;
    }catch(error){console.error(clean(error.message));if(watchMode){clearTimeout(timer);timer=setTimeout(sync,Math.min(60000,2000*2**Math.min(retry++,5)));}else process.exitCode=1;}
    finally {running=false;if(pending){pending=false;schedule();}}
  }
  function schedule(){clearTimeout(timer);timer=setTimeout(sync,1500);}
  if(watchMode) {
    for(const path of [join(base,"progress-v3/news-scopes/reports"),join(base,"artifacts")])watch(path,{recursive:true},(_,filename)=>{if(filename&&(String(filename).endsWith("/report.json")||path.endsWith("/reports")&&String(filename).endsWith(".json")))schedule();});
  }
  await sync();
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(error=>{console.error(clean(error.message));process.exitCode=1;});
