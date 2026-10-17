import test from 'node:test';
import assert from 'node:assert/strict';
import {readNewsArticle} from './newsReadArticle.mjs';
const url='https://www.noen.at/region/aktuelle-meldung-a123';
const schema=(value)=>`<script type="application/ld+json">${JSON.stringify(value)}</script>`;
const primary={"@type":"NewsArticle",url:'/region/aktuelle-meldung-a123',headline:'Offene aktuelle Meldung',isAccessibleForFree:true,datePublished:'2026-10-16T23:30:00Z'};
const main='<main id="main-content"><h1>Offene aktuelle Meldung</h1><div class="article-body-text content-block"><div><span>Die tatsächlich angeforderte Nachricht.</span><div>Vollständiger weiterer Absatz.</div></div></div><article>Andere Meldung in einer Empfehlung</article></main>';
const fetchPage=(body)=>async()=>new Response(body);
test('NÖN reads primary body instead of the first related article and keeps Vienna publication evidence',async()=>{
 const result=await readNewsArticle(url,fetchPage(schema([primary,{...primary,url:'/andere',isAccessibleForFree:false,datePublished:'2001-01-01'}])+main));
 assert.match(result.text,/tatsächlich angeforderte Nachricht/);assert.match(result.text,/weiterer Absatz/);
 assert.doesNotMatch(result.text,/Empfehlung/);assert.equal(result.accessRestricted,false);
 assert.deepEqual(result.dateCandidates,['2026-10-17']);assert.equal(result.publicationDateEvidence[0].origin,'primary_article_jsonld');
});
test('a declared paid primary remains restricted even when an open related article exists',async()=>{
 const result=await readNewsArticle(url,fetchPage(schema([{...primary,isAccessibleForFree:false},{...primary,url:'/offen',isAccessibleForFree:true}])+main));
 assert.equal(result.accessRestricted,true);
});
test('missing or broken NÖN primary containers fail visibly instead of returning another story',async()=>{
 await assert.rejects(readNewsArticle(url,fetchPage('<main id="main-content"><article>Related only</article></main>')),/primary article body is missing/);
 await assert.rejects(readNewsArticle(url,fetchPage('<main id="main-content"><h1>Broken</h1><div class="article-body-text">Unclosed')),/container is incomplete/);
});
test('date-only primary publication metadata remains usable without inventing a source time',async()=>{
 const result=await readNewsArticle(url,fetchPage(schema({...primary,datePublished:'2026-10-17'})+main));
 assert.equal(result.publicationDateEvidence[0].value,'2026-10-17');assert.deepEqual(result.dateCandidates,['2026-10-17']);
});
