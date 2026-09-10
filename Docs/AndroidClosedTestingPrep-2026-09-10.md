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
- Scoped Hosting release `1789032133429000` added the bilingual child-safety standards and updated only the support-page link; the other 15 hosted files were preserved and read back:
  - `https://ukrainiancommunity-dbd5f.web.app/child-safety`
- Play Console declarations saved:
  - privacy-policy URL;
  - no ads;
  - not a government app;
  - no financial features;
  - no health features;
  - category `Social Networks`;
  - public contact email and website.
  - Advertising ID is not used; this matches the exact merged Build 86 production manifest, which has no `com.google.android.gms.permission.AD_ID` permission.
  - child-safety standards URL, in-app reporting capability, legal/authority-reporting commitment, and the verified Play developer contact.
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
- Signed Android build `1.1 (86)` remains available on Internal testing and has now been submitted for Closed-testing review. No production action was taken.

## Current closed-test state

- Track: `Closed testing - Alpha`.
- Country: Austria.
- Tester access: Google Group `UAC Android Closed Test` was created at `https://groups.google.com/g/uac-android-closed-test`; anyone may find and join it. Play tester access is now managed by `uac-android-closed-test@googlegroups.com`, replacing the temporary two-address email list.
- Release: closed-track release `1.1 (86)` was created from the exact signed Internal artifact; German and Ukrainian release notes and ReTrace mapping are attached. It was submitted to Google review on 2026-09-10.
- Publishing overview: both blocking precheck findings were resolved and the final fast precheck completed. Play read-back now states `Deine Änderungen werden jetzt überprüft` and lists the 14 submitted changes, including Closed testing Alpha, Build 86, Austria and the Google Group. The package is limited to Closed testing and required app-content/store declarations; no production release is present.
- Opt-in URLs reserved by Play but disabled until the release is published:
  - Android: `https://play.google.com/store/apps/details?id=at.serlest.ukrainiancommunity`
  - Web: `https://play.google.com/apps/testing/at.serlest.ukrainiancommunity`

The current icon and feature graphic are suitable for closed-test setup. The four Store screenshots represent the earlier build-79 UI and remain a deliberate temporary choice to unblock the closed test; replace them with owner-approved build-86 captures before any production submission.

The reviewer login was verified through Firebase Authentication after creation: UID `dMewmkhGatNyrVyWMq29QcK1Ozu2`, email verified, account enabled. Its matching Firestore profile is an active ordinary `user` in Tirol, so privileged management sections remain intentionally unavailable.

The exact merged Build 86 production manifest was inspected before the Advertising ID answer. It contains notification, network, biometric and Firebase Messaging permissions but no Advertising ID permission. The published child-safety page was then checked in both German and Ukrainian through the live site; the language switch, reporting link, standards and contact are rendered and accessible.

## Explicitly not done

- No production-track release or production-access request.
- No external/open testing.
- No reviewer password in source control or documentation.
- No Firebase Functions deployment; build 86 remains compatible with accepted privacy version `2026.12` while the policy update is non-blocking.
