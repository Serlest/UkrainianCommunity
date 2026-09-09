# Fix80-14 handoff — App Lock availability

## Result

Implemented the confirmed passcode-only enable fix on `codex/uac-1.1-build80` from Build 79 (`fd58131`). No build, test, Simulator run, linter, install, commit, push, or deployment was performed.

The app now treats device-owner authentication availability separately from the biometric type. A device with a configured passcode and no enrolled Face ID or Touch ID can enable App Lock and reach the existing `.deviceOwnerAuthentication` prompt.

## Changed files

- `UkrainianCommunity/Services/Auth/AppLockService.swift`
- `UkrainianCommunity/Views/Profile/BiometricLockViews.swift`
- `Docs/Fix80-14-handoff.md`

`AppLockShield.swift`, `AuthState.swift`, `AuthService.swift`, `AuthViews.swift`, project configuration, routing, `AppStrings.swift`, and `Localizable.xcstrings` were not changed by this package.

The existing `removeAccountPreference(userID:)` hunk in `AppLockService.swift`, used by package 21 account cleanup, was preserved exactly.

## Covered

- Adds `AppLockAuthenticationAvailability` with independent `canAuthenticate` and `biometry` values.
- `DeviceLocalAuthentication` probes `.deviceOwnerAuthentication` for eligibility and probes biometric policy separately only to choose the Face ID or Touch ID presentation.
- Profile and registration toggles are disabled only when device-owner authentication itself is unavailable.
- Passcode-only devices no longer show the old biometric-unavailable warning.
- The locked screen uses a neutral shield symbol when no biometric type is available.
- Existing test fakes retain source compatibility through the protocol default: a fake with `.unavailable` remains unavailable unless it explicitly supplies a passcode-only availability.
- DEBUG scripted authentication accepts a `passcodeOnly` scenario for the coordinator's unified UI run.

## Already correct

- Authentication and unlock already evaluate `.deviceOwnerAuthentication`, so the OS can fall back to the device passcode.
- A temporary biometric lockout already retains passcode recovery.
- Enable and disable both require successful device-owner authentication.
- Cancellation, account changes, background transitions, and late results already use generation and user-ID guards.
- App Lock preferences remain local and account-scoped.
- Package 21 already connects successful account cleanup to `removeAccountPreference(userID:)`; this behavior remains present.

## Findings not changed

### Durable UserDefaults write

The earlier audit identified a theoretical write-confirmation gap, but no current reproducible UserDefaults failure was supplied or observed. A fallible storage abstraction would be a wider security-state refactor. It was intentionally not added to this package.

### Multiple scenes

The earlier audit identified shared `isInBackground` and `backgroundedAt` state as a possible multi-window conflict. No current two-scene reproduction exists in this branch, and the assigned change did not authorize a lifecycle redesign. `AppLockShield.swift` remains unchanged. Validate on iPad before deciding whether scene-counted or scene-scoped state is required.

## Coordinator-owned localization copy

No new key is required for compilation. To make the visible labels match passcode-only support, update these existing keys in `AppStrings.swift` and `Localizable.xcstrings`:

| Key | English | German | Ukrainian |
| --- | --- | --- | --- |
| `app_lock.registration_title` | Enable account protection | Kontoschutz aktivieren | Увімкнути захист акаунта |
| `app_lock.toggle_title` | Protect this account | Dieses Konto schützen | Захистити цей акаунт |
| `app_lock.unavailable` | Set a device passcode or Face ID / Touch ID in Settings, then allow access for the app. | Richten Sie in den Einstellungen einen Gerätecode oder Face ID / Touch ID ein und erlauben Sie anschließend den Zugriff für die App. | Налаштуйте в параметрах пристрою код пристрою або Face ID / Touch ID, а потім дозвольте доступ для застосунку. |

The existing help and locked-screen copy already mentions Face ID, Touch ID, or the device passcode.

## Unified validation scenarios

1. On a real iPhone with a device passcode and no enrolled biometrics, open Profile settings. The App Lock toggle is enabled, the old unavailable warning is absent, and enabling presents the OS device-passcode flow.
2. Repeat the passcode-only path during registration. Successful owner authentication creates the one-use authorization; cancellation leaves the option off and registration can continue.
3. On a device with neither passcode nor biometrics, both enable toggles remain disabled and the revised unavailable copy is visible.
4. With Face ID and Touch ID fixtures, confirm the matching icon remains visible and enable, lock, unlock, and disable still work.
5. Trigger biometric lockout and confirm App Lock remains available through device-passcode fallback.
6. Reject or cancel enable, unlock, and disable. State remains fail-closed and no preference changes on a rejected operation.
7. Run the DEBUG `passcodeOnly` UI fixture and assert `canAuthenticate == true`, `biometry == .unavailable`, enabled toggle, neutral shield icon, and successful scripted enable.
8. Compile existing `FakeLocalAuthentication` and `ReliableLocalAuthentication` conformers to verify the protocol default preserves compatibility.
9. Re-run account deletion/local purge coverage and confirm both App Lock enabled and grace keys are removed through package 21's preserved hunk.
10. On iPad, open two scenes and reproduce or dismiss the shared-lifecycle concern before any multi-scene refactor.

## Verification boundary

Implementation and the scoped diff were read manually. Per package constraints, all executable verification remains for the coordinator's unified run.
