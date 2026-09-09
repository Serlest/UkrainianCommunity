# Fix 80 — Package 13 handoff

## Scope

iOS Settings and Privacy consent reconciliation only, against base `fd58131d2c7c7c5f50b5d354473b91d271990565`. Android findings from audit 13 are deferred until after TestFlight acceptance and were not changed.

## Already fixed by package 28

Package 28 fully closed the primary D13-01 privacy defect. `ProfilePreferencesView` now consumes the initial and subsequent `collectionChanges()` signals and re-reads `analyticsService.isCollectionEnabled`. When `FirstPartyAnalyticsService` clears a locally enabled consent after `failedPrecondition`, `invalidArgument`, or `permissionDenied`, its existing delivery transition emits a change and the visible switch returns to the actual OFF state.

That observer was preserved as implemented. No owner-analytics screen, repository, model, counter, routing, legal, Android, or production behavior was rewritten.

## Covered in package 13

The existing collection-change stream is intentionally untyped. It cannot honestly distinguish a permanent consent rejection from an auth transition, external consent change, or ordinary state refresh. Package 13 therefore adds one narrow failure stream:

- `AnalyticsTracking.consentFailures()` defaults to an empty stream, preserving existing conformers.
- Every failure carries the opaque principal binding and exact consent generation. `isCurrentConsentFailure(_:)` rechecks both against the active account and latest opt-in attempt before UI presentation, so a queued rejection for account A or an older retry generation cannot appear for account B/new generation.
- `FirstPartyAnalyticsService` emits `.permanentRejection` only after the existing same-principal/same-consent guards and only for the three permanent callable codes that already revoke local consent.
- Transient network and unavailable failures remain silent; the local choice and fail-closed delivery behavior are unchanged.
- `ProfilePreferencesView` shows an inline error and retry only for this typed permanent-rejection signal. Retry creates a new explicit opt-in attempt through the existing `setCollectionEnabled(true)` path.
- The error is cleared by a new user choice and on principal change, so it cannot leak to another account.

## Changed files

- `UkrainianCommunity/Services/Analytics/AnalyticsTracking.swift`
- `UkrainianCommunity/Services/Analytics/FirstPartyAnalyticsService.swift`
- `UkrainianCommunity/Views/Profile/ProfileRootDestinationViews.swift`
- `Docs/Fix80-13-handoff.md`

`ProfileRootDestinationViews.swift` also contains a pre-existing package change to the donation subtitle; package 13 did not modify or claim it.

## Coordinator-owned dependency

Resolved during integration: coordinator added `AppStrings.Profile.analyticsConsentRejected` and the `profile.analytics_consent.rejected` EN/UK/DE catalog entry requested by package 13.

The supplied copy is:

- key: `profile.analytics_consent.rejected`
- UK: `Не вдалося підтвердити згоду на необов’язкову аналітику. Збір залишається вимкненим. Перевірте обліковий запис і спробуйте ще раз.`
- DE: `Die Einwilligung zur optionalen Analyse konnte nicht bestätigt werden. Die Erfassung bleibt deaktiviert. Prüfen Sie Ihr Konto und versuchen Sie es erneut.`

The retry button uses existing `AppStrings.Action.retry`. No outstanding project-file, routing, dependency, backend, Rules, localization, or Android change remains for package 13.

## Consolidated validation

1. Permanent callable rejection while Settings remains open: switch returns OFF, inline error and retry appear, collection scope stays nil.
2. Retry after the cause is resolved: a new consent generation is submitted; error clears; collection remains closed until exact server confirmation.
3. Transient failure: no permanent-error card appears, explicit local choice remains visible, collection scope stays nil.
4. Principal/auth change and external consent refresh: visible switch follows actual state without showing the permanent-rejection error; prior account error is cleared.
5. Existing analytics tracking conformers continue to compile through the protocol default implementation.

No test, build, Simulator, linter, install, commit, push, deployment, production access, or release action was performed in this package, as required.
