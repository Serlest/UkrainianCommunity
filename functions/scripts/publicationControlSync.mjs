#!/usr/bin/env node
// Read-only local report observer. Its only remote writes are compact owner-only control records.
import {watch} from "node:fs";
import {readFile,readdir,stat,mkdir,writeFile,rename} from "node:fs/promises";
import {join,resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {createHash} from "node:crypto";
import {contentAutomationCredential} from "./contentAutomationCredential.mjs";
const regions=["austria","burgenland","kaernten","niederoesterreich","oberoesterreich","salzburg","steiermark","tirol","vorarlberg","wien"];
const bounded=(v)=>Number.isSafeInteger(v)&&v>=0?v:null;
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
  const scheduledAt=new Date(report.scheduledAt??report.startedAt);
  const runId=report.runId,id=createHash("sha256").update(`${kind}\0${region}\0${runId}`).digest("hex").slice(0,40);
  return {id,kind,region,runId,status,scheduledAt:Number.isFinite(scheduledAt.getTime())&&scheduledAt<=date?scheduledAt:null,endedAt:date, timestampBasis:supplied&&!invalidTime?"reportCompletedAt":"reportFileModifiedAt",published,candidates,rejected,sourcesExpected:bounded(report.expectedSources),sourcesChecked:bounded(report.observedSources??report.sourceMetrics?.sourcesAttempted),issues:issues.slice(0,8),issueCount:issues.length,contentIds:contentIds.slice(0,100),publicationOnly:report.publicationOnly===true,expiresAt:new Date(date.getTime()+45*86400000)};
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
    if(!folder.isDirectory()||folder.name.startsWith("qa-"))continue;
    for(const entry of await readdir(join(news,folder.name)))if(entry.endsWith(".json")&&regions.includes(entry.slice(0,-5)))result.push({path:join(news,folder.name,entry),kind:"news",region:entry.slice(0,-5)});
  }
  for(const region of regions.filter(r=>r!=="austria")) {
    const runs=join(base,"artifacts",`events-${region}`,"runs");
    for(const folder of await readdir(runs,{withFileTypes:true}).catch(()=>[]))if(folder.isDirectory()&&folder.name.startsWith("events-v4-"))result.push({path:join(runs,folder.name,"report.json"),kind:"event",region});
  }
  return result;
}
export function semanticDigest(row) {
  const keys=['id','kind','region','runId','status','endedAt','timestampBasis','published','candidates','rejected','sourcesExpected','sourcesChecked','issues','issueCount','contentIds','publicationOnly'];
  function canonical(v){if(v instanceof Date)return v.toISOString();if(Array.isArray(v))return v.map(canonical);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])]));return v??null;}
  return createHash('sha256').update(JSON.stringify(canonical(Object.fromEntries(keys.map(k=>[k,row[k]]))))).digest('hex');
}
export async function readControlSchedules(folder=join(process.env.HOME??'', '.codex/automations')) {
  const aliases={austria:'sterreich-und-l-nder',kaernten:'k-rnten',niederoesterreich:'nieder-sterreich',oberoesterreich:'ober-sterreich'},result={};
  for(const kind of ['news','event'])for(const region of regions.filter(r=>kind==='news'||r!=='austria')) {
    const id=`uac-${kind==='news'?'news':'events'}-${aliases[region]??region}`;
    const raw=await readFile(join(folder,id,'automation.toml'),'utf8').catch(()=>'');
    if(!/^status\s*=\s*"ACTIVE"/m.test(raw))continue;
    const rule=raw.match(/^rrule\s*=\s*"([^"\n]+)"/m)?.[1];
    const hours=rule?.match(/BYHOUR=([0-9,]+)/)?.[1].split(',').map(Number),minutes=rule?.match(/BYMINUTE=([0-9,]+)/)?.[1].split(',').map(Number);
    if(rule?.includes('FREQ=DAILY')&&!/BYDAY=|BYMONTH=|INTERVAL=(?!1(?:;|$))/.test(rule)&&hours?.every(h=>h>=0&&h<24)&&minutes?.every(m=>m>=0&&m<60))result[kind+'_'+region]={hours,minutes,timeZone:'Europe/Vienna',graceMinutes:90};
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
  const update=(path,data,existing)=>({update:{name:`${root}/${path}`,fields:encode(path.includes("/revisions/")?{...data,publicationControlExpiresAt:data.expiresAt}:data).mapValue.fields},currentDocument:existing?{updateTime:existing.updateTime}:{exists:false}});
  return {async write(report,digest) {
    const semantic=semanticDigest(report);
    for(let attempt=0;attempt<4;attempt++) {
      const runPath=`publicationControlRuns/${report.id}`,sourcePath=`publicationControlSources/${report.kind}_${report.region}`;
      const [previous,source]=await Promise.all([request('/'+runPath),request('/'+sourcePath)]);
      const old=previous?decode({mapValue:{fields:previous.fields}}):null,last=source?decode({mapValue:{fields:source.fields}}):null;
      const oldSemantic=old?semanticDigest(old):null;
      if(oldSemantic===semantic&&old?.semanticDigest===semantic&&JSON.stringify(encode(old.schedule))===JSON.stringify(encode(report.schedule))&&JSON.stringify(encode(old.scheduledAt))===JSON.stringify(encode(report.scheduledAt)))return false;
      const versionPath=`${runPath}/revisions/${semantic}`;
      const archived=await request('/'+versionPath);
      // A duplicate older file must never roll a logical pass back to a seen revision.
      if(archived&&oldSemantic!==semantic)return false;
      const writes=[];
      if(old&&!old.semanticDigest) {
        const path=`${runPath}/revisions/${oldSemantic}`;
        if(!await request('/'+path))writes.push(update(path,{...old,semanticDigest:oldSemantic},null));
      }
      const changed=oldSemantic!==semantic;
      const row={...report,digest,semanticDigest:semantic,revisionNumber:old?(old.revisionNumber??1)+(changed?1:0):1,schemaVersion:2,syncedAt:changed?new Date():old.syncedAt??new Date()};
      if(!archived&&(!old||oldSemantic!==semantic||old.semanticDigest))writes.push(update(versionPath,row,null));
      writes.push(update(runPath,row,previous));
      const complete=report.status==="complete"?report.endedAt:null;
      let lastComplete=last?.lastCompleteAt??null;
      if(old?.status==="complete"&&report.status!=="complete"&&lastComplete?.getTime()===old.endedAt?.getTime())lastComplete=null;
      if(complete&&(!lastComplete||complete>lastComplete))lastComplete=complete;
      if(!last||last.id===report.id||report.endedAt>=last.endedAt)writes.push(update(sourcePath,{...row,lastCompleteAt:lastComplete},source));
      else if(lastComplete?.getTime()!==last?.lastCompleteAt?.getTime())writes.push(update(sourcePath,{...last,lastCompleteAt:lastComplete},source));
      try{await request(':commit',{writes});return changed;}catch(error){if(![409,412].includes(error.status)||attempt===3)throw error;}
    }
  },async heartbeat(imported,errors,issues=[]) {
    const previous=await request('/publicationControlMeta/importer'),old=previous?decode({mapValue:{fields:previous.fields}}):{};
    const now=new Date();
    await request(':commit',{writes:[update('publicationControlMeta/importer',{...old,lastAttemptAt:now,
      ...(errors===0?{lastSuccessfulCheckAt:now,syncedAt:now}:{}),...(imported>0?{lastImportedAt:now}:{}),
      imported,errors,issues:issues.slice(0,20),mode:'localReportObserver',schemaVersion:2},previous)]});
  }};
}
export async function synchronize({base,writer,cache={},now=new Date(),days=14,schedules={}}) {
  let imported=0,errors=0,skipped=0;const issues=[];
  const scheduleDigest=createHash('sha256').update(JSON.stringify(schedules)).digest('hex');
  const schedulesChanged=cache.$schedule!==scheduleDigest;
  const entries=await discoverReports(base);
  const pending=[];for(const entry of entries){try{pending.push({...entry,metadata:await stat(entry.path)})}catch{}}
  pending.sort((a,b)=>a.metadata.mtimeMs-b.metadata.mtimeMs);
  for(const entry of pending) {
    const metadata=entry.metadata;
    if(metadata.mtimeMs<now.getTime()-days*86400000||!schedulesChanged&&(cache[entry.path]?.mtime??cache[entry.path])===metadata.mtimeMs){if(cache[entry.path]?.error){errors++;issues.push(cache[entry.path].error)}else skipped++;continue;}
    try {
      const raw=await readFile(entry.path,"utf8"),report=normalizeControlReport(JSON.parse(raw),{...entry,mtime:metadata.mtime,now});
      if(report.endedAt<new Date(now.getTime()-days*86400000)){skipped++;continue;}
      report.schedule=schedules[entry.kind+"_"+entry.region]??null;
      const changed=await writer.write(report,createHash("sha256").update(raw).digest("hex"));
      cache[entry.path]=metadata.mtimeMs;if(changed)imported++;
    } catch(error) {
      errors++;const issue={kind:entry.kind,region:entry.region,detail:clean(error.message)};issues.push(issue);
      if(/Unsupported report identity|scope does not match|Invalid report.*times/.test(error.message))cache[entry.path]={mtime:metadata.mtimeMs,error:issue};
      console.error(JSON.stringify({operation:'publicationControlSync',...issue}));
    }
  }
  cache.$schedule=scheduleDigest;
  await writer.heartbeat(imported,errors,issues);
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
      const result=await synchronize({base,writer,cache,schedules:await readControlSchedules()});
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
  if(watchMode)setInterval(schedule,60000);
  await sync();
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(error=>{console.error(clean(error.message));process.exitCode=1;});
