import test from "node:test";
import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {mkdtemp, writeFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {buildNewsAmendment, amendPublishedNews} from "./newsAmendPublished.mjs";
import {buildContentDocument, normalizeAndValidateManifestItem} from "./verifiedContentPublisherCore.mjs";

const now = new Date("2026-10-16T16:25:00Z");
const url = "https://www.unsereoebb.at/de/verkehrsmeldungen~test~";
const old = {kind: "news", state: "approved", missingFields: [], regionScope: "federalState", federalState: "niederoesterreich", category: "transport", city: "Stockerau",
  title: "Рух поїздів тимчасово припинено", subtitle: "ÖBB повідомляє про обмеження руху.",
  body: "Між Stockerau та Hausleiten тимчасово припинено рух поїздів. Перед поїздкою перевірте актуальне сполучення в офіційному планувальнику ÖBB SCOTTY. Точний час відновлення руху ще не повідомлено; стежте за оновленнями оператора.",
  deTitle: "Zugverkehr vorübergehend unterbrochen", deSubtitle: "ÖBB meldet eine Unterbrechung.",
  deBody: "Zwischen Stockerau und Hausleiten ist der Zugverkehr vorübergehend unterbrochen. Prüfen Sie vor der Fahrt Ihre Verbindung im offiziellen ÖBB-Routenplaner SCOTTY. Ein genauer Zeitpunkt der Wiederaufnahme ist noch nicht bekannt. Beachten Sie die Aktualisierungen des Betreibers.",
  publishedAt: "2026-10-16T15:00:00Z", imagePath: "/tmp/cover.png", imageCredit: "KI-Symbolbild", imageAlternativeText: "Bahnsteig",
  sources: [{url, title: "ÖBB", isPrimary: true, verificationRole: "officialPrimary"}]};
const next = {...old, title: "Обмеження руху поїздів завершилося", deTitle: "Zugverkehrsunterbrechung beendet", publishedAt: now.toISOString(),
  body: old.body + " Обмеження завершилося о 18:01 за повідомленням ÖBB.", deBody: old.deBody + " Die Unterbrechung endete laut ÖBB um 18:01 Uhr."};
function record(raw = old) {
  return buildContentDocument(normalizeAndValidateManifestItem(raw, "niederoesterreich"), {name: "UAC", logoURL: "https://example.at/logo.jpg"}, "uac-niederoesterreich-info", "https://example.at/cover.jpg", now);
}
test("amendment only patches bilingual text and UAC timestamps, preserving identity, cover and counters", () => {
  const before = {...record(), likeCount: 43};
  const plan = buildNewsAmendment(before, old, next, "uac-niederoesterreich-info", now);
  assert.deepEqual(Object.keys(plan.fields), ["title", "subtitle", "summary", "body", "localizations", "publishedAt", "updatedAt"]);
  assert.equal(before.likeCount, 43);
  assert.equal(plan.fields.localizations.de.title, next.deTitle);
});
test("wrong owner, changed baseline, source, scope and cover cannot be amended", () => {
  for (const before of [{...record(), authorId: "other"}, {...record(), body: "concurrently changed"}, {...record(), moderationStatus: "pending"}]) {
    assert.throws(() => buildNewsAmendment(before, old, next, "uac-niederoesterreich-info", now));
  }
  for (const change of [{city: "Wien"}, {imagePath: "/tmp/other.png"}, {sources: [{url: "https://www.unsereoebb.at/de/other", title: "ÖBB", isPrimary: true, verificationRole: "officialPrimary"}]}]) {
    assert.throws(() => buildNewsAmendment(record(), old, {...next, ...change}, "uac-niederoesterreich-info", now), /cannot change/);
  }
});
const encoded = (v) => v instanceof Date ? {timestampValue: v.toISOString()} : typeof v === "string" ? {stringValue: v} : typeof v === "number" ? {integerValue: String(v)} : v === null ? {nullValue: null} : Array.isArray(v) ? {arrayValue: {values: v.map(encoded)}} : {mapValue: {fields: Object.fromEntries(Object.entries(v).map(([k,x]) => [k, encoded(x)]))}};
async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), "uac-amend-")); t.after(() => rm(dir, {recursive: true, force: true}));
  const imagePath = join(dir, "cover.png"); await writeFile(imagePath, "image");
  const a = {...old, imagePath}, b = {...next, imagePath};
  const review = {scope: "niederoesterreich", evidenceMode: "official", sourceEventDate: "2026-10-16", sourceEventKind: "material_update", materialChange: "The operator now confirms that the active train suspension ended at18:01.", primaryURL: url, primaryCheckedAt: now.toISOString(), primaryOpened: true, primaryPageKind: "article_or_notice", officialAuthorityConfirmed: true,
    practicalEffect: "The previously published train suspension has ended; passengers need the corrected current status.", territoryEvidence: "Both stations are within Niederösterreich.", affectedPeople: "Passengers using Stockerau–Hausleiten.", readerAction: "Check current service in the official SCOTTY planner.", ukDeFactParityConfirmed: true, originalTextConfirmed: true, excludedTopicsAbsent: true,
    image: {tool: "image_gen", generatedForURL: url, generatedAt: now.toISOString(), prompt: "Photorealistic thematic empty Austrian rail platform, no incident detail or logos", sha256: createHash("sha256").update("image").digest("hex"), photorealisticReviewed: true, topicMatchReviewed: true, sourceImageCopied: false}};
  review.image.generatedAt = "2026-10-10T12:00:00Z"; // Existing reviewed cover may be older than the material update.
  const config = {baselineManifestPath: join(dir, "old.json"), baselineReviewPath: join(dir, "old-review.json"), manifestPath: join(dir, "new.json"), reviewPath: join(dir, "review.json"), planPath: join(dir, "plan.json"), organizationId: "uac-niederoesterreich-info", runId: "test-run", threadId: "test-thread"};
  await Promise.all([[config.baselineManifestPath,a],[config.baselineReviewPath,review],[config.manifestPath,b],[config.reviewPath,review]].map(([p,d])=>writeFile(p,JSON.stringify(d))));
  return {config, record: {updateTime: "2026-10-16T15:00:00Z", fields: Object.fromEntries(Object.entries(record(a)).map(([k,v])=>[k,encoded(v)]))}};
}
test("live amendment requires matching dry-run, locks and Firestore updateTime precondition", async (t) => {
  const f = await fixture(t); let locked = false; const writes = [];
  const deps = {now, getAccessToken: async()=>"test", checkLocks: async()=>{locked=true;}, convertCover: async()=>({bytes:Buffer.from("image")}), readback: async()=>({allVerified:true,coverSHA256:createHash("sha256").update("image").digest("hex")}), fetchImpl: async(u,o)=>{if(o.method==="PATCH") {writes.push({url:String(u),body:JSON.parse(o.body)}); return Response.json({updateTime:"new"});}return Response.json(f.record);}};
  await assert.rejects(amendPublishedNews(f.config,{...deps,apply:true}));
  const dry = await amendPublishedNews(f.config,deps); assert.equal(dry.dryRun,true); assert.equal(writes.length,0);
  await amendPublishedNews(f.config,{...deps,apply:true});assert.equal(locked,true);assert.equal(writes.length,1);
  const u=new URL(writes[0].url);assert.equal(u.searchParams.get("currentDocument.updateTime"),f.record.updateTime);
  assert.equal(u.searchParams.getAll("updateMask.fieldPaths").includes("imageURL"),false);
  assert.equal(writes[0].body.fields.localizations.mapValue.fields.de.mapValue.fields.title.stringValue,next.deTitle);
});
test("concurrent edit or lock rejection stops live write", async(t)=>{
  const f=await fixture(t);let writes=0;
  const deps={now,getAccessToken:async()=>"test",convertCover:async()=>({bytes:Buffer.from("image")}),readback:async()=>({allVerified:true,coverSHA256:createHash("sha256").update("image").digest("hex")}),fetchImpl:async(u,o)=>{if(o.method==="PATCH")writes++;return Response.json(f.record);}};
  await amendPublishedNews(f.config,deps);
  await assert.rejects(amendPublishedNews(f.config,{...deps,apply:true,checkLocks:async()=>{throw new Error("foreign lock");}}),/foreign lock/);
  f.record.updateTime="2026-10-16T16:20:00Z";
  await assert.rejects(amendPublishedNews(f.config,{...deps,apply:true,checkLocks:async()=>{}}),/Dry-run\/production changed/);
  assert.equal(writes,0);
});
