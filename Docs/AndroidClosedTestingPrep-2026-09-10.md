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
- Dedicated standard reviewer account created, verified, login-tested, and saved in Play Console. Its password is stored only in macOS Keychain under service `UAC Play Reviewer`; no credential was committed to the repository.
- Target audience saved as `16–17` and `18+`.
- IARC questionnaire and terms completed. Current ratings include USK 12 for Germany, PEGI parental guidance for Europe, ESRB Teen for North America, and 12+ for the generic IARC regions.
- Data Safety questionnaire completed and saved for review:
  - encrypted in transit;
  - account and partial-data deletion URLs supplied;
  - no data sharing with third-party companies or organizations;
  - collected types: approximate location; name, email, user IDs, address, phone, other personal data; other in-app messages; photos; diagnostics; app interactions; other user-generated content; device or other IDs;
  - no advertising/marketing or personalization purpose selected.
- Default German Store listing completed and saved for review with:
  - app name, short description, and full description;
  - 512×512 app icon;
  - 1024×500 feature graphic, accurately declared as AI-generated;
  - four 1080×1920 German phone screenshots.
- All eleven initial Play setup tasks are complete. The dashboard now exposes the closed-test track setup.
- Closed-test country availability is saved for Austria.
- Signed Android build `1.1 (86)` remains available only on Internal testing. No production action was taken.

## Current closed-test state

- Track: `Closed testing - Alpha`.
- Country: Austria.
- Tester access: pending creation of the self-service Google Group. Google presented a CAPTCHA at the final group-creation step, so human completion is required before its group address can be attached to the Play track.
- Release: not yet created. Build 86 can be promoted from the existing Internal artifact after tester access is saved.
- Opt-in URLs reserved by Play but disabled until the release is published:
  - Android: `https://play.google.com/store/apps/details?id=at.serlest.ukrainiancommunity`
  - Web: `https://play.google.com/apps/testing/at.serlest.ukrainiancommunity`

The current icon and feature graphic are suitable for closed-test setup. The four Store screenshots represent the earlier build-79 UI and remain a deliberate temporary choice to unblock the closed test; replace them with owner-approved build-86 captures before any production submission.

The reviewer login was verified through Firebase Authentication after creation: UID `dMewmkhGatNyrVyWMq29QcK1Ozu2`, email verified, account enabled. Its matching Firestore profile is an active ordinary `user` in Tirol, so privileged management sections remain intentionally unavailable.

## Explicitly not done

- No production-track release or production-access request.
- No external/open testing.
- No reviewer password in source control or documentation.
- No Firebase Functions deployment; build 86 remains compatible with accepted privacy version `2026.12` while the policy update is non-blocking.
