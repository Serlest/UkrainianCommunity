# Android 86 — complete management visual acceptance

User scope: all ten entries under Profile → Керування, including every descendant screen,
form, sheet and confirmation. Build85 is the baseline, not proof of visual acceptance.
No iOS, backend or production-data changes. Synthetic populated data for dangerous actions.

Final acceptance: all ten rows below have completed source changes and synthetic visual review.
Per-row PASS applies to documented synthetic branches and configurations only.
Final source `cda63d6`: 34/34 font100 visual traversals and 165/165 font200 tests
(34 visual + 131 component regression), 1,950 JVM tests and lint PASS.
German/light and Ukrainian/dark were tested, not every possible permutation. See individual
reports for branch-level coverage and limitations; this is not live-cloud or physical-device proof.

## Root inventory, confirmed in MainActivity

| # | Entry | Descendant coverage owner | Status |
|---|---|---|---|
| 1 | Підтримка проєкту | root: enabled/link, Ukrainian/German text, save/error, discard | PASS — synthetic visual |
| 2 | Аналітика | root: periods, metrics, content/organization detail, related content, empty/error | PASS — synthetic visual |
| 3 | Системний журнал | root: filters, entry detail, review, diagnostics, delete/clear confirmations | PASS — synthetic visual |
| 4 | Керування користувачами | Android86-Visual-People.md: list/detail/status/role/legal descendants | PASS — synthetic visual |
| 5 | Перевірка матеріалів | Android86-Visual-People.md: queues/detail/decisions/confirmations | PASS — synthetic visual |
| 6 | Перевірка заявок організацій | Android86-Visual-People.md: queue/application/decision descendants | PASS — synthetic visual |
| 7 | Оповіщення користувачів | Android86-Visual-Support.md: owner editor/audience/schedule/confirmation | PASS — synthetic visual |
| 8 | Рекомендовані банери | Android86-Visual-Content.md: list/editor/media/confirmations | PASS — synthetic visual |
| 9 | Планування контенту | Android86-Visual-Content.md: drafts/detail/editor/media/lifecycle | PASS — synthetic visual |
| 10 | Скринька підтримки | Android86-Visual-Support.md: inbox/case/context/actions/confirmations | PASS — synthetic visual |

## Acceptance rules

- Source inventory is not visual PASS. Each rendered branch requires populated screenshot review.
- Check Ukrainian/German, light/dark, normal/large text, scrolling, keyboard and back navigation.
- Preserve meaningful labels, validation, authorization and destructive-action confirmations.
- Record fixture-only, real-host, emulator, production and physical-device evidence separately.
- No publication claim until exact artifact and Play read-back are recorded.
