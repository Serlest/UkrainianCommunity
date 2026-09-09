# Fix80-25 — Управління користувачами

## Межі пакета

- Робоча копія: `/Users/serlest/Developer/UAC-1.1-Build80`
- Базовий commit: `fd58131d2c7c7c5f50b5d354473b91d271990565`
- Деплой, commit, push, build, тести, лінтери, Simulator і встановлення залежностей не виконувалися за умовами координації.
- Зміни в `CloudFunctionsClient.swift`, `AppStrings.swift`, `Localizable.xcstrings`, shared shell, `ContentView.swift`, project-файлі, account deletion і DSA не вносилися.

## Виправлено в цьому пакеті

1. Деталі користувача тепер показують обидва вже отримані з Auth поля, які раніше губилися в UI:
   - чи вимкнений вхід (`authDisabled`);
   - час створення Auth-акаунта (`creationTime`).
2. Пошук явно повідомляє про обмежену сервером вибірку, коли `totalMatches` більший за кількість отриманих користувачів. Повідомлення показує фактичні числа і пропонує уточнити запит.
3. Після успішного запису обмеження у Firestore помилка `revokeRefreshTokens` більше не завершується звичайною успішною відповіддю:
   - callable повертає `HttpsError` з reason `session-revocation-failed`;
   - details чесно фіксують `accountStatusCommitted: true` і `sessionRevocationSucceeded: false`;
   - старий успішний response-контракт не змінений;
   - iOS розпізнає частковий результат за details, перечитує користувача, оновлює UI до вже записаного статусу і показує окреме попередження замість повідомлення про повний успіх.
   - view model тимчасово повертає ту саму account action у список доступних дій; успішний повтор очищає retry.
   - backend розпізнає повтор уже збереженого restricted status, не дублює Firestore mutation, audit log або notification, але все одно повторює `revokeRefreshTokens`.

## Уже виправлено у поточному коді

Ці пункти з аудиту присутні на базі `fd58131` і не переписувалися:

- Firestore document ID є авторитетним UID; поле `data["id"]` його не замінює.
- Ключ сесії завантаження враховує фактичний `canAccessUserManagement`, тому зміна доступу запускає reset/reload.
- Помилка глобального пошуку має стійкий стан, окрему картку помилки та Retry.
- Завантаження організацій має окремий `organizationsLoaded`; організаційні фільтри не видають неповний результат за повний.
- Загальний scroll-контейнер передає дочірньому контенту точну ширину viewport через `containerRelativeFrame`.
- Довгі індивідуальні рядки вже використовують перенесення: `ManagedUserRow` має vertical fixed sizing, badge flow переносить badges, а metadata row переходить з горизонтального в вертикальний layout через `ViewThatFits`. Додаткова локальна перебудова не потрібна без нового runtime FAIL.

## Запропоновані ключі локалізації

Ці ключі передані власнику `AppStrings.swift` / `Localizable.xcstrings`. Прямі звернення через `LocalizationStore` одразу використовують catalog entries, щойно вони з’являються, і мають українські default values до інтеграції.

| Key | Українська | Deutsch |
| --- | --- | --- |
| `user_management.security.auth_status` | Статус входу | Anmeldestatus |
| `user_management.security.auth_enabled` | Вхід дозволено | Anmeldung aktiviert |
| `user_management.security.auth_disabled` | Вхід вимкнено | Anmeldung deaktiviert |
| `user_management.security.auth_created_at` | Створено в Auth | In Auth erstellt |
| `user_management.search.result_limit_notice` | Показано перші %lld із %lld збігів. Уточніть пошук. | Die ersten %lld von %lld Treffern werden angezeigt. Suche verfeinern. |
| `user_management.account_status.session_revocation_failed` | Обмеження збережено, але активні сесії не вдалося відкликати. Спробуйте дію ще раз. | Die Einschränkung wurde gespeichert, aktive Sitzungen konnten jedoch nicht widerrufen werden. Aktion erneut versuchen. |

## Залежності та інтеграція

- Поточна реалізація не потребує зміни `CloudFunctionsClient.swift`: Firebase Functions error details доступні у view model, а успішний response DTO залишається без змін.
- Якщо власник task 22 централізує typed Cloud Functions errors, reason `session-revocation-failed` і поля `accountStatusCommitted` / `sessionRevocationSucceeded` треба зберегти в тому mapper.
- Після завершення локалізаційної інтеграції прямі звернення до `LocalizationStore` можна перенести в `AppStrings.UserManagement`; цей package навмисно не редагує файл іншого власника.

## Self-review

- Diff обмежений екраном/моделлю управління користувачами, деталями користувача, `accountStatusManagement.ts` і цим handoff.
- Firestore transaction залишається завершеною до спроби revoke; error details не стверджують rollback.
- Часткова помилка викликає точкове перечитування користувача з сервера і не скидає список, пошук чи пагінацію.
- Після перечитування restricted status та сама action залишається доступною до успішного retry; restore для цього не потрібний.
- Повтор тієї самої restricted mutation обходить дублювання transaction side effects, але не обходить revoke.
- Cap notice порівнює `totalMatches` з необробленою кількістю server search results, тому локальний role/status filter не створює хибне повідомлення про серверний cap.
- Існуючі довгі row layouts прочитані; speculative refactor не внесений.
- `git diff --check` пройшов. Компіляція і runtime не перевірені через пряму заборону координатора.

## Залишкова перевірка перед release

- TypeScript compile/test для callable та перевірка Firebase emulator сценарію: Firestore commit успішний, revoke падає, та сама action доступна, повтор не додає другий audit/notification і знову викликає revoke.
- iOS build після інтеграції localization/task 22 змін.
- Runtime: Auth disabled/created-at у деталях, capped search у UK/DE, часткова revoke-помилка з оновленим статусом без повідомлення про повний успіх.
- Accessibility runtime для cap notice і metadata rows на великих Dynamic Type розмірах.
- Cloud deploy/read-back окремим дозволеним пакетом. Поточний стан не є deployed або release-verified.
