# Fix80-31 — Legal evidence handoff

## Baseline and scope

- Baseline: `fd58131d2c7c7c5f50b5d354473b91d271990565` (Build 79).
- Implemented only Legal Evidence models, repository contract, view model, view, callable projection, legal response DTOs, and the minimum fixture/test-stub adaptations required by the repository return type.
- No retention/deletion policy or retention duration was changed. Policy-defined legal and analytics receipts remain retained.
- No search index or scan rollout was added. The existing `adminSearchDocuments` readiness remains `incomplete`; the UI copy below states the real discovery boundary.
- No build, tests, Simulator, linters, install, commit, push, or deploy were run, per coordinator instruction.

## Implemented behavior

1. `LegalEvidenceUserViewModel` now filters by both evidence type and history search text. Search covers event type, UID, version, source, locale, app version, organization, source record ID, platform, consent ID, purpose/disclosure versions and disclosure text. Current account name/email also match the selected subject's complete history.
2. Detail adds `legalEvidence.historySearch` with the existing search placeholder/empty-state copy.
3. Export is now a versioned `LegalEvidenceExportEnvelope` containing:
   - `schemaVersion`
   - server `generatedAt`
   - one subject block with UID, current display name/email, account creation time, and `identityContext=currentAccountIdentityAtExport`
   - all unfiltered events.
4. Backend events now project `sourceRecordId`, `acceptedFromPlatform`, analytics `consentId`, `purposeVersion`, `disclosureVersion`, and exact `disclosureText` when stored.
5. Current profile identity is no longer copied into historical events by any legal evidence callable. The iOS repository also discards legacy event-level identity fields, so an older deployed endpoint cannot make current identity look historical. Current identity remains in the account/subject block.
6. Event cards expose the additional provenance fields when present.
7. The account browser explains that search covers current directory profiles; retained evidence for accounts absent from that directory is not discoverable from the list.

## Coordinator-owned localization additions

Add these accessors to `AppStrings.LegalEvidence` and keys to `Localizable.xcstrings` before building:

| Swift accessor | Key | English | German | Ukrainian |
| --- | --- | --- | --- | --- |
| `accountSearchScopeNotice` | `legal_evidence.accounts.search.scope_notice` | Search covers current account profiles only. Retained evidence for accounts no longer present in the directory is not discoverable from this list. | Die Suche umfasst nur aktuell im Kontoverzeichnis vorhandene Profile. Aufbewahrte Nachweise zu nicht mehr vorhandenen Konten sind in dieser Liste nicht auffindbar. | Пошук охоплює лише актуальні профілі в каталозі облікових записів. Збережені підтвердження для облікових записів, яких більше немає в каталозі, неможливо знайти в цьому списку. |
| `currentIdentityNotice` | `legal_evidence.identity.current_notice` | Name and email are current account details when this history is loaded. Historical confirmations identify the subject by UID and do not prove which name or email was used at that time. | Name und E-Mail sind die aktuellen Kontodaten zum Zeitpunkt des Ladens. Historische Bestätigungen ordnen die Person über die UID zu und belegen nicht, welcher Name oder welche E-Mail damals verwendet wurde. | Ім’я та електронна адреса — це актуальні дані облікового запису на момент завантаження історії. Історичні підтвердження пов’язують суб’єкта за UID і не доводять, яке ім’я чи адресу було використано тоді. |
| `sourceRecordIDLabel` | `legal_evidence.provenance.source_record_id` | Source record ID | ID des Quelldatensatzes | ID вихідного запису |
| `platformLabel` | `legal_evidence.provenance.platform` | Confirmation platform | Plattform der Bestätigung | Платформа підтвердження |
| `consentIDLabel` | `legal_evidence.provenance.consent_id` | Consent ID | Einwilligungs-ID | ID згоди |
| `purposeVersionLabel` | `legal_evidence.provenance.purpose_version` | Purpose version | Zweckversion | Версія мети |
| `disclosureVersionLabel` | `legal_evidence.provenance.disclosure_version` | Disclosure version | Version des Einwilligungshinweises | Версія повідомлення про згоду |
| `disclosureTextLabel` | `legal_evidence.provenance.disclosure_text` | Disclosure text | Einwilligungshinweis | Текст повідомлення про згоду |

## Files changed by this package

- `UkrainianCommunity/Models/Legal/LegalEvidence.swift`
- `UkrainianCommunity/Repositories/Firebase/CloudLegalEvidenceRepository.swift`
- `UkrainianCommunity/Repositories/UITestLegalEvidenceRepository.swift`
- `UkrainianCommunity/Services/Firebase/CloudFunctionsClient.swift` — only `LegalEvidenceFunctionEvent` fields; this file already contained other packages' dirty changes.
- `UkrainianCommunity/ViewModels/LegalEvidenceViewModel.swift`
- `UkrainianCommunity/Views/Profile/LegalEvidenceView.swift`
- `UkrainianCommunityTests/LegalEvidenceViewModelTests.swift` — repository stub return-type adaptation only.
- `UkrainianCommunityTests/AccessReliabilityTests.swift` — existing export assertion decodes the new envelope.
- `functions/src/legal/legalEvidence.ts`

## Integration notes

- The app references the eight coordinator-owned `AppStrings.LegalEvidence` accessors above and will not compile until they are added.
- Deploy `getLegalEvidencePage`/related legal evidence callable projection together with the iOS client to populate the new provenance fields. The client decodes the new fields as optional for backward response compatibility.
- Existing account search still reads the complete current account stream while its index readiness is `incomplete`; this package deliberately does not activate an index or change query cost semantics.
- Runtime/build verification remains pending for the coordinator's serialized validation phase.
