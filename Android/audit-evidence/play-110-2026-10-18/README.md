# Android 1.2 (110) — сверка актуальности и тестовая доставка

18.10.2026. Авторитетный checkout `/Users/serlest/Developer/UAC-Android-1.2-Parity107`, `codex/android-parity-1.2-107`; исходный HEAD `6b4ab10`, дерево чистое. Play 109 первоначально подтверждён как available в existing Internal Testing; максимальный загруженный code — 109, выбран 110.

## Состав Android 109 против текущего source

**Android 109 уже содержит актуальные Android-функции.** Последующие четыре файла `6cb0413..6b4ab10` — только evidence; product source не изменялся. Повторная сборка 110 выполняется по поручению пользователя для синхронного тестового пакета платформ, а не как заявление об отсутствовавших функциях Android.

Проверенный main reference — `106f38c` (`origin/main`, подготовка iOS 110), включая `dbe2e8f`, `ea07491`, `0632884`:

- Xcode 27.1 actor isolation, iPhone orientations и SwiftUI ScaledMetric/Duo tests относятся к iOS. Swift/project/plist изменения не переносились в Android.
- Android Directory intro уже использует Compose wrap-content, гибкую ширину и минимальную (не фиксированную) высоту; Activity не закреплена в portrait. Draft/pane/revision уже используют rememberSaveable. Клиентских исправлений ради номера сборки не добавлено.
- `functions/src` runtime совпадает с проверенным main; отличается один integration test `organizationDeletionLifecycle.integration.test.ts`, не runtime contract. После `e5e7b15` релевантные shared изменения main относительно parity — только два `newsWaveAudit` operator helper/test из `d8d583a`; они не являются Android binary dependency. Другие старые отличия scripts/drafts/env не зеркалировались автоматически.
- Старая Android-копия в main не применялась поверх parity checkout. Все ранее доставленные Firebase authoritative catalog/cache, recent, banners/region, ссылки, lifecycle и audit исправления сохранены.

## Изменения для 110 и gate

Только `versionCode:109→110` и новый instrumentation regression `DirectoryDraftRestorationUiTest`. Новый тест проверяет ввод немецкого section body, уменьшение ширины 360→300dp, saved-state restoration, восстановление текста и исходной ревизии 7, отсутствие автоматической публикации, затем явный publish в изолированный spy с проверкой payload. Это Compose state restoration, не утверждение о физическом Duo/OS process kill.

- **2028/2028 JVM PASS**, failures/errors/skipped=0; финальный запуск после bump, `/tmp/uac-android-110-final-checks.log`.
- `lintLocalDebug` BUILD SUCCESSFUL: 0 errors, 100 warnings, 4 hints. Предупреждения не объявляются устранёнными.
- Финальный **21/21 instrumentation PASS**, API37, local APK **110**, 43,570 с. Новый draft restoration + CloudCatalog (4) + Recent (5) + Reader (3) + Editor (8); `/tmp/uac-android-110-ui-final.log`.
- **1/1 production Firebase SDK smoke PASS**, productionDebug APK **110**, 9,327 с, `/tmp/uac-android-110-sdk-live.log`. Реальный `FirebaseDirectoryCatalogSource`, marker/categories `Source.SERVER`: **25 категорий / 145 тем / 288 региональных блоков**, guestAuth=true; cold ViewModel/disk-cache round-trip и retry с отключённой SDK сетью сохранили полный authoritative каталог. Network включена обратно. [SDK evidence](live-sdk.json).
- Public production REST/Android parser/reader также повторно проверен в UI batch: [evidence](live-parser.json). Это отдельный transport от SDK smoke.
- Read-only public recent callable: HTTP200, `items:[]`, `nextCursor:null`, `hasMore:false`: [evidence](live-recent.json). Новых production публикаций тесты не создавали.

Временные устройства: local tests сначала `emulator-5586`, затем отдельный свежий `UAC_DirectoryCloudSDK_20261018`, `emulator-5588`. Перед финальным local batch на этом новом AVD удалён только установленный нами production instrumentation test APK: hardcoded photo provider authority двух test APK конфликтовал. Это harness install conflict, не release manifest/продуктовая ошибка. Production app/data не удалялись. На окончательном local APK110 весь batch повторён успешно.

## Границы

Backend/Rules не deploy-ились, production данные не изменялись. Аудитория Internal не расширялась; Closed Alpha и public production не входят в эту доставку. Physical Play install, полноценные Google/Apple/passkey/TOTP/private CRUD flows на телефоне и физический Duo не объявляются проверенными этим release gate.
