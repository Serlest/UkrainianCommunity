# Android design audit — Build 83 candidate

Date: 2026-09-09  
Baseline: Android Build 82 / iOS Build 82  
Scope: Android presentation and navigation only. Shared Firebase collections, callable contracts,
authorization checks, moderation gates, and iOS sources are unchanged.

## Audit result

The reported visual problem was reproducible on the API 37 phone profile. It was not caused only by
an old handset. Four structural issues were responsible:

1. The full brand header and featured banner consumed too much vertical space outside Home.
2. Browse controls used two independent horizontal chip lists, so filters were partially hidden and
   looked clipped.
3. Content details presented title, media, prose, dates, participation, and links as a sequence of
   equally weighted cards. Important information had no clear priority.
4. The authenticated profile exposed more than twenty destinations as identical full-width outline
   buttons. Personal actions, privacy settings, moderation, owner tools, and deletion looked like one
   undifferentiated technical form.

The review covered the four primary destinations, news/event/organization lists and details, guest
and authenticated profile entry points, personal saved/subscription routes, communication/privacy
sections, and permission-gated administration destinations. The app contains more than fifty Compose
screen implementations; shared card and header changes deliberately propagate to the nested screens
without changing their state or authorization ownership.

## Implemented design system changes

- Home keeps the full UAC identity and featured hero. Secondary routes use a compact UAC app bar.
- Featured banners are shown only on the Home feed, never above event, organization, news details, or
  account screens.
- Cards now use Material 3 surface containers, 20 dp corners, low tonal elevation, and calmer spacing
  instead of repeated bright white elevated panels.
- Section headings use a compact title hierarchy rather than competing with the page title.
- A reusable Android settings/navigation row provides a consistent icon, title, optional explanation,
  chevron, 60 dp minimum row height, disabled state, and destructive state.
- Profile destinations are grouped into: My space, Communication, Activity, Administration, and
  Account. Existing test tags and route guards are retained.
- Inbox exposes unread state as supporting text instead of putting a counter into a generic button.

## Browse and filter changes

- Lists expose three primary controls: Region, Search, and Filters.
- Categories, event time scope, and audience selection moved into a scrollable Material bottom sheet.
- News period, ordering, source, and category are handled in one bottom sheet.
- The filter control shows the number of active filters.
- Saved items, registrations, and subscriptions remain available as explicit secondary links; they
  are no longer mixed with filtering choices.
- Interactive controls retain a 48 dp minimum target while the visible iconography remains compact.

## Detail changes

- Detail media is a consistent 16:9 hero with crop/fallback behavior appropriate to the content type.
- Organization details always reserve a meaningful visual area, even if no image URL is available.
- Event information now has a dedicated at-a-glance block for time, place, price, audience,
  organizer, and timezone context.
- Cancellation, sold-out, past-event, capacity, registration, contact, and additional-date states are
  visually separated instead of appearing as an unstructured paragraph.
- Unsafe nullable event dates are no longer force-unwrapped by the UI.

## Verification evidence

- Kotlin compilation: PASS.
- Local debug APK assembly/install/launch on API 37: PASS.
- JVM unit tests: PASS.
- Android lint for the local debug variant: PASS.
- Browse Compose journeys: 6/6 PASS on API 37.
- Main visual/accessibility journeys at system font scale 1.0: 2/2 PASS.
- Main visual/accessibility journeys at system font scale 2.0: 2/2 PASS.
- Guest/profile/content-cover/gallery/chrome selection: 10 PASS, 1 environment-gated skip. Two initial
  failures were runner configuration only and passed after the required font-scale argument was set.

## Internal testing publication

- Production-signed Android App Bundle: PASS.
- Google Play acceptance: PASS for version `1.1 (83)`.
- Internal track state: ACTIVE.
- Release: `1.1 (83) – Internal`.
- Play Console read-back: available to internal testers, published 2026-09-09 at 23:10 (Europe/Vienna).
- Device coverage: no supported devices were removed relative to the previous release.
- Tester opt-in URL: `https://play.google.com/apps/internaltest/4701365572505552935`.
- AAB SHA-256: `714398ac0da43e2f1b0d44e2049691e96b4948d0bd862c4d15c6d4a7c45824e4`.
- APK SHA-256: `620e41c6396dd0bedad1219f232f6e44856440a67a0f00c704f60f1ff65ac8b8`.

## Release boundary

Internal publication is complete. Physical-device approval is still NOT VERIFIED until Build 83 is
installed through Google Play on the target work phone and the redesigned German and Ukrainian flows
are reviewed. No open, closed, production, or public track was changed.
