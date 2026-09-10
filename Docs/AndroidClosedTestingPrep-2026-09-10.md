# Android closed-testing preparation — 2026-09-10

## Confirmed scope

- Prepare Google Play closed testing and its tester link.
- Do not create or submit a production release.
- Publish shared iOS/Android privacy, support, and account-deletion pages without forcing existing iOS users to accept a new policy.
- Use conservative, code-backed Play declarations: no ads, no sale of data, no advertising tracking, encrypted transport, Firebase as processor.

## Completed and verified

- Firestore privacy policy `2026.14` is active with `requiresAcceptance=false`; previous documents were preserved.
- Hosting release `1789028760610000` serves and was read back at:
  - `https://ukrainiancommunity-dbd5f.web.app/privacy`
  - `https://ukrainiancommunity-dbd5f.web.app/support`
  - `https://ukrainiancommunity-dbd5f.web.app/delete-account`
- Play Console declarations saved:
  - privacy-policy URL;
  - no ads;
  - not a government app;
  - no financial features;
  - no health features;
  - category `Social Networks`;
  - public contact email and website.
- Data Safety questionnaire completed and saved as a draft:
  - encrypted in transit;
  - account and partial-data deletion URLs supplied;
  - no data sharing with third-party companies or organizations;
  - collected types: approximate location; name, email, user IDs, address, phone, other personal data; other in-app messages; photos; diagnostics; app interactions; other user-generated content; device or other IDs;
  - no advertising/marketing or personalization purpose selected.
- Signed Android build `1.1 (86)` remains available only on Internal testing. No production action was taken.

## Play dashboard state

The setup dashboard still reports `6 of 11` because Google does not count Data Safety as complete until target audience is saved and the pending change can be submitted.

## Honest blockers before closed testing can be enabled

1. **Reviewer credentials.** Play explicitly says reviewers cannot create an account. A dedicated, email-verified ordinary UAC account is required. It must grant access to all normal authenticated areas, must not rely on OTP/biometrics, and must not have moderation/owner privileges.
2. **IARC terms.** Starting the content-rating questionnaire is an explicit acceptance of IARC terms. This was not accepted as part of the confirmed declaration batch.
3. **Store assets.** The Console requires icon, feature graphic, and phone screenshots. Browser automation cannot populate the native file chooser, and the currently authenticated Google token does not have the Android Publisher API scope. The prepared assets are under `Android/release/play/`; the existing screenshots represent the earlier build-79 UI and should be replaced with build-86 store screenshots before production.

Target audience (`16–17` and `18+`) and final Data Safety submission become available after reviewer credentials are saved. Closed-test release and opt-in link follow after all eleven setup items are complete.

## Explicitly not done

- No production-track release or production-access request.
- No external/open testing.
- No IARC agreement acceptance.
- No fabricated reviewer credentials.
- No Firebase Functions deployment; build 86 remains compatible with accepted privacy version `2026.12` while the policy update is non-blocking.
