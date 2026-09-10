# Android 86 — complete management visual acceptance

User scope: all ten entries under Profile → Керування, including every descendant screen,
form, sheet and confirmation. Build85 is the baseline, not proof of visual acceptance.
No iOS, backend or production-data changes. Synthetic populated data for dangerous actions.

## Root inventory, confirmed in MainActivity

| # | Entry | Descendant coverage owner | Status |
|---|---|---|---|
| 1 | Підтримка проєкту | root: enabled/link, Ukrainian/German text, save/error, discard | IN PROGRESS |
| 2 | Аналітика | root: periods, metrics, content/organization detail, related content, empty/error | IN PROGRESS |
| 3 | Системний журнал | root: filters, entry detail, review, diagnostics, delete/clear confirmations | IN PROGRESS |
| 4 | Керування користувачами | Android86-Visual-People.md: list/detail/status/role/legal descendants | IN PROGRESS |
| 5 | Перевірка матеріалів | Android86-Visual-People.md: queues/detail/decisions/confirmations | IN PROGRESS |
| 6 | Перевірка заявок організацій | Android86-Visual-People.md: queue/application/decision descendants | IN PROGRESS |
| 7 | Оповіщення користувачів | Android86-Visual-Support.md: owner editor/audience/schedule/confirmation | IN PROGRESS |
| 8 | Рекомендовані банери | Android86-Visual-Content.md: list/editor/media/confirmations | IN PROGRESS |
| 9 | Планування контенту | Android86-Visual-Content.md: drafts/detail/editor/media/lifecycle | IN PROGRESS |
| 10 | Скринька підтримки | Android86-Visual-Support.md: inbox/case/context/actions/confirmations | IN PROGRESS |

## Acceptance rules

- Source inventory is not visual PASS. Each rendered branch requires populated screenshot review.
- Check Ukrainian/German, light/dark, normal/large text, scrolling, keyboard and back navigation.
- Preserve meaningful labels, validation, authorization and destructive-action confirmations.
- Record fixture-only, real-host, emulator, production and physical-device evidence separately.
- No publication claim until exact artifact and Play read-back are recorded.
