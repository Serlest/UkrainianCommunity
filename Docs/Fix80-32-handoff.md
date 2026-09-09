# Fix80-32 — System Logs

## Межі пакета

- Робоча копія: `/Users/serlest/Developer/UAC-1.1-Build80`
- Базовий commit: `fd58131d2c7c7c5f50b5d354473b91d271990565`
- Змінені лише `Features/SystemLogs`, вузький callable `functions/src/systemLogs/clientDiagnostics.ts` і цей handoff.
- `Firebase/firestore.rules`, indexes manifest, `AppStrings.swift`, `Localizable.xcstrings`, routing, shared shell і project file не редагувалися.
- Build, tests, linters, Simulator, install, commit, push і deploy не запускалися за прямою умовою координатора.

## Виправлено

1. **Server-fresh list, pagination і detail.**
   - `fetchPage` використовує `getDocuments(source: .server)`.
   - `fetchLog` використовує `getDocument(source: .server)`.
   - Offline/cache fallback більше не може виглядати як свіже завантаження адміністративного журналу.

2. **Detail більше не є мовчазно застарілим snapshot зі списку.**
   - При відкритті detail виконується точкове server refresh.
   - Поки refresh триває, показується progress.
   - Якщо документ видалено або server read не вдався, fallback залишається видимим разом з явною error-карткою і Retry.
   - Після mark-reviewed detail ще раз читається із server, тому `reviewedAt` переходить з локального optimistic часу на фактичний server timestamp.

3. **Partial bulk review показує фактично записаний стан.**
   - Repository зберігає порядок ID, прибирає дублікати і накопичує ID лише після успішного commit кожного batch до 400.
   - Якщо пізніший batch падає, `SystemLogBulkReviewPartialError` повертає точний список уже committed ID.
   - View model позначає reviewed лише ці ID та показує окреме повідомлення про частковий результат. Перший failed batch не змінює UI.

4. **Callable сам виконує redaction.**
   - `writeClientDiagnostic` після schema/size validation редагує metadata за sensitive key fragments і token/email-like values.
   - Sensitive `technicalMessage` замінюється на `[redacted]`.
   - Це захищає callable від модифікованого або старого клієнта, який не застосував Swift `SystemLogRedactionPolicy`.

## Точна Rules-передача координатору

Поточний Build79 уже пише diagnostics через `writeClientDiagnostic`; Admin SDK callable обходить client Rules. Прямий diagnostics create у Rules залишається реальним bypass. Найнадійніше сумісне для Build79 звуження — закрити лише legacy direct diagnostics create після підтвердження, що жодна підтримувана production-версія не використовує його:

```diff
     function canCreateDiagnosticsLog(logId) {
-      return isOwnerOrAppAdmin()
-        && isSafeDiagnosticsCreate(logId);
+      return false;
     }
```

`validSystemLogClientCreate` та інші audit/moderation/security create paths не змінюються. Callable `writeClientDiagnostic` продовжує працювати, бо використовує Admin SDK. Якщо production minimum version ще містить direct diagnostics write, цей hunk поки не застосовувати: Rules не можуть надійно перевірити всі значення довільної metadata map, тому частковий key blacklist не закриє bypass. Спочатку потрібне підтвердження client-version distribution або staged migration.

## Ключі локалізації для coordinator-owned catalog

| Key | Українська | Deutsch | English |
| --- | --- | --- | --- |
| `system_logs.detail.not_found` | Запис журналу більше не доступний. | Der Protokolleintrag ist nicht mehr verfügbar. | This log entry is no longer available. |
| `system_logs.review.partial_failure` | Частину записів позначено як переглянуті. Не вдалося завершити всю операцію. Оновіть журнал і повторіть спробу. | Einige Einträge wurden als geprüft markiert. Der Vorgang konnte nicht vollständig abgeschlossen werden. Aktualisieren Sie das Protokoll und versuchen Sie es erneut. | Some entries were marked as reviewed, but the operation did not finish. Refresh the log and try again. |

До інтеграції catalog entries код використовує українські default values через `LocalizationStore.localizedString`.

## Не змінювалося навмисно

- Відсутні в source manifest індекси не трактувалися як відсутні production indexes; нові індекси не додавалися.
- Search, metrics і client filters залишаються обмеженими вже завантаженими сторінками, що UI прямо повідомляє. Розширювати Firestore query без перевірки deployed indexes небезпечно.
- AppAdmin Rules усе ще повертають повний документ для `isAppAdminReadable=true`; UI-only приховування полів не було б security boundary.
- Owner delete/clear callable gates не змінювалися в цьому вузькому пакеті.

## Self-review

- Cache fallback прибраний для initial page, next page і point detail read.
- Cursor оновлюється лише з server snapshot.
- Partial error містить тільки batch ID, commit яких уже завершився; failed batch не додається.
- Dedupe bulk ID тепер детермінований і зберігає порядок видимого списку.
- Detail error не стирає fallback, але більше не подає його як підтверджено актуальний.
- Після review server reread також виправляє optimistic `reviewedAt`.
- Callable redaction відбувається до Firestore transaction і quota write.
- `git diff --check` потрібно виконати координатору разом із загальною інтеграцією; локально команди перевірки заборонені умовою пакета.

## Обов'язкова перевірка координатором

- iOS compile для Firebase async overloads та Swift concurrency diagnostics.
- Unit: first bulk batch failure; second batch failure після 400 success; duplicate/empty IDs; exact committed UI state.
- Detail: server success/not-found/network; Retry; review server timestamp reread.
- Firestore emulator offline/cache proof: cached data існує, `.server` read падає і не замінює його на fresh.
- Functions tests: metadata token/email key/value та sensitive technical message повертаються `[redacted]`, safe fields не змінюються.
- Rules emulator після узгодження hunk: direct diagnostics create denied owner/admin; callable-created documents readable у правильному scope; audit/moderation/security creates не регресують.
- Production/deploy/read-back залишаються окремим дозволеним етапом.
