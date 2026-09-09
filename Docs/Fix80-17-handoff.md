# Fix80-17 — Заблокированные организации

Дата реализации: 2026-09-09  
Checkout: `/Users/serlest/Developer/UAC-1.1-Build80`  
Base: `fd58131d2c7c7c5f50b5d354473b91d271990565` (Build 79)

## Что изменено

### Cold-offline fail-closed

- `OrganizationBlockingCoordinator` теперь различает `pending`, `cached`, `confirmed`, `unavailable` и `notRequired`.
- До первой подтверждённой загрузки без локального кэша организационные новости, события и карточки организаций не допускаются политикой видимости.
- Гостевая сессия получает `notRequired`: отсутствие пользовательского blocklist не блокирует гостевой контент.
- Подтверждённый пустой ответ получает `confirmed` и снимает защитный gate; пустой список больше не смешивается с неизвестным состоянием.
- При cold-offline ошибке над публичными вкладками показывается доступная карточка ошибки с Retry. Профиль остаётся доступен.
- При наличии валидного кэша известные блокировки применяются сразу; ошибка обновления не превращает их в пустой список.

Доказанная причина: coordinator начинал с обычного `[]`, а `ContentVisibilityPolicy` не умел выразить неизвестное состояние. Поэтому успешная загрузка публичного feed могла показать материалы server-blocked организации до получения blocklist или после cold-offline failure.

### Reconciliation после неопределённой записи

- После transport-ошибок `NSURLErrorDomain` и Firebase Functions `deadlineExceeded`, `unavailable`, `aborted` выполняется ровно одна немедленная загрузка полного blocklist.
- Если read-back подтверждает требуемое состояние, операция считается успешной, sheet закрывается и локальный кэш обновляется.
- Если read-back не удался или подтвердил противоположное состояние, UI сохраняет исходную ошибку и предлагает повтор.
- Generation/user guards остаются в силе: поздний ответ предыдущего аккаунта не применяется.

Доказанная причина: callable мог применить transaction, но потерять ответ. Старый coordinator показывал timeout и оставлял прежний local set до foreground/manual reload.

### Напоминания, кэш и порядок

- Event reminder reconcile теперь получает только события, разрешённые текущей organization visibility policy. Block/unblock и завершение первоначальной проверки запускают повторную сверку preferences + registered events.
- Это удаляет pending/delivered reminder IDs заблокированных организаций через существующий `LocalEventReminderService.reconcileEventReminders` и восстанавливает допустимые reminders после unblock.
- Blocklist сортируется newest-first с устойчивым tie-breaker по organization ID после fetch, mutation и read-back.
- Namespace предыдущего пользователя удаляется из `UserDefaults` при logout/account switch; визуальное состояние очищается до загрузки следующего пользователя.

### Согласованное общее изменение из Fix80-18

- В существующем `UIApplication.willEnterForegroundNotification` task после organization reload добавлен `await userBlockingCoordinator.reload()`.

## Изменённые файлы

- `UkrainianCommunity/ViewModels/OrganizationBlockingCoordinator.swift`
- `UkrainianCommunity/Models/UserBlockingModels.swift` — shared: один boolean gate в `ContentVisibilityPolicy`.
- `UkrainianCommunity/Views/Profile/BlockedOrganizationsView.swift`
- `UkrainianCommunity/Views/ContentView.swift` — shared: initial fail-closed application, policy observation, visibility gate, filtered reminder reconciliation и foreground user-block reload. Существующие feedback/legal/banner/popup routing hunks сохранены.
- `Docs/Fix80-17-handoff.md`

Backend, Rules, `AuthState`, `CloudFunctionsClient`, `AppStrings`, localization catalog и project file этим пакетом не менялись.

## Ключи локализации для coordinator-owned каталога

Текущая реализация безопасно использует существующие `safety.organization_block.list`, error strings и общий Retry. Для точного текста публичного safety gate рекомендуется добавить:

| Key | UK | DE | EN |
|---|---|---|---|
| `safety.organization_block.verifying_content.title` | Перевіряємо прихований вміст | Ausgeblendete Inhalte werden geprüft | Checking hidden content |
| `safety.organization_block.verifying_content.message` | Зачекайте, поки застосунок підтвердить ваш список заблокованих організацій. | Bitte warten Sie, während die App Ihre Liste blockierter Organisationen bestätigt. | Please wait while the app confirms your blocked organizations list. |
| `safety.organization_block.visibility_unavailable.title` | Не вдалося перевірити прихований вміст | Ausgeblendete Inhalte konnten nicht geprüft werden | Hidden content could not be checked |
| `safety.organization_block.visibility_unavailable.message` | Організаційний вміст залишатиметься прихованим, доки список блокувань не буде підтверджено. Перевірте з’єднання та повторіть спробу. | Inhalte von Organisationen bleiben ausgeblendet, bis die Blockierungsliste bestätigt wurde. Prüfen Sie die Verbindung und versuchen Sie es erneut. | Organization content will remain hidden until the block list is confirmed. Check your connection and try again. |

`action.retry` уже существует.

## Сценарии общего этапа тестов

1. Authenticated, новый install/no cache, медленный успешный blocklist: до ответа organization news/event/cards скрыты, loading gate доступен; после confirmed empty контент восстанавливается.
2. Authenticated, новый install/no cache, offline: organization content остаётся скрытым, error gate и Retry видимы; профиль и переключение на него доступны.
3. Повтор после восстановления сети: confirmed empty снимает gate; confirmed populated показывает только разрешённые материалы.
4. Валидный cached populated + offline: известные blocked IDs применяются сразу, список остаётся видимым вместе с reload error.
5. Guest launch: после `configure(nil)` нет вечного gate; публичный контент загружается.
6. Account A → logout → Account B: блокировки A не появляются у B; ключ A удалён; поздний fetch/mutation A игнорируется.
7. Fetch возвращает записи в случайном порядке и с одинаковым `blockedAt`: UI newest-first, tie-breaker organization ID стабилен.
8. Block success и unblock success: policy обновляется, список сортируется, public content скрывается/восстанавливается.
9. Block commit + simulated deadlineExceeded + successful read-back confirming blocked: sheet закрывается без ложной ошибки.
10. Unblock commit + simulated network loss + successful read-back confirming unblocked: строка исчезает, public content восстанавливается.
11. Timeout + failed read-back: исходная timeout/network ошибка остаётся, повтор доступен, local state не делает оптимистичного предположения.
12. Timeout + read-back opposite state: операция остаётся failed, фактический полный список и кэш соответствуют read-back.
13. Во время mutation/read-back сменить аккаунт: результат предыдущей generation не меняет новый session state.
14. Зарегистрированное событие blocked organization: после block pending и delivered local reminder удаляются; reminder другой организации остаётся.
15. Unblock с включёнными reminders: допустимое зарегистрированное событие снова планируется согласно lead time.
16. Foreground: одновременно обновляются organization и user blocklists; routing diff пакетов feedback/legal/banner/popup не регрессирует.
17. UK/DE light/dark, Dynamic Type XXXL и actual VoiceOver: loading/error gate, Retry, blocked list и confirmation имеют правильный focus/announcement; проверить исправленный общим shell экран Settings.
18. iPhone SE: gate не перекрывает tab bar, Профиль остаётся достижимым, Retry имеет не менее 44 pt.

## Оставшиеся зависимости и границы

- Recent Views и Activity History требуют устойчивого `organizationID` в snapshot schema и общего фильтра; эти экраны не менялись в Fix80-17.
- Client capability для restricted account можно сузить через `PermissionService.isUsableAccount`; email verification уже выражается текущим auth session state. Organization detail header не менялся в этом пакете.
- App Check enforcement для callables требует отдельной проверки совместимости Build 79/старых клиентов и staged rollout; backend не менялся.
- Dedicated gate strings выше должны быть добавлены coordinator-owned локализационным пакетом; до этого используются существующие переводы.
- Actual `UNUserNotificationCenter`, VoiceOver, small-screen и reconnect должны быть подтверждены единым тестовым этапом.

## Проверка в этом пакете

По прямому ограничению координатора тесты, сборки, Simulator, линтеры, dependency install, commit, push и deploy не запускались. Выполнены только реализация и чтение итогового diff.
