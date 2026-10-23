# My event registrations: verification, 2026-10-23

## Scope

Profile → My event registrations, for authenticated roles including application owner. No production registration, event, notification or user record was created, deleted or edited. No backend/rule deployment or TestFlight upload is required by these client changes.

## Data and interaction changes

- Added bounded membership pages: 20 registration records per UI request (repository clamps 1–50), stable document-ID ordering, user-bound continuation cursor and one-record lookahead. Every membership/event read uses server source; manual refresh bypasses the five-minute membership cache.
- Event documents resolve concurrently in batches of at most 10. This list does not request likes or bookmarks. Removed, nonpublic or inaccessible events do not discard the remaining readable events; genuine network failures retain existing rows and continuation.
- Filter counts explicitly describe loaded events while more pages remain. Time ordering applies to loaded events; an unscanned membership page can contain events in any time group. The UI offers continuation even for an empty filtered/hidden-only page. It does not present partial counts as totals.
- Refresh replaces the first page; load more merges by ID. Auth changes clear rows, errors, loading flags and cursor. Generation checks reject old-account results. Registration changes during an in-flight read take precedence over its stale snapshot.
- Separate upcoming, ongoing, completed and cancelled groups. A shared presentation model uses exact current time, scheduled occurrences and exclusive all-day endpoints and legacy same-day fallback. Completed events use their last scheduled occurrence rather than the first. Filters recalculate at minute intervals while the view is active.
- Errors and retry remain visible independently of the selected filter. The screen explains that external website registrations do not automatically enter UAC.
- Cards use vertical full-width presentation with accessibility text sizes; normal cards omit empty thumbnails. All-day dates are read without invented midnight times. Ukrainian and German labels use a separate localization table.
- Opening details retains the existing public EventDetail route. Cancellation updates membership/counters through the existing callable. A server-confirmed repeated cancellation also clears local reminders; it does not duplicate analytics/activity events when didChange is false.

## Evidence

Ignored local artifacts: build/registrations-audit-20261023/.

- RegistrationsLogic.xcresult: 29 unit tests passed before final reminder/empty-page additions.
- RegistrationsVerified.xcresult: 29 unit tests plus full Ukrainian UI flow passed, including 20→24 records, filter change, event open, cancellation and reopen.
- RegistrationsPolished.xcresult: both UI scenarios passed after the accessibility row redesign. German dark/accessibility scenario verifies a loading error remains available with an empty active filter.
- RegistrationsComplete.xcresult: 33 checks passed (31 unit and 2 UI), zero failures/skips, including reminder idempotency and empty-page continuation. RegistrationsFinalLogic.xcresult: all 31 unit tests passed again after adding canonical all-day exclusive-midnight boundary/display checks.
- server-final.log: 12 server/rules tests passed, none skipped. Includes bounded own-membership query and continuation; querying another account is denied. Existing atomic registration counter/idempotency/capacity checks remain green.
- production-query.json: read-only first-page and cursor queries accepted by actual Firestore. Production currently had no registration sample, so this confirms query/index compatibility, not production-user end-to-end persistence.
- Repository/localization validators and git diff --check passed. Final screenshots inspected separately from automated interaction assertions.

## Delivery boundary

Client source is prepared for the next iOS build. Current TestFlight remains 1.2.1 (115). Production schema, rules and callable contracts are unchanged. Reminder reconciliation elsewhere still intentionally reads the full membership set to schedule/cancel reminders; this change bounds the Profile registrations list itself.
