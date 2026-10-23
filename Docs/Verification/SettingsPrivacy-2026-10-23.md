# Settings and privacy verification — 2026-10-23

## Scope

iOS Profile → Settings and privacy, including notification scheduling, consent state, account-security operations and nested routes. No backend deployment, TestFlight upload or public release.

## Changes

- Cancel disabled local reminders without reading events. For enabled schedules, read registrations and eligible events without likes/bookmarks enrichment; reject results from a previous account.
- Fence MFA state, linked-provider responses and passkey operations to the account that initiated them. Reset security views when the account changes.
- Keep banner-consent read errors visible and retryable. Coalesce reads, bound callable waits, reject stale responses including account A → B → A, and persist pending withdrawal for retry before reading consent again.
- Group appearance, privacy/consents, notifications, account security, biometric protection, hidden content and legal settings separately. Improve large-text layout and dark-mode control contrast.
- Isolate simulator fixtures from production notification registration. Keep existing consent defaults and production authorization requirements.

## Evidence

Artifacts are local, ignored by Git: `build/settings-privacy-fix-20261023/`.

- Simulator build succeeded. Existing unrelated warnings: SystemLogDeliveryQueue captured self and DirectoryEditorAccessStore isolated decoding.
- `SettingsUnitIsolated.xcresult`: 30 tests passed across SettingsPrivacyReliabilityTests, ProfileEditingTests, AccountProviderLinkServiceTests and AuthSecurityTests.
- `SettingsUI.xcresult`: 3 UI scenarios passed: owner nested routes/deletion restriction; consent failure/retry/enable, notification persistence and language/theme after relaunch; ordinary-account German dark mode with accessibility text and nested security/hidden-content routes.
- `SettingsFinal.xcresult`: final rebuild and rerun passed all 12 reliability tests plus the German accessibility UI scenario (13 passed, zero failed/skipped). Includes the added compatibility regression: a model without an event source preserves enabled reminder schedules. Final control tint changes were included in this run.
- Initial unit harness crashed because a mock graph initialized production Firebase push registration without a configured Firebase app. Production registration remains the default; injected no-op registration in mock graphs resolved the crash, and the subsequent suite passed.
- Localization validation: 3268 entries, Ukrainian and German; localization-table validator: 3 tests passed. Repository structure, property lists, release configuration (build 115) and whitespace checks passed.

## Boundaries

UI persistence/error scenarios use deterministic simulator repositories. Live Face ID, APNs receipt, password reset, provider linking, passkey enrollment/removal and destructive account deletion were not executed against real accounts. Existing application/server contracts remain in place. New source changes require a subsequent build for device delivery.
