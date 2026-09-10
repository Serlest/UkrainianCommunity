# Owner tools — visual branch inventory

Baseline 85 source and archived screenshots inspected, not counted as new runtime proof.

## 1. Project support

- Root: loading, unavailable, public-card switch, URL validation.
- Ukrainian and German: title, message, button label, counters/validation, keyboard.
- Save: disabled/dirty/saving/saved/conflict/uncertain read-back/error.
- Leave: protected discard dialog, cancel/discard.
- Source changes: shorter page title, inline switch with weighted label, explicit visibility
  explanation, consistent language headings, IME padding. Repository and save semantics unchanged.

## 2. Analytics

- Overview: three periods, search, partial-source warning, updated timestamp.
- Metrics/current-vs-previous, trend, action metrics, popular content, regional/user metrics.
- Organization, news and event details: periods, metrics, regions, partial date.
- Organization → related news/event → detail (nested branch), back to overview.
- Empty, offline, access/refreshing errors.
- Source changes: concise secondary introduction; labeled trend bars with exact numeric values;
  related content rendered as readable navigation cards rather than giant outlined pills.

## 3. System journal

- Overview: metrics, query, expandable quick/date filters, review status, sorting.
- Populated record → summary, metadata/technical values, review action.
- Record deletion → confirmation/cancel; owner only.
- Diagnostics → test push receipt; clear-all → confirmation/cancel; owner only.
- Empty, error and unconfirmed-action recovery.
- Source changes: local-language severity and field labels; Vienna-format timestamps;
  separate summary and label/value metadata; diagnostics below records in its own section;
  filter groups explicitly named. Existing redaction and repository authorization unchanged.

## Evidence status

Build86OwnerVisualUiTest covers populated branches, nested related analytics, donation form fields,
protected discard dialog, errors, list/detail/clear/delete confirmations. Synthetic repositories;
delete/clear/push throw if submitted. This is not production functional proof.

Compilation PASS during implementation. Screenshot execution/review: IN PROGRESS.

## Image review follow-up

All 98 owner captures at native font_scale=2.0 reviewed in 13 labelled sheets, with full-size
inspection of suspicious frames; German/light and Ukrainian/dark. Normal-font populated forms,
overview/detail/related content, errors, filters and diagnostics were also inspected.
Findings fixed and confirmed in final font100/font200 recaptures (`cda63d6`):

- Related analytics navigation reused the previous detail's scroll position. Detail composition
  is now keyed by target; a bounds assertion requires the period control to start within the viewport.
- Ukrainian donation discard dialog clipped the long secondary action at 200% text. Actions are
  now an explicit full-width vertical stack, with a shorter clear edit label and destructive color.
- Deletion/clear cancel actions now have explicit reachability, click and dismissal assertions,
  and separate bottom captures rather than relying on partial visibility.
- Earlier fixes confirmed in rendered output: translated metrics/region labels, readable partial-data
  banner, full-width large-font log metrics, lighter donation cards and properly selected period captures.

No destructive fixture action was submitted. Real production data, device installation, TalkBack,
and every platform/width permutation are not asserted by these screenshots.
