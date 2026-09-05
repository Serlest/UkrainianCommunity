# UAC 1.0.3 (69) — validation and remaining release gates

Final validation: 2026-09-05. App runtime `81020508e8454cec636f7a8935b8279c2b17bd0a`; test source `d20c9e0c63a012c10c77435327541722cae8f9aa`. Server runtime remains `0681aa0540a8557a57f8c49f9f295bc5266784f2`. Android was neither changed nor tested.

[Sanitized evidence](ReleaseEvidence-1.0.3.json) records source mapping and artifact hashes. [Structured gates](ReleaseGates-1.0.3.json) distinguish completed validation from publication readiness.

## Confirmed

| Area | Evidence and scope |
| --- | --- |
| Full unit | 417 passed, zero failed, three opt-in skips on 415ac7d. Both SDK tests and the OS notification probe passed separately. Later app delta is only explicit accessibility grouping, covered by final UI. |
| Full functional UI | 50 unique / 53 executions, zero failed/skipped on 0172860. |
| Final regression UI | Four DE/UK and AX5 multi-day scenarios passed on d20c9e0; range and endpoint screenshots independently inspected. Both dates/times visible and wrapped. |
| Actual SDK | Timestamp pagination across five repositories and Auth/media/consent/account lifecycle each 1/1 against isolated local emulators. Fixtures cleaned. |
| OS notifications | Separate 1/1 actual Simulator notification-queue account-switch/sign-out probe; not physical APNs delivery. |
| Server | Build/lint, 392 unit checks, 74 integrations, 172 common Rules and 169 iOS-adapted Rules passed; tested production dependency audit zero. |
| iPhone archive | Local Apple Development-signed Release archive69 succeeded on8102050; strict codesign, matching profile, app dSYM UUID, production Firebase configuration and 30 privacy manifests verified. All manifests equal build68; 14 categories. APNs development entitlement; no export/upload/device launch. |
| Privacy | 2026.13 active in Firestore and Hosting; locale/content hashes match, 25 related/historical documents and 14 unrelated website files preserved. Three compatible existing Functions deployed and read back. |
| Search | Two existing Functions deployed; source/runtime settings/IAM verified. The other116 Functions unchanged after sorting unordered event filters; total121 and global App Check unchanged. Reads remain O(N). |
| Content | Three DE title/summary/details patches published with guarded field masks and read-back; actual guest DE cards/details inspected. One event held. |
| Restore | Real backup restored to isolated database;23 documents/five collections sampled, anonymous403, historical hash matched. Temporary database deletion completed with exact404; source/PITR/protection preserved. |

No authenticated production canary is claimed for the deployed functions. The privacy correction describes existing90/180 timing; it does not add presence processing. The multi-day presentation fix preserves stored dates and does not verify their factual accuracy.

## Remaining gates

- **App Privacy:** authenticated questionnaire unavailable (`authResult=FAILED`); compare current answers with the final archive and published policy when access is restored.
- **Distribution/TestFlight:** App Store export/signing, upload, processing and installed TestFlight smoke have not been performed. A development archive is not distribution proof.
- **Physical device / minimum OS:** actual APNs, Face ID/passcode, App Attest, privileged TOTP/recovery and iOS17 runtime remain unverified. Do not infer them from configured entitlements or Simulator26.5.
- **Content:** source confirmation for the held fourth event, content/image rights and structured daily schedule clarification. Hall end17:00 is not source-confirmed; Hackathon admission09:00 and program09:30 must not be conflated. Tags remain source-language content.
- **Final live comments:** accepted/rejected comments in the installed final candidate against the intended backend remain separate from fixtures and older probes.
- **Accessibility/performance:** full manual VoiceOver, global AX5 layout and physical latency/memory/energy measurements remain open. Existing large header action buttons overlap at AX5; the successful date-range regression is not a global accessibility pass.
- **Scaling:** bounded memory does not remove O(N) user reads; index readiness/backfill and shared writers were not activated.

## Authorization and current submission

The user authorized the agreed implementation and scoped external work. Public App Store publication is outside this run. The existing1.0.2(68) submission was not cancelled or published. Historical Apple states are dated evidence and must be refreshed before any later submission action.

`candidate-validation`, `privacy-publication`, scoped authorization, search deployment and bounded restore are recorded passed. Archive/TestFlight remains open for its distribution/TestFlight portion. The strict legal release validator is expected to fail while real publication gates remain; do not remove them to obtain a green command.
