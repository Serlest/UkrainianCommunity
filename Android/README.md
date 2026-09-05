# UAC Android — локальная разработка

Это локальный Android-клиент UAC, **не готовый к публикации релиз всего приложения**. Поддержка, native TOTP UI/SDK, заявки и управление организациями, медиа, authoring/recovery, inbox и ограниченные административные пакеты уже реализованы; их локальные доказательства и оставшиеся границы различаются. README — инструкция безопасной работы, не замена актуальному реестру функций:

- [Текущая точка, блокировки и результаты](../Docs/AndroidOvernightCheckpoint-2026-09-02.md).
- [Журнал проверенных пакетов](../Docs/AndroidMigrationStatus.md).
- [Матрица паритета и незакрытых сценариев](../Docs/AndroidParityMatrix.md).
- [План миграции](../Docs/AndroidMigrationPlan.md) и [визуальная сверка с build65](../Docs/AndroidVisualParityBuild65.md).

Документационный baseline — snapshot39, 2026-09-03: **1 280/1 280 unit PASS на36; оба APK/lint PASS12s на39**. Unit на37–39 UP-TO-DATE, основной APK побайтно совпадает с36; это не новые полные unit-прогоны. Kotlin compiler warnings отсутствовали; lint сохраняет33 warnings и1 hint,0 errors. Реальные component-проверки: API26/snapshot36 **235/235 PASS172.694s**, API37/snapshot37 **235/235 PASS349.173s**, OS font200%. Полные Main: API37/font100/snapshot37 **35/35 PASS334.797s**, API26/font200/snapshot39 **35/35 PASS198.263s** — каждый включает28 Main journeys+7cleanup-policy. A01-C UI9+Device7 также PASS на обеих версиях. Targeted39 API37 management/registrations/policy **9/9 PASS18.757s**. Неудачные API26 прогоны37/38 сохранены: test-only AVD guard и LinkedHashSet cleanup linkage исправлены39;6остаточных документов+2synthetic Auth удалены и независимо проверены. Подробности — в checkpoint; cloud/release proof это не заменяет.

Исходный foundation probe сохранён в настройках как отдельная неэкспортированная Activity. Исторические **35 unit/9 device/UI** относились к foundation/public-browsing пакету, а не ко всему нынешнему приложению.

## Безопасность

- Application ID `at.uac.android.local`; debug only, release variant отключён.
- Firebase named app `uac-local`, только `demo-uac-android`, Android bridge `10.0.2.2`: Auth9098, Firestore8088, Storage9198, local callables5008. Нет production google-services.json, Google Services plugin, default FirebaseApp, Messaging/Analytics/Crashlytics SDK. Auth/Firestore/Storage SDK включены явно; личные данные Firestore не сохраняются на диск.
- Фиктивные applicationId/apiKey не являются credentials. Endpoint нельзя задать через intent, preference или build property. Guard проверяется unit tests. Нельзя переносить реальные данные, секреты и Firebase iOS config в этот проект.
- Synthetic mode по умолчанию. Публичный emulator reader использует Source.SERVER, ограниченные timeout и явные offline/invalid/denied/missing/index/unknown; fallback в cloud отсутствует. Публичные demo-страницы и детали сохраняются атомарно на диске (до 200 записей, 24 часа). Только network/timeout допускают явно помеченную offline-копию; denied/missing/invalid очищают cache. Этот cache не даёт права на запись. Отдельный authoring recovery сохраняет private draft/pending в зашифрованном хранилище и не публикует автоматически; сроки и условия мутаций заданы контрактом конкретного пакета, не общим пятисекундным timeout.
- Network security разрешает cleartext только Android bridge. HTTPS не блокируется глобальным firewall: защита от production основана на фиксированной demo-конфигурации и отсутствии live data source. Это не обещание безопасности произвольно добавленных будущих SDK.
- `firebase.android-local.json` в корне репозитория отделён от существующего firebase.json. Использует текущие локальные Rules/indexes; их согласованные изменения и исторический baseline проверяются отдельно, это не production deployment. Только Auth/Firestore/Storage на loopback; Functions/Hosting/PubSub не запускаются.
- Для actual callable сценариев используется отдельный `firebase.android-functions-local.json` и guarded runtime из `functions/android-local/README.md`: только allowlisted onCall, без triggers/schedulers/внешних сообщений. Local Functions SDK исключён из-за обязательного IID/FIS перед HTTP даже при `useEmulator`; `LocalCallableClient` реализует документированный протокол только для фиксированного demo host/project/region. Это не production gateway и не подтверждение cloud SDK/FCM/App Check.

## Сборка и проверки

Из этой папки, с существующим SDK и Java (глобальные версии не менять). Эти Gradle-задачи только собирают APK и проверяют код, не устанавливают приложение ни на одно подключённое устройство. Перед запуском согласовать владение общей сборкой и неизменный snapshot исходников:

```sh
./gradlew :app:assembleDebug :app:assembleDebugAndroidTest :app:testDebugUnitTest :app:lintDebug --console=plain
node scripts/catalog-contracts.mjs --check
```

Проверка catalog намеренно обнаруживает изменения контрактов; не перегенерировать baseline для сокрытия согласованного Rules/source diff. Общую сборку не запускать одновременно с чужим редактированием или сборкой.

### Только явно выбранный эмулятор

Рабочий телефон может оставаться подключённым. **Не использовать Gradle connected-device задачи или ADB без `-s` для установки/тестов:** они могут выбрать физическое устройство или все устройства. Перед каждой установкой и каждым тестовым пакетом заново проверить имя AVD, SDK, qemu и владение runtime. Прежнее совпадение serial недостаточно после перезапуска эмулятора.

| Проверенный disposable AVD | Serial в текущем checkpoint | Дополнительные условия |
| --- | --- | --- |
| `UAC_API_37_Play_ARM64` | `emulator-5554` | SDK37, qemu1; обычный guarded local test target |
| `UAC_API_26_Compat_ARM64` | `emulator-5556` | SDK26, qemu1, ranchu, модель `Android SDK built for arm64`; только совместимые тесты с `expectCompatibilityApi26=true` |

Ниже пример **одного** публичного component-пакета на точном API37 AVD, не весь набор androidTest и не cloud/native-system proof. Блок останавливается до установки при несовпадении цели; если serial изменился, сначала выяснить точную цель и обновить весь блок, не подставлять serial телефона:

```sh
(
  set -eu
  test "$(adb -s emulator-5554 emu avd name | tr -d '\r' | sed -n '1p')" = 'UAC_API_37_Play_ARM64'
  test "$(adb -s emulator-5554 shell getprop ro.build.version.sdk | tr -d '\r')" = '37'
  test "$(adb -s emulator-5554 shell getprop ro.kernel.qemu | tr -d '\r')" = '1'
  adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk
  adb -s emulator-5554 install -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
  adb -s emulator-5554 shell am instrument -w -r \
    -e class at.uac.android.UacChromeUiTest \
    at.uac.android.local.test/androidx.test.runner.AndroidJUnitRunner
)
```

Для API26 не достаточно заменить serial: повторить проверки точного имени/SDK/qemu/hardware/model и добавить `-e expectCompatibilityApi26 true` только классу, который поддерживает `CompatibilityAvd`. Отказ guard или пропущенный тест — не PASS. Полный пакет запускать лишь по согласованному явному списку классов и текущему checkpoint; два AVD не должны одновременно изменять общие fixtures.

### Шрифт, online и native-проверки — разные условия

- Реальный масштаб сначала прочитать, например `adb -s emulator-5554 shell settings get system font_scale`. Main/dialog/font200 тесты требуют настоящего OS значения 2.0; injected Compose density в component-тесте его не заменяет. Изменение/восстановление масштаба выполняет владелец конкретного AVD, не тест на рабочем телефоне.
- Для online Auth/Firestore/Storage нужны действующие локальные сервисы и `-e expectEmulator true`; для callable сценариев дополнительно guarded Functions runtime и `-e expectFunctions true`. Эти аргументы не запускают сервер и не включают cloud.
- Native media явно требует `-e expectNativeStartup true` и проверенный `-e expectStartupAsset ORIGINAL` (текущий API37) либо `COMPATIBILITY` (текущий API26). Это отдельный capability/TextureView тест.
- Настоящие reminders/PIN/privacy сценарии требуют собственных reviewed opt-in флагов, состояния устройства, ограниченного времени и cleanup/read-back; например `expectLocalReminders`, `expectLocalDeviceLock`. Не добавлять их массово ко всем классам. PIN/Doze/cold process проверки допустимы только на выделенном disposable AVD и не выполняются приведённым примером.
- Сохранять точные serial/AVD/API, SHA APK, список классов, флаги, масштаб и итог runner. Успешный exit команды сам по себе не заменяет число PASS/FAIL/SKIP и подтверждённую очистку fixtures.

### Локальный сервер и fixtures

Порты 9098/8088/9198/5008 и Firebase hub принадлежат одному согласованному запуску. Не запускать второй сервер и не останавливать чужие listeners. В отдельном окне, после освобождения портов, можно выполнить **host-only** проверку Auth/Firestore/Storage; она не вызывает ADB и не запускает устройство:

```sh
sh scripts/run-local-checks.sh
```

Для actual callable/device-пакетов следовать [guarded runtime README](../functions/android-local/README.md): он запускается отдельно до выбранной ADB-команды и остаётся живым до завершения тестов и exact cleanup. Использовать только demo fixtures и указанные в выбранном классе preconditions; тесты не имеют единого общего режима «все offline по умолчанию».

`local-fixtures.mjs` не очищает базу целиком: пишет именованные synthetic fixtures, включая публичный demo `appConfig/donation`. `generate-content-fixtures.mjs` создаёт общий asset из 84 вымышленных документов; один файл читают Android и локальный seeder. Admin bypass используется только в подготовке/уборке тестов; пользовательские операции выполняются через настоящий локальный Auth/Firestore/Storage и Rules. Исторические результаты пакетов1–2 не заменяют текущую проверку изменённых BC01 Rules. Тесты создают уникальные synthetic accounts и собственные документы, никогда production.

Поиск/категории/аудитория просматривают следующие backend-страницы, а не только уже видимые карточки. После 20 пачек показывается продолжение, а не ложное «ничего нет». Cursor содержит исходные timestamp + ID; список событий — endDate, рекомендации событий — createdAt. Регион включает общенациональный контент. Настоящие cloud-медиа не загружаются: exact canonical URL demo Storage строго перенаправляется клиентом на `10.0.2.2:9198`, без обращения к HTTPS/cloud host и без redirects; проверяется исходный bucket/path. Встроенная картинка соответствует только точному `https://example.invalid/media/community.png`.

Баннеры: сроки, секции, регион, priority → updatedAt → ID; неизвестная конфигурация не активируется. По умолчанию ручная карусель; пользователь может включить таймер 3–12 секунд из документа. В фоне и при TalkBack таймер приостанавливается. Никакого нового role/audience-поля в backend не добавлено. Event/editor timezone, create-only NOW/SCHEDULED и encrypted recovery уже имеют свои контракты и проверки; это не доказательство отдельного owner-planning/lease workflow. Актуальные границы — в матрице, не в историческом foundation inventory.

Инструменты закреплены: Gradle 9.1.0 с distribution SHA-256, AGP 9.0.1 built-in Kotlin, Compose compiler 2.3.20, Compose BoM 2026.03.01, Firebase BoM 34.18.0, lifecycle 2.10.0, coroutines 1.10.2; Espresso 3.7.0 явно. Источник истины для дополнительных точечных SDK pins — build files, не этот краткий перечень. JDK toolchain 17, compile/target API36, min API26. Выбранные сценарии фактически проверены на ARM64 API26 и API37 AVD; это не утверждённая полная OEM/physical-матрица релиза. Wrapper взят из проверенного официального шаблона, не глобальный Gradle.

### Единый стиль Kotlin

`bash scripts/format-kotlin.sh --check` проверяет Android Kotlin и build scripts без изменения исходников; `--write` применяет отступы Kotlin style (4 пробела). Используется ktfmt 0.64 с закреплённым SHA-256 официального release asset. При первом запуске инструмент загружается только в игнорируемую Android `.gradle/uac-tools`; глобальные настройки IDE и iOS-файлы не меняются. Готовый проверенный jar можно передать через `UAC_KTFMT_JAR`. Импорты автоматически не удаляются. Форматирование не заменяет компиляцию, unit и экранные проверки; не применять его одновременно с редактированием тех же файлов.

## Структура

- core/backend: фиксированный provider, named Firebase binding, gateway и явная недоступность cloud/Main push в локальной сборке.
- feature/foundation: state + ViewModel → repository → synthetic/emulator data source; constructor injection, StateFlow, lifecycle-aware Compose.
- feature/browse: wire mapping, источники, ограниченный public cache, страницы/cursor, SavedStateHandle, отдельные списки/детали/настройки и безопасные переходы.
- feature/*: отдельные сценарные слои Auth/personal/community/organization/media/authoring/recovery/moderation и другие; актуальный охват и ограничения см. в матрице, не выводить полноту из наличия папки.
- test/androidTest: unit, component UI, actual SDK/Rules, Main journeys и opt-in native/cold/fault проверки. Числа, snapshots и воспроизводимые receipts — в журнале; старые 35/9 сохранены выше только как foundation-история.
- ../Contracts/Android: общий source contract snapshot; не включать его в APK.
- ../Docs/AndroidMigration*: постоянный план/журнал/паритет/аудит. Читать до продолжения; следующий пакет требует согласования.

Полный ручной TalkBack, signed-in visual matrix, OEM/physical, память/performance, настоящий privileged TOTP, App Check/Play Integrity, Main FCM account ownership и облачные service read-back остаются отдельными gates. Успех отдельного pushprobe не равен Main push, а A01-C local UI/negative proof не равен privileged-positive или server CAS. Android legal/Data Safety, подпись и Play/production требуют отдельного решения.

Следующий порядок: завершить текущую точную регрессию → отдельно согласованный test-cloud provider → real TOTP/privileged и Main FCM → оставшиеся admin/planning возможности → финальные release gates. Последние фактические результаты — в связанных Docs; никакая инструкция README не запускает следующий этап автоматически.
