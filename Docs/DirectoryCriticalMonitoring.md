# Directory critical monitoring

Effective 30 October 2026. This supplements DirectoryPublicationOperations-2026-10-18.md.

Before every morning/evening topic rotation, run from `functions/`:

```sh
node scripts/checkDirectoryCriticalSources.mjs --output ABS_NEW_RUN_DIR/critical-sources.json
```

The collector performs read-only requests, retains exact responses and errors, and refuses to overwrite evidence. It does not determine legal truth, publish, or mark a group reviewed. A 200, redirect, unchanged hash, cookie page or source date alone is never sufficient. A blocked source must remain unavailable until an independently competent substitute covers the same claim.

Every run must substantively review these groups against current Firebase payloads:

- Residence: temporary protection, RWR Plus and other NAG transitions, eligibility, protection loss, duration and renewals. Read current VertriebenenVO, NAG and applicable AuslBG provisions, BMI and MA35 implementation. Distinguish Ausweis für Vertriebene from Blue Card EU.
- Benefits: Familienbeihilfe/Kinderbetreuungsgeld and Grundversorgung interaction, using current FLAG/KBGG and competent implementation. The collector's FLAG3 is an entry point; review other governing provisions when relevant.
- Health insurance: coverage after protection/employment/basic-care changes, self-insurance and exceptions. ASVG16 is an entry point, not the complete legal regime; identify the applicable ordinance/provision and ÖGK/competent ministry guidance.

For each group record `criticalChecks`: source URL and observedAt, exact supporting fragments, affected category/topic/section IDs, effective dates/transitions, bilingual comparison, disposition (`unchanged`, `corrected`, `unresolved`, `unavailable`) and a concrete next action. Collector output starts unreviewed. Missing checks mean partial coverage, even if the rotating topic succeeded. Do not silently roll an important unresolved issue out of the next run.

Also search official announcements, RIS promulgations and new competent pages over a rolling 14-day overlap each run. The fixed watchlist cannot discover all new sources. Follow announcements until enacted/rejected and search adjacent catalog blocks for stale versions of the same rule.

Resolve stale guidance through legal scope, commencement and competent implementation, not crawl time. Example regression: BMI RWR FAQ Q8 says other NAG titles are unavailable; VertriebenenVO4a effective 16 October 2026 and current MA35 implement their availability with a conditional written waiver. Record that supersession; distinguish the special RWR Plus route, which does not require that waiver. An unresolved conflict is held and reported, not copied.

Notify a newly discovered material discrepancy affecting status, benefits or coverage with the exact production block and primary source. Report operational failures and precise incomplete coverage. These checks reduce missed changes; they do not guarantee every change will be detected. Keep all existing bridge, revision, bilingual-review and read-back requirements.
