# App Review notes

## Ready-to-use notes

UAC (UkrainianCommunity) is a German/Ukrainian community app for people in Austria.
The app opens with sign-in or account creation. An account is required to use
the content sections and account features. Email/password, Sign in with Apple,
Google sign-in and passkeys are available. Passkeys are optional for ordinary
verified accounts. Owner and administrator access has additional protection.

On the first sign-in with the review account, the app presents the current Terms
of Use and Privacy Policy for acceptance. Material updates require a fresh
review and acceptance before app access; declining signs the user out. This is
the same gate shown to every account; no administrator approval is required.
The review account is email-verified and has the ordinary user role.

The registration form requires selection of an Austrian federal state and
confirmation that the user is at least 14. The technical age confirmation is
self-declared; it is not document-based identity or age verification.

Optional first-party content analytics is off by default. Users can choose it
separately during registration and change their choice in Profile settings.
Banner impression and click measurement requires another, separate voluntary
consent that can be withdrawn in Settings. The owner sees aggregate counts, not
per-user reports. Neither choice controls essential account-feature records or
all Firebase technical diagnostics. No advertising SDK, IDFA or cross-app
advertising tracking is used.

Optional Face ID / Touch ID locks an existing signed-in session on the device,
with device-passcode fallback. Passkeys can use Face ID, Touch ID or the device
passcode. The session lock is separate from Sign in with Apple; registration
does not require biometrics.

User content can be reported from its action menu. Users can block other users
and manage their block list in Profile. Administrators moderate reports and
organizations. A public illegal-content reporting portal is also available:
https://ukrainiancommunity-dbd5f.web.app/report-illegal-content

New comments are created through a server-side moderation endpoint. It rejects
clear threats, hateful slurs, child sexual exploitation terms and link-flooding
before publication. Rejected text is not stored. Published comments can still be
reported, and authorized moderators can remove them.

Profile may show a voluntary project-support card configured by the platform
owner. Its button opens a clearly identified external HTTPS website in Safari.
There are no digital goods, subscriptions, paid features, rewards, account
privileges or moderation advantages associated with a contribution.

Account deletion can be initiated in Profile > Settings > Delete account. Please
use the dedicated ordinary review account for destructive tests; do not use a
platform owner or administrator account. Credentials are supplied in the
dedicated App Review sign-in fields, not in these notes or the repository.

Support: https://ukrainiancommunity-dbd5f.web.app/support
Privacy: https://ukrainiancommunity-dbd5f.web.app/privacy

## Release-specific instruction: 1.3 (154)

The operator explicitly requested public submission and automatic release after approval on 2026-10-29. The 1.3 draft therefore uses AFTER_APPROVAL. This is a specific authorized exception to the default manual-release checklist below. The existing dedicated ordinary review account was verified for password authentication and role before this submission; no owner credentials were substituted. Seasonal scenes are cosmetic and user-disableable, and standard screenshots disable them only locally.

## Internal checklist before submission

- Re-test the dedicated review account on the selected release build. Never
  provide the real owner's credentials.
- Confirm the exact localized navigation labels for deletion and blocking on
  the selected build.
- Verify the production comment endpoint and Rules with the selected build.
- Choose the final tested build and upload real screenshots for each supported
  required device family and localization.
- Keep release mode MANUAL. Adding notes is not authorization to submit.
