#!/usr/bin/env node
// Read-only discovery evidence. Hash equality does not establish legal currency.
import {writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';

const output = process.argv[process.argv.indexOf('--output') + 1];
if (!process.argv.includes('--output') || !output) throw new Error('Usage: --output NEW_JSON_FILE');
const groups = {
  residence: [
    ['protection-law', 'https://www.ris.bka.gv.at/GeltendeFassung.wxe?Abfrage=Bundesnormen&Gesetzesnummer=20011842'],
    ['rwr-law', 'https://www.ris.bka.gv.at/NormDokument.wxe?Abfrage=Bundesnormen&Gesetzesnummer=20004242&Paragraf=41a'],
    ['bmi-current', 'https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html'],
    ['bmi-rwr-faq', 'https://www.bmi.gv.at/ukraine/informationen_zum_umstieg_auf_eine_rot-_weiss_rot_karte_plus.html'],
    ['ma35-rwr', 'https://www.wien.gv.at/amtswege/rot-weiss-rot-karte-plus-vertriebene-ukraine'],
  ],
  benefits: [
    ['family-law', 'https://www.ris.bka.gv.at/NormDokument.wxe?Abfrage=Bundesnormen&Gesetzesnummer=10008220&Paragraf=3'],
    ['family-implementation', 'https://www.bundeskanzleramt.gv.at/agenda/familie/familienbeihilfe/familienbeihilfe-fuer-aus-der-ukraine-vertriebene.html'],
    ['basic-care', 'https://www.bbu.gv.at/ukraine-info-faq-deutsch'],
  ],
  healthInsurance: [
    ['asvg-law', 'https://www.ris.bka.gv.at/NormDokument.wxe?Abfrage=Bundesnormen&Gesetzesnummer=10008147&Paragraf=16'],
    ['insurance-implementation', 'https://www.oegk.at/cdscontent/?contentid=10007.884366'],
  ],
};
const sources = await Promise.all(Object.entries(groups).flatMap(([group, entries]) => entries.map(async ([id, url]) => {
  const observedAt = new Date().toISOString();
  try {
    const response = await fetch(url, {signal: AbortSignal.timeout(20000)});
    const html = await response.text();
    return {group, id, url, finalURL: response.url, observedAt, status: response.status,
      bytes: Buffer.byteLength(html), sha256: createHash('sha256').update(html).digest('hex'),
      // Retain the exact response so editorial review can distinguish content from shells.
      html, editorialStatus: 'unreviewed', requiresSubstantiveReview: true};
  } catch (error) {
    return {group, id, url, observedAt, error: String(error), editorialStatus: 'unavailable'};
  }
})));
const report = {schemaVersion: 1, capturedAt: new Date().toISOString(),
  coverage: 'partial_until_editorial_review', sources,
  requiredReviewGroups: Object.keys(groups),
  warning: 'Collector only. Review actual text, legal dates, exceptions, authority conflicts and production blocks. Search new official URLs over a rolling 14-day overlap separately.'};
writeFileSync(output, JSON.stringify(report, null, 2), {flag: 'wx'});
console.log(JSON.stringify({output, sourceCount: sources.length,
  unavailable: sources.filter(s => s.error || s.status !== 200).map(s => s.id),
  editorialReviewComplete: false}));
