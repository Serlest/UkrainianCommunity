// Deterministic, invented public documents. Never import real users or content.
import { writeFileSync, mkdirSync } from 'node:fs';
const date = value => ({ $date: value });
const out = {};
// Firestore stores microseconds; local fixtures use the same persisted precision.
const stamp = '2026-09-02T10:00:00.123456Z';
const base = { moderationStatus: 'approved', sourceType: 'organization', createdAt: date(stamp),
  updatedAt: date(stamp), publishedAt: date(stamp), regionScope: 'austria', city: 'Wien',
  organizationId: 'synthetic-org-01', organizationName: 'Beispielverein / Вигадана спільнота',
  imageURL: 'https://example.invalid/media/community.png', mediaMetadata: { alternativeText: 'UAC · Demo', caption: 'Synthetisches Motiv / Вигадана ілюстрація', credit: 'UAC local test' } };
for (let i = 1; i <= 18; i++) {
  const n = String(i).padStart(2, '0');
  const region = i % 3 === 0 ? { regionScope: 'federalState', federalState: 'tirol', city: 'Innsbruck' }
    : i % 3 === 1 ? { regionScope: 'federalState', federalState: 'wien', city: 'Wien' } : {};
  const bodyDE = `Dies ist der frei erfundene Beispieltext ${n}. Keine echten Angebote oder Termine. ` +
    (i === 1 ? 'Lange Texte bleiben vollständig lesbar, auch bei großer Schrift.\n\n'.repeat(7) : 'Informationen für die lokale Prüfung.');
  const bodyUK = `Це повністю вигаданий приклад ${n}. Тут немає справжніх пропозицій чи зустрічей. ` +
    (i === 1 ? 'Довгий текст залишається доступним навіть із великим шрифтом.\n\n'.repeat(7) : 'Матеріал для локальної перевірки.');
  out[`news/synthetic-news-${n}`] = { ...base, ...region, title: `Beispielnachricht ${n}`, summary: 'Gemeinschaft vor Ort', body: bodyDE,
    category: i % 2 ? 'communityAndIntegration' : 'education', additionalCategories: ['culture'], tags: ['demo', i === 1 ? 'Suchziel' : 'lokal'],
    localizations: { ...(i === 5 ? {} : { de: { title: `Beispielnachricht ${n}`, subtitle: 'Gemeinschaft vor Ort', body: bodyDE } }),
      uk: { title: `Тестова новина ${n}`, subtitle: 'Спільнота поруч', body: bodyUK } },
    sourceName: 'Lokale Testredaktion', sourceURL: 'https://example.invalid/source',
    externalAction: { title: 'Demo', url: 'https://example.invalid/demo' } };
  out[`events/synthetic-event-${n}`] = { ...base, ...region, title: `Beispieltreffen ${n}`, summary: 'Erfundener Termin', details: bodyDE,
    startDate: date(i > 14 ? '2026-01-01T10:00:00Z' : `2030-09-${n}T10:00:00Z`),
    endDate: date(i > 14 ? '2026-01-01T12:00:00Z' : `2030-09-${n}T12:00:00Z`),
    occurrences: [{ id: `occurrence-${n}`, startDate: date('2030-10-27T00:30:00Z'), endDate: date('2030-10-27T02:30:00Z'), isAllDay: i === 2, status: i === 3 ? 'cancelled' : 'scheduled' }],
    category: i % 2 ? 'meetups' : 'education', audience: i % 2 ? 'everyone' : 'families',
    cancellationState: i === 3 ? 'cancelled' : 'active', participationMode: i === 4 ? 'externalTickets' : 'inAppRegistration',
    capacity: 10, registeredCount: i === 2 ? 10 : 2, pricing: { kind: i % 2 ? 'free' : 'range', amount: 5, maximumAmount: 12, currencyCode: 'EUR' },
    venue: 'Erfundener Begegnungsraum', address: 'Testadresse, kein Veranstaltungsort', organizerName: 'Beispielverein',
    contactEmail: 'demo@example.invalid', contactPhone: '+430000000',
    externalAction: { title: 'Demo Tickets', url: 'https://example.invalid/tickets' },
    localizations: { de: { title: `Beispieltreffen ${n}`, summary: 'Erfundener Termin', details: bodyDE },
      uk: { title: `Тестова зустріч ${n}`, summary: 'Вигадана подія', details: bodyUK } } };
  out[`organizations/synthetic-org-${n}`] = { ...base, ...region, name: `Beispielverein ${n}`, description: bodyDE,
    shortDescription: 'Erfundene Organisation', fullDescription: bodyDE, logoURL: base.imageURL, coverURL: base.imageURL,
    ownerId: 'synthetic-public-owner', adminIds: [], moderatorIds: ['synthetic-public-helper'], subscriberCount: 7,
    missionStatement: 'Gemeinsam lernen und helfen.', languages: ['uk', 'de'], foundedYear: 2020,
    website: 'https://example.invalid/community', contactEmail: 'demo@example.invalid', phone: '+430000000', address: 'Testadresse',
    donationURL: 'https://example.invalid/support', telegramURL: 'https://example.invalid/telegram',
    directoryProfile: { profileKind: ['community', 'business', 'restaurant', 'specialist', 'institution', 'mediaProject'][(i - 1) % 6],
      serviceModes: ['online', 'onSite'], serviceArea: 'Österreich', regularHours: { monday: '09:00-17:00', sunday: 'closed' },
      specialHoursNote: 'Keine echten Öffnungszeiten', services: ['Beratung', 'Sprachcafé'],
      bookingURL: 'https://example.invalid/booking', currentOfferTitle: 'Lokales Testangebot', currentOfferDetails: 'Nur eine Demonstration',
      currentOfferURL: 'https://example.invalid/offer', currentOfferValidUntil: date('2031-01-01T00:00:00Z') },
    localizations: { de: { name: `Beispielverein ${n}`, shortDescription: 'Erfundene Organisation', fullDescription: bodyDE },
      uk: { name: `Тестова організація ${n}`, shortDescription: 'Вигадана організація', fullDescription: bodyUK,
        missionStatement: 'Навчаємось та допомагаємо разом.', services: ['Консультації', 'Мовна зустріч'],
        specialHoursNote: 'Години роботи вигадані', currentOfferTitle: 'Тестова пропозиція', currentOfferDetails: 'Лише демонстрація' } } };
  out[`organizations/synthetic-org-${n}/photos/synthetic-photo`] = { imageURL: base.imageURL, uploadedBy: 'synthetic-public-owner',
    createdAt: date(stamp), caption: 'Demo · Приклад' };
}
out['publicProfiles/synthetic-public-owner'] = { displayName: 'Demo · Олена', city: 'Wien', avatarURL: base.imageURL, updatedAt: date(stamp) };
out['publicProfiles/synthetic-public-helper'] = { displayName: 'Demo · Андрій', city: 'Wien', updatedAt: date(stamp) };
for (const [id, action, extra] of [
  ['welcome', 'news', { actionTargetID: 'synthetic-news-01', priority: 30 }],
  ['event', 'event', { actionTargetID: 'synthetic-event-01', priority: 20 }],
  ['community', 'organization', { actionTargetID: 'synthetic-org-01', priority: 10 }],
  ['expired', 'none', { endsAt: date('2020-01-01T00:00:00Z') }],
  ['future', 'none', { startsAt: date('2099-01-01T00:00:00Z') }],
  ['legacy', 'guide', {}], ['tirol', 'none', { regionScope: 'federalState', federalState: 'tirol' }],
]) out[`featuredBanners/synthetic-banner-${id}`] = { id: `synthetic-banner-${id}`, createdBy: 'synthetic-owner', title: `Demo ${id}`, subtitle: 'Lokales Beispiel',
  localizations: { de: { title: 'Gemeinsam in Österreich', subtitle: 'Entdecke die lokalen Beispiele' },
    uk: { title: 'Разом в Австрії', subtitle: 'Перегляньте локальні приклади' } }, imageURL: base.imageURL,
  isActive: true, actionType: action, regionScope: 'allAustria', visibleSections: ['home', 'events', 'organizations'],
  displayDurationSeconds: 6, priority: 0, createdAt: date(stamp), updatedAt: date(stamp), ...extra };
out['appConfig/donation'] = { isEnabled: true, donationURL: 'https://example.invalid/donation',
  titleDE: 'Projekt unterstützen · Demo', titleUK: 'Підтримати проєкт · демо',
  messageDE: 'Testansicht. Hier wird kein Geld gesammelt.', messageUK: 'Тестовий екран. Тут не збирають кошти.',
  buttonTitleDE: 'Demo-Link', buttonTitleUK: 'Демо-посилання' };
out['news/synthetic-news-private'] = { ...base, moderationStatus: 'pendingReview', title: 'Private fixture', body: 'Denied' };
out['news/synthetic-news-malformed'] = { ...base, title: 123, body: 'Invalid fixture' };
const target = new URL('../app/src/main/assets/', import.meta.url);
mkdirSync(target, { recursive: true });
writeFileSync(new URL('content-fixtures.json', target), JSON.stringify(out, null, 2) + '\n');
console.log(`Generated ${Object.keys(out).length} invented documents; no production input.`);
