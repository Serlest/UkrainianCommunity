# Fix80-27 — Планування контенту

## База і межі

- Спільна робоча копія: `/Users/serlest/Developer/UAC-1.1-Build80`
- Базовий commit на старті: `fd58131d2c7c7c5f50b5d354473b91d271990565`
- Змінено лише модель planning draft, її Firestore decoder та planning UI.
- `ContentView`, `ProfileViews`, shared shell, backend, project і localization не змінювалися цією задачею.
- Новий navigation case або API не потрібні.

## Змінені файли

- `UkrainianCommunity/Models/OwnerContentDraft.swift`
- `UkrainianCommunity/Repositories/Firebase/FirestoreOwnerContentDraftRepository.swift`
- `UkrainianCommunity/Views/Profile/OwnerContentPlanningView.swift`
- `Docs/Fix80-27-handoff.md`

## Виправлено

1. Planning cards тепер показують усі `sourceReferences`, а не лише перше джерело. Primary source піднімається вгору і позначається зіркою. Для кожного джерела показуються title, URL і `checkedAt`; валідні `http/https` URL відкриваються через `Link`, інші залишаються текстом.
2. Усі непорожні `verificationNotes` відображаються на planning cards, у scheduled detail та history receipt.
3. Scheduled draft має окрему кнопку відкриття і read-only detail. У detail немає editor, publish, archive або delete action.
4. Event draft без `payload.startDate` більше не втрачає весь `eventDraft` під час decoding. Decoder додає `startDate` у `missingFields` і використовує `updatedAt` лише як внутрішній transport placeholder.
5. Перед відкриттям editor для такого редагованого event draft planning flow вимагає явної зміни DatePicker. Після вибору створюється лише локальна копія draft із датою; запис у backend не виконується.

## Already fixed у Build 79 і збережено

- `canDiscardInPlanning` уже дозволяв archive/delete для неповного unpublished draft навіть без editor payload. Цю поведінку не дубльовано і не послаблено.

## Publication invariants

- Editor відкривається лише коли `isEditableInPlanning == true`.
- Missing-start-date preflight застосовується лише до редагованих draft states.
- `scheduled` відкривається тільки в read-only detail.
- `completed` і `archived` залишаються у history receipt.
- Активний non-expired `publishing` не потрапляє в editor; deep link може показати лише read-only detail.
- Ця зміна не викликає publication API і не створює реальний матеріал.

## Localization handoff

Поточна реалізація використовує лише наявні `AppStrings` і не додає нового ключа. Для явних текстових/VoiceOver-позначок замість поточних іконок рекомендовано додати координатором:

| Key | Українська | Deutsch |
| --- | --- | --- |
| `content_planning.sources.title` | Джерела | Quellen |
| `content_planning.sources.primary` | Основне джерело | Primärquelle |
| `content_planning.sources.checked_at` | Перевірено: %@ | Geprüft: %@ |
| `content_planning.verification_notes.title` | Нотатки перевірки | Prüfnotizen |
| `content_planning.scheduled.open` | Переглянути запланований матеріал | Geplanten Inhalt ansehen |
| `content_planning.missing_start_date.title` | Укажіть дату події | Veranstaltungsdatum angeben |
| `content_planning.missing_start_date.message` | Оберіть дату й час перед відкриттям редактора. | Datum und Uhrzeit vor dem Öffnen des Editors auswählen. |
| `content_planning.missing_start_date.confirm` | Підтвердити дату й відкрити редактор | Datum bestätigen und Editor öffnen |

## Залежності

- Немає нового route/API/backend dependency.
- Якщо coordinator додасть localization keys вище, `OwnerContentEditorialMetadataView` і `OwnerContentMissingEventStartDateView` можна перевести з повторно використаних загальних labels на ці точні тексти.

## Remaining validation

- Build: **NOT RUN** за умовою делегування.
- Tests: **NOT RUN** за умовою делегування.
- Simulator/runtime/accessibility: **NOT RUN** за умовою делегування.
- Потрібно перевірити після інтеграції: кілька джерел із primary/checkedAt; invalid URL; кілька verification notes; scheduled news/event detail; completed receipt; event `needsAttention` без startDate; cancel preflight; explicit date selection; відсутність editor/publish action для scheduled/completed/publishing.

## Self-review

- Diff перечитано в межах чотирьох файлів задачі.
- Shared dirty changes інших задач не змінювалися і не скидалися.
