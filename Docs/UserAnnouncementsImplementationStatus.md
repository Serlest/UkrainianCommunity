# Оповещения пользователей — реализация и проверка

Дата: 2026-09-07. Реализация и автоматические проверки завершены; архив 1.0.3 (70) готов, загрузка TestFlight выполняется. Физический APNs/device acceptance пока не подтверждён.

Пользователь явно разрешил автономную реализацию, исправления, тесты и новый билд после успешных проверок. Публичная публикация приложения не запрошена.

## Рабочая копия

`/Users/serlest/Developer/UACAnnouncements-20260907`, ветка `codex/user-announcements-20260907`, основа `update/1.0.3` / `c9ec39a` (1.0.3 build 69). Новый номер — 70, проверен по App Store Connect перед сборкой.

Изменения перенесены с ранней рабочей копии build 68 трёхсторонним патчем. В конфликте AppDelegate сохранены и изоляция unit-test host, и новая обработка push. Собственные первоначальные изменения обращены точным обратным патчем в `/Users/serlest/Developer/UkrainianCommunity`; параллельные изменения Android сохранены. План оставлен также в исходной папке.

## Реализовано

- Owner-only раздел профиля; двуязычный редактор, перевод uk/de с обязательной проверкой, черновики, предпросмотр, подсчёт аудитории, тест себе, публикация/расписание, отмена и статистика.
- Адресаты: конкретные аккаунты, объединение групп registered/guests/org owners/app admins/org admins/org moderators. Регион зарегистрированных берётся из `users.selectedFederalState`; гости без регионального фильтра. Роли организаций проверяются по authoritative полям организаций.
- Отдельный серверный контракт `schemaVersion=1`, отдельные коллекции/receipt/устройства; legacy inbox не используется. Android пока отклоняется; будущему клиенту нужны адаптер UI/repository и явное включение серверной capability, без копирования доменной логики.
- Окно при входе, один автоматический показ за сессию; обычный режим один раз и режим до подтверждения. Новая сессия после перезапуска или 30 минут в фоне. Обязательные экраны имеют приоритет. История, отмена/срок, переход в «Звернення» с темой объявления.
- Подтверждения аккаунта синхронизируются между устройствами; гостевые отметки локальные. Повторные события идемпотентны, сбои синхронизации сохраняют pending-отметку. Смена аккаунта очищает отображаемое личное состояние.
- Дополнительный push iOS, гостевой opt-in, FID challenge для доказательства контроля установки, нейтральный lock-screen текст и повторная проверка аудитории при открытии. Отдельные метрики аккаунтов/гостевых установок. Успешно отправленные задания не повторяются при повторной обработке страницы; транспортное exactly-once не обещается.
- История/receipt хранятся до 180 дней после срока объявления; устройства без обновления удаляются через 90 дней. Перевод ограничен 20 запросами в день на владельца. При сбое перевода доступен ручной ввод.

## Проверки на актуальной основе 1.0.3

| Проверка | Результат | Лог в `output/announcements/` |
| --- | --- | --- |
| Общий Functions unit/integration, последовательный запуск | 457 PASS, 0 FAIL; 11 специализированных SKIP затем проверены отдельно | `server-final.log` |
| Firestore/Storage Rules | 173 PASS, 0 FAIL, 0 SKIP | `server-final.log` |
| Специализированный retention demo | 44 PASS, 0 FAIL, 0 SKIP | `retention-specialized.log` |
| Специализированный managed-user search demo | 9 PASS, 0 FAIL, 0 SKIP | `remaining-server-tests.log` |
| Финальный контракт/сервис/device challenge/retry/cleanup объявлений | 11 PASS, 0 FAIL, 0 SKIP | `announcements-final.log` |
| Дополнительные Rules с настоящими role-документами owner/admin/user | 1 PASS, 0 FAIL | `rules-owner-final.log` |
| Полная обычная Swift-регрессия | 423 PASS; opt-in SDK/OS сценарии отдельно | `ios-regression.log` |
| Общий UI smoke + новые сценарии | 6 PASS, 0 FAIL | `ios-regression.log` |
| Финальные Swift-тесты объявлений + реальная OS очередь уведомлений | 8 PASS, 0 FAIL, 0 SKIP | `ui-publish-final.log` |
| UI owner: две локализации → save → preview → review → publish | PASS | `ui-publish-final.log` |
| UI guest: окно uk/dark → acknowledge → история; owner entry отсутствует | PASS | `confirmation-final.log` |
| Реальный Firebase SDK: Codable callable, owner publish, guest feed, receipt/statistics, cancellation | PASS | `sdk-real-final.log` |
| Реальный SDK существующей snapshot cursor pagination | PASS | `sdk-real-final.log` |
| TypeScript, App Check policy, локализации, plist, индексы, release config, diff check | PASS | вывод валидаторов / `appcheck-policy.log` |
| npm production audit | 0 vulnerabilities | `npm audit` |

Ранние неуспешные попытки сохранены для диагностики, не считаются итоговым PASS. Причины устранены: пути emulator config; UI тест нажимал центр длинного label вместо самого switch. UI смена языка/публикация проверены скриншотами `ui-final-screenshots/`. Последняя Debug сборка имеет 0 compiler warnings/errors. Исправлены выявленные Swift actor isolation и ambiguous Optional.none; AppIntents metadata extraction теперь выполняется с framework import.

Штатный общий запуск намеренно пропускает `FirebaseEmulatorJourneyTests` (старый полный photo/consent SDK fixture); этот независимый сценарий не запускался в данном пакете. Новый полный SDK-путь объявлений и прежняя cursor-проверка выполнены отдельно без skips. Физическое устройство и APNs не заменяются этими тестами.

## Cloud read-back

Production: `ukrainiancommunity-dbd5f`, `europe-west3`.

- Развёрнуты только 6 новых функций: `manageAnnouncements`, `getAnnouncements`, `acknowledgeAnnouncement`, `registerAnnouncementDevice`, `deliverAnnouncements`, `cleanupAnnouncements`. Все `ACTIVE`, Node.js 22.
- Новый collection-group индекс `announcementReceipts.retentionExpiresAt` — `READY`; прежние collection индексы сохранены. Firestore/Storage Rules и старые функции не переустанавливались.
- Четыре публичных callable endpoint без App Check/auth дают HTTP 401. Owner/MFA/audience положительные и отрицательные сценарии проверены в эмуляторе; реальный owner Auth/App Attest сеанс на iPhone ещё не проверен.
- `appConfig/announcements`: enabled/iosEnabled/pushEnabled=true, androidEnabled=false. Ни одной кампании реальным пользователям не отправлено.
- Планировщик доставки и ручной запуск новой очистки завершились с успешным статусом. Реальный push с содержимым кампании не проверялся.
- Cloud Translation API включён; live uk→de перевод двух тестовых строк успешно выполнен. Новые функции используют тот же service account, что существующая доставка; IAM не менялся.
- Первые Firebase CLI попытки использовали неподходящую сохранённую авторизацию. Развёртывание выполнено существующей gcloud ADC в отдельной конфигурации CLI с quota project. Диагностическое предупреждение CLI про quota header при upload не помешало загрузке; это не compiler warning. Не менялись роли ради обхода ошибки.

Доказательства: `cloud-readback.json`, `index-readback.json`, `cloud-negative-probes.json`, `rollout-live.json`, `scheduler-readback.json`, `cleanup-live-readback.json`, `translation-live-check.json`, `functions-deploy-final.log`.

## Воспроизведение SDK проверки

1. Собрать `functions` (`npm run build`). Запустить `firebase emulators:start --project demo-uac-release-audit --config firebase.announcements-emulators.json --only auth,firestore,functions,storage`. Конфигурация фиксирует localhost ports, UI выключен.
2. Выбрать `cursor-<UUID>`, выполнить `node scripts/seed-cursor-sdk-emulators.cjs seed <run>`. В локальном `appConfig/announcements` задать enabled=true, iosEnabled=true, pushEnabled=false. Никогда не использовать live project для fixture.
3. Передать test runner `UACFirebaseEmulators=1`, `UACCursorFixtureRun=<run>` и запустить только `AnnouncementSDKEmulatorTests` и `FirestoreRepositoryCursorEmulatorTests` с подписанным Debug Simulator host. Подробности подписи — `LocalIOSValidation.md`. В текущем прогоне использованы `TEST_RUNNER_` environment prefixes и Xcodebuild `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES`.
4. Удалить только собственную кампанию `<run>-announcement` с её metrics, guestMetrics и receipt; затем `seed-cursor-sdk-emulators.cjs cleanup <run>`, завершить собственные эмуляторы. В текущем прогоне cleanup 61 документов/Auth подтверждён.

## Оставшийся уровень приёмки

Нужен доступный iPhone: owner Auth/App Attest → test self → push при закрытом приложении → открытие окна → гостевой opt-in/opt-out → смена аккаунта. Сейчас `Serlest Mobile` недоступен через devicectl. Успешные тесты/архив/TestFlight не являются доказательством этих сценариев. Публичная публикация и App Review не выполняются.

## Архив build 70

Release archive завершён успешно, compiler warnings/errors: 0/0. `codesign --verify --deep --strict` PASS. Info.plist: 1.0.3 (70), ITSAppUsesNonExemptEncryption=false. Архив: `/tmp/UAC-announcements-70.xcarchive`; log: `output/announcements/archive70.log`. Export/upload и обработка Apple пока проверяются отдельно.
