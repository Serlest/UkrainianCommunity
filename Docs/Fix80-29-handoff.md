# Fix 80 — Package 29 handoff

## Scope

iOS donation settings and the public Profile support destination. Baseline checked at `fd58131d2c7c7c5f50b5d354473b91d271990565`.

## Product changes

1. A successful donation-config write is now committed to the local model before verification read.
   - A failed or empty post-write read no longer reports that the write failed.
   - The saved normalized config remains visible and the method returns success.
   - The form adopts the final ViewModel config after success, so server metadata cannot leave Save or the dirty-back guard active.
   - The owner sees a distinct informational message explaining that saving succeeded but refresh did not.
   - A real repository write failure still uses the existing error state and keeps the edited draft.

2. URL validation guidance is visible whenever the current draft is invalid.
   - Enabling support without a URL immediately explains why Save is disabled.
   - A nonempty URL rejected by the existing client policy immediately shows the existing invalid-URL message.

3. Back protects an edited donation draft.
   - The screen supplies a feature-owned back action to `PushedScreenShell`.
   - An unchanged form dismisses immediately.
   - A changed form presents a destructive discard confirmation; Cancel preserves the form.

4. The public support message is no longer duplicated.
   - The pushed header uses the stable public-section subtitle.
   - The owner-configured message remains once inside `ProfileDonationSupportCard`.
   - Together with the coordinator-provided accessibility scrolling behavior in `PushedScreenShell`, this removes the long configurable message from the fixed header path.

## Changed files

- `UkrainianCommunity/ViewModels/DonationConfigViewModel.swift`
- `UkrainianCommunity/Views/Profile/DonationSettingsView.swift`
- `UkrainianCommunity/Views/Profile/ProfileRootDestinationViews.swift` — only the `ProfileProjectSupportView` subtitle line belongs to package 29; the analytics-consent diff in the same file belongs to package 28.

`FirestoreDonationConfigRepository.swift` and `ProfileViews.swift` were reviewed but did not require product changes for this package.

## Coordinator-owned localization additions

The feature currently follows the existing `DonationLocalization` UK/DE literals so this package does not edit `AppStrings.swift` or `Localizable.xcstrings`. Suggested keys and final text for coordinator migration:

| Key | English | Ukrainian | German |
|---|---|---|---|
| `profile.donation.settings.save_refresh_failed` | Changes were saved, but the data could not be refreshed. Try again later. | Зміни збережено, але оновити дані не вдалося. Спробуйте ще раз пізніше. | Die Änderungen wurden gespeichert, aber die Daten konnten nicht aktualisiert werden. Versuchen Sie es später erneut. |
| `profile.donation.settings.discard.title` | Discard unsaved changes? | Відхилити незбережені зміни? | Ungespeicherte Änderungen verwerfen? |
| `profile.donation.settings.discard.message` | Changes to the support settings will be lost. | Зміни налаштувань підтримки буде втрачено. | Die Änderungen an den Unterstützungseinstellungen gehen verloren. |
| `profile.donation.settings.discard.action` | Discard changes | Відхилити зміни | Änderungen verwerfen |

Suggested `AppStrings` accessors may live under a coordinator-selected donation/profile namespace. After adding them, replace the four new `DonationLocalization` methods with those accessors or have those methods delegate to them.

## Self-review

- Read the complete feature diff after edits.
- Confirmed the post-write read is still bounded by `RefreshRequest`; no write is retried.
- Confirmed failed refresh retains the just-saved local config rather than replacing it with defaults or stale data.
- Confirmed dirty detection uses the same normalized representation as Save.
- Confirmed normal Back remains one tap when the form is unchanged.
- Confirmed the public configurable message remains visible exactly once in the card.
- Preserved package 28 changes already present in `ProfileRootDestinationViews.swift`.

## Coordinator validation

- Repository fake: write succeeds, verification fetch fails or returns `nil` → `save` returns `true`, local config equals normalized submitted config, informational refresh message appears.
- Repository fake: write fails → `save` returns `false`, existing save error appears, draft stays edited.
- Owner UI: enable with empty URL and enter rejected URL → inline reason is visible while Save remains disabled.
- Owner UI: edit any field → Back presents confirmation; Cancel retains edits; Discard closes; unchanged Back closes directly.
- Public support page: header uses the stable section subtitle and configurable message appears once in the card.
- Repeat UK/DE Accessibility XXXL using the shared shell fix and verify URL, both language sections and Save are reachable.

No build, tests, Simulator, linter, dependency installation, commit, push, deployment, backend change, production access, real config write, external browser action or payment was performed, as required by the coordinator.
