# Fix80-15 — notification settings reliability

Baseline reviewed: `fd58131d2c7c7c5f50b5d354473b91d271990565` (Build 79).

## Implemented

- `ProfileViewModel` now scopes notification load, save, and test-push completions to the active notification user session. An auth reset or a load for another user invalidates late results before they can update visible state.
- Notification controls become interactive only after preferences for the current user have loaded. Initial load has an explicit progress state; load failure hides unverified defaults and exposes Retry.
- Preference persistence and local event-reminder reconciliation are separate outcomes. Once Firestore save succeeds, a later reconciliation failure no longer rolls the toggle back. The view model reads the persisted preferences back, keeps the durable value visible, and reports a localized partial-success error.
- Enabling push requests the iOS permission without starting APNs/FCM registration. After the preference write succeeds, the registration service is configured from the persisted setting. A failed preference write therefore cannot leave a newly enabled registration behind.
- The system permission/badge warning is shown only while the in-app push preference is enabled.
- The test action is disabled during a preference save and its completion is ignored after an account switch.
- `sendTestPushNotification` reads the existing user language fields and sends a Ukrainian, German, or English diagnostic body. Missing or unsupported locale retains the previous English copy.

## Files in this package

- `UkrainianCommunity/ViewModels/ProfileViewModel.swift`
- `UkrainianCommunity/Views/Profile/NotificationSettingsSectionView.swift`
- `UkrainianCommunity/Services/Notifications/NotificationPermissionService.swift`
- `UkrainianCommunity/Services/Notifications/RemoteNotificationRegistrationService.swift`
- `functions/src/notifications/inboxPushDelivery.ts`

`ProfileViewModel.swift` also contains unrelated changes from Fix80-21/Fix80-22; those hunks were preserved.

## Coordinator-owned localization integrated concurrently

The view-model/view implementation depends on these coordinator-owned `AppStrings.Profile` properties:

- `notificationPreferencesSyncFailed` → `profile.notifications.sync_failed`
- `notificationPreferencesLoading` → `profile.notifications.loading`

The coordinator also owns the plural variants for `profile.notifications.reminder.days`, including German singular `1 Tag` and Ukrainian one/few/many forms. This package did not edit `AppStrings.swift` or `Localizable.xcstrings`.

## Validation boundary

- Read the final targeted diff and ran `git diff --check` for the five implementation files; no whitespace errors.
- Per coordinator instruction, no tests, builds, Simulator, linters, install, commit, push, or deploy were run.
- Runtime account-switch, permission-grant, APNs/FCM, read-back failure, and reminder-reconciliation probes remain NOT VERIFIED until the coordinated validation phase.
- D15-08 (the shared Settings header/safe-area failure at Accessibility XXXL) is outside this package's notification-card ownership and remains unresolved here.

## Deployment note

The localized diagnostic push requires deploying the existing Cloud Function export `sendTestPushNotification`. No deployment was performed.
