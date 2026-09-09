# Fix80-16 handoff — Security settings

## Scope and reason

- Baseline: `fd58131` (Build 79).
- Section 16 showed a misleading email-verification result: every verification screen claimed that a message had been sent, including sign-in and restored sessions where no send request had succeeded.
- The fix records whether the current pending user actually completed a verification-email send. The UI keeps neutral pending copy until that fact is known.
- TOTP input also accepted any Unicode numeric characters as a six-digit code. Normalization and validation now permit only ASCII digits `0...9`, matching the backend code format.

## Changes

- `UkrainianCommunity/Services/Auth/AuthState.swift`
  - Adds `EmailVerificationNotice.pending` and `.emailSent`.
  - Starts every verification-pending session in the neutral state unless an explicit notice is supplied.
  - Records `.emailSent` only for the same pending user ID and clears the notice on other session transitions.
- `UkrainianCommunity/Services/Auth/AuthService.swift`
  - Marks the verification email as sent only after `sendVerificationEmail()` completes successfully and the auth transition is still current.
  - Existing package 21 account-deletion behavior in this shared file is preserved.
- `UkrainianCommunity/Views/Profile/AuthViews.swift`
  - Shows neutral “verification still pending” copy by default.
  - Shows “sent”, “sent to”, and spam-folder copy only after a successful initial send or resend.
  - Removes the view-appearance behavior that always asserted a successful send.
  - Existing account-deletion-completed handling from package 21 is preserved.
- `UkrainianCommunity/Services/Auth/AuthMultiFactorService.swift`
  - Restricts TOTP normalization and validation to ASCII digits without changing enrollment, refresh, or reauthentication behavior.
- `UkrainianCommunityTests/AuthSessionConsistencyTests.swift`
  - Adds source-level coverage for unverified sign-in, successful and failed registration sends, successful resend, and stale-user protection.
- `UkrainianCommunityTests/AuthSecurityTests.swift`
  - Adds Unicode-digit rejection coverage for TOTP normalization and validation.

## Dependencies and ownership

- Shared `AuthState` and `AuthService` edits were approved by the coordinator for this narrow verification-notice change.
- No routing, project configuration, `AppStrings`, or localization catalog changes were made; those remain coordinator-owned.
- The implementation reuses existing localized strings. No new UK/DE/EN keys are required.

## Existing localization keys used

| Key | English fallback | Ukrainian | German |
| --- | --- | --- | --- |
| `auth.email_verification.still_pending` | Verification is still pending. | Підтвердження ще не завершено. | Die Verifizierung ist noch ausstehend. |
| `auth.email_verification.description` | We sent a verification link. Check your inbox and open it to activate your account. | Ми надіслали лист із підтвердженням. Відкрийте посилання, щоб активувати обліковий запис. | Wir haben Ihnen eine Bestätigungsmail gesendet. Öffnen Sie den Link, um Ihr Konto zu aktivieren. |
| `auth.email_verification.sent` | Account created. Verification email sent. | Обліковий запис створено. Лист із підтвердженням надіслано. | Konto erstellt. Bestätigungs-E-Mail wurde gesendet. |
| `auth.email_verification.resent` | Verification email has been resent. | Посилання для підтвердження надіслано повторно. | Bestätigungs-E-Mail erneut gesendet. |
| `auth.email_verification.sent_to` | Sent to | Надіслано на | Gesendet an |
| `auth.email_verification.spam_hint` | Check your spam/junk folder if you do not see the message. | Якщо листа немає, перевірте також папку спаму/небажаних. | Falls Sie die Mail nicht finden, prüfen Sie bitte auch Ihren Spam-/Junk-Ordner. |

## Unified verification scenarios

1. Sign in with an existing unverified account. The screen shows the neutral pending message, the email address, and no claim that an email or account was just created. “Sent to” and the spam hint are hidden.
2. From that screen, complete a successful resend. The state changes to `.emailSent`; the UI shows the resend success, “Sent to”, and the spam hint.
3. Register a new account with a successful initial send. The screen may begin pending, then changes to the sent state only after the send completes.
4. Register a new account while the initial send fails. The Firebase session remains verification-pending, the resend-failed error appears, and no sent-only copy appears.
5. Fail a resend from a session that has never sent successfully. The error appears and the notice remains pending.
6. Switch pending users while an earlier send is completing. A completion for user A must not mark user B as sent.
7. Transition to guest, authenticated, restoring, authenticating, or unavailable session state. The verification notice is cleared.
8. Enter `12 34-56` as TOTP input. Normalization yields `123456` and validation accepts it. Fullwidth and Arabic-script digits are removed or rejected rather than treated as backend-compatible codes.
9. Recheck the package 21 account-deletion-completed sign-in message to confirm the shared-file merge remains intact.

## Verification status

- Implementation and scoped diff were read manually.
- `git diff --check` passes for the touched files.
- Per package constraints, no tests, build, Simulator run, linter, install, commit, push, or deployment was performed. The scenarios above belong in the coordinator’s unified validation run.
