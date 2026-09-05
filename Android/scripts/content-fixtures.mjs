import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { doc, setDoc, getDoc, collection, query, where, orderBy, documentId, limit, startAfter, getDocs, or, Timestamp } = require('firebase/firestore');
const { assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
export async function checkContentFixtures(env) {
  if (process.env.FIRESTORE_EMULATOR_HOST !== '127.0.0.1:8088') throw Error('Local emulator only');
  const fixtures = JSON.parse(readFileSync(new URL('../app/src/main/assets/content-fixtures.json', import.meta.url), 'utf8'));
  function convert(value) {
    if (value?.$date) {
      const millis = Date.parse(value.$date);
      const fraction = value.$date.match(/\.(\d+)Z$/)?.[1] ?? '';
      return new Timestamp(Math.floor(millis / 1000), Number(fraction.padEnd(9, '0')));
    }
    if (Array.isArray(value)) return value.map(convert);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, convert(item)]));
    return value;
  }
  await env.withSecurityRulesDisabled(async context => {
    for (const [path, value] of Object.entries(fixtures)) {
      if (!path.includes('/synthetic-') && path !== 'appConfig/donation') throw Error('Non-synthetic path');
      await setDoc(doc(context.firestore(), path), convert(value));
    }
  });
  const guest = env.unauthenticatedContext().firestore();
  let passed = 0;
  for (const kind of ['news', 'events', 'organizations']) {
    const constraints = [where('moderationStatus', '==', 'approved')];
    if (kind !== 'organizations') constraints.push(where('sourceType', '==', 'organization'));
    if (kind === 'events') constraints.push(where('endDate', '>=', new Date()));
    const field = kind === 'events' ? 'endDate' : kind === 'news' ? 'publishedAt' : 'createdAt';
    const direction = kind === 'events' ? 'asc' : 'desc';
    const ref = query(collection(guest, kind), ...constraints, orderBy(field, direction), orderBy(documentId(), direction), limit(6));
    const first = await assertSucceeds(getDocs(ref)); passed++;
    assert.equal(first.size, 6); passed++;
    const last = first.docs.at(-1);
    const next = await assertSucceeds(getDocs(query(ref, startAfter(last.get(field), last.id)))); passed++;
    assert(!next.docs.some(row => first.docs.some(before => before.id === row.id))); passed++;
    const regional = await assertSucceeds(getDocs(query(ref, or(where('regionScope', '==', 'austria'), where('federalState', '==', 'wien'))))); passed++;
    assert(regional.docs.every(row => row.get('regionScope') === 'austria' || row.get('federalState') === 'wien')); passed++;
  }
  for (const path of ['news/synthetic-news-01', 'events/synthetic-event-01', 'organizations/synthetic-org-01',
    'organizations/synthetic-org-01/photos/synthetic-photo', 'publicProfiles/synthetic-public-owner', 'appConfig/donation']) {
    await assertSucceeds(getDoc(doc(guest, path))); passed++;
  }
  await assertFails(getDoc(doc(guest, 'news/synthetic-news-private'))); passed++;
  await assertFails(getDoc(doc(guest, 'users/synthetic-public-owner'))); passed++;
  for (const section of ['home', 'events', 'organizations']) {
    const banners = await assertSucceeds(getDocs(query(collection(guest, 'featuredBanners'), where('isActive', '==', true),
      where('actionType', 'in', ['none', 'news', 'event', 'organization', 'externalURL']), where('visibleSections', 'array-contains', section)))); passed++;
    assert(!banners.docs.some(row => row.get('actionType') === 'guide')); passed++;
  }
  const exact = await getDoc(doc(guest, 'news/synthetic-news-01'));
  assert.equal(exact.get('publishedAt').nanoseconds, 123456000); passed++;
  console.log(`PASS: ${passed} package-2 public query/region/cursor/detail/banner/negative assertions; ${Object.keys(fixtures).length} synthetic fixtures.`);
}
