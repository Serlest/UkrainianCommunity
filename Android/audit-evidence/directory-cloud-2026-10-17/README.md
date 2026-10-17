# Android — Firebase как основной источник Довідника

17.10.2026. База `9d5dca7`, `codex/android-parity-1.2-107`. Bundled asset сохранён; production migration/backup и серверные Rules выполнены главным чатом отдельно.

## Контракт и поведение

Маркер `appConfig/directoryCatalog`: `schemaVersion:1`, `source:'firestore'`, `migrationComplete:true`, `baselineCategoryIDs`, `migratedAt:Timestamp`. Marker отделён от `directoryCategories`, поэтому старый клиент не пытается разобрать metadata как категорию.

- До подтверждения миграции сохранён legacy bootstrap: bundled + опубликованные overrides. После активации — только полный Firebase catalog, без подмешивания отсутствующих bundled IDs.
- Переключение допускается после server marker + следующего `Source.SERVER` query всех категорий либо при целиком присутствующем baseline/tombstones в валидном непредварительном SDK cache. Позднейшие удаления baseline допустимы: список baseline не требуется вечно, пустой подтверждённый серверный каталог остаётся пустым.
- Независимые marker/category listeners используют `MetadataChanges.INCLUDE`. Неполный SDK cache, pending writes и повреждённый документ не заменяют last-good full snapshot. Повторный server read защищён от отката более нового listener event. Скрытые категории/группы/темы/блоки фильтруются существующим reader; редактор получает полный актуальный cloud source, включая hidden entries.
- Полный принятый каталог хранится отдельным atomic offline envelope с привязкой project/package. Durable activation flag записывается раньше payload: потерянный/повреждённый cache после активации не возвращает bundle даже на холодном старте. До загрузки cache отсутствует flash устаревшего bundled каталога. Ошибка записи offline-копии отображается отдельно.
- Bundled разбирается лениво и не загружается reader-ом после authoritative activation. Файл не удалён и остаётся bootstrap/offline fallback для ещё не активированного клиента.
- Deep-link target сверяется с сервером. Отсутствующий authoritative document больше не возвращает bundled статью. Recent использует прежний публичный callable; никаких дат миграции для старых материалов клиент не создаёт.
- Retry при потере сети/недоступности marker сохраняет последнюю полную копию. Cache текущего пользователя не смешивается с другим Firebase project/flavor; каталог публичный и не зависит от UID.

## Проверки

- JVM: **2028 PASS**, 0 errors/failures/skipped; 9 новых DirectoryCloudCatalogTest покрывают bootstrap, обе очередности listeners, cached baseline/tombstones, последующие удаления/пустой полный сервер, partial cache/pending writes, malformed record, потерянный cache/sticky authority, hide/publication revisions и invalid marker.
- Local API37 instrumentation: **20/20 PASS**, 49,061 с: 4 новых DirectoryCloudCatalogDeviceTest, 5 Recent UI, 3 Reader UI, 8 Editor UI. Проверены disk round-trip/corruption/project isolation, offline retry, отсутствие bundle resurrection, current-source search/hidden/editor projection, региональные ссылки, CRUD confirmation/publication payload и recent.
- В этом наборе **реальный anonymous production REST GET** marker + categories прошёл через Android `DirectoryCatalog.parseCategory`, ViewModel и reader renderer: **25 категорий / 145 тем**. [REST evidence](live-parser.json), [снимок](live-parser.png). Это отдельно от Firebase SDK proof.
- **Production cloud Firebase SDK smoke: 1/1 PASS**, 7,822 с, отдельный свежий API37 AVD `UAC_DirectoryCloudSDK_20261017`, `emulator-5588`. Реальный `FirebaseDirectoryCatalogSource.confirmedCatalog()` использовал `Source.SERVER` для marker + category query; **25 категорий / 145 тем / 288 региональных блоков**, `guestAuth=true`. Затем: atomic disk write, SDK `disableNetwork()`, новый ViewModelStore/ViewModel/новый disk cache reader, retry offline — всё ещё authoritative 25/145. Network включена обратно в finally. Это cold ViewModel/disk round-trip, не отдельный OS process restart. [SDK evidence](live-sdk.json), [SDK renderer](live-sdk.png).
- SDK smoke собран в production cloud flavor с временно включённым диагностическим `productionDebug` через `-Puac.production.sdkSmoke=true`. По умолчанию остаются прежние три варианта; release не становится debug. Play Integrity provider сохранён, debug App Check token не регистрировался и enforcement не ослаблялся. На прежнем AVD production APK с другой подписью сохранён; для SDK smoke создан новый временный AVD.
- Lint localDebug: BUILD SUCCESSFUL, 0 errors; на момент до smoke test helper 100 warnings / 4 hints. Предупреждения не объявляются исправленными.
- Logs: `/tmp/uac-directory-cloud-build.log`, `/tmp/uac-directory-cloud-ui.log`, `/tmp/uac-directory-cloud-lint.log`, `/tmp/uac-directory-sdk-build.log`, `/tmp/uac-directory-sdk-live.log`.

## Границы

Android проверял production только на чтение. Новые production публикации, изменения пользователей, ролей, SDK App Check protections и правил этот клиентский тест не выполнял. Полный provider login/физическая Play install приёмка остаются отдельными проверками. Старые исторические audit/recent исправления `c2834f1` и `9d5dca7` входят в рабочую ветку.

## Финальная доставка — 1.2 (109)

**Google Play Internal Testing опубликован и доступен внутренним тестировщикам.** Прямое read-back из Console: `Für interne Tester verfügbar`, release `1.2 (109) – Internal`, versionCode **109**, существующий internal track `4701365572505552935`, release ID `10`; label Console: `17. Okt. 17:23`.

- [Ссылка тестировщика](https://play.google.com/apps/internaltest/4701365572505552935).
- [Release details в Console](https://play.google.com/console/u/0/developers/9121433135565744403/app/4976209024167699220/tracks/4701365572505552935/releases/10/details).
- [Публикационный receipt](play-109-receipt.json), [подтверждение Console](play-109-console.jpg).
- Аудитория сохранена: выбран прежний `UAC Internal Test`, 2 пользователя; список не редактировался. Closed Alpha и его группы не изменялись; ссылка закрытого Alpha сама по себе не доставляет эту Internal-сборку.
- Отдельный Android Publisher API не использовался. versionCode/track/status подтверждены по принятому Console artifact и живому опубликованному track; это UI read-back, не заявленный API response.

Сборка из source commit **`6cb0413`**: `productionRelease`, package `at.serlest.ukrainiancommunity`, version `1.2 (109)`, minSdk 26, targetSdk 36, upload certificate SHA-256 `c7f97bb4be68c85ead95a67d29356708874c3697a6ea69453f7837d83f7fefbe`. Явные Apple/passkey flags включены прежним release wrapper; local backend/debug App Check не включены. Signature APK проверена `apksigner verify`; R8 mapping находится в AAB и принят Play.

| Artifact | SHA-256 |
|---|---|
| `Android/app/build/outputs/bundle/productionRelease/app-production-release.aab` | `9e888f84e47da58b1128c94f0f684489f703aa76b3ffcb4045c5d74084e737f8` |
| `Android/app/build/outputs/apk/production/release/app-production-release.apk` | `22eb9e81018c46aed046123afc05abb50b4c4c95812815256fa7876b34830cf6` |

Final release BUILD SUCCESSFUL, 1 мин 49 с, `/tmp/uac-android-109-release.log`. Перед release повторены **2028/2028 JVM PASS** и `lintLocalDebug` (0 errors, 100 warnings, 4 hints), `/tmp/uac-android-109-final-checks.log`. Play: 0 errors, 1 неблокирующее предупреждение об отсутствии native debug symbols, потери поддерживаемых устройств нет. Physical Play install, живые Google/Apple/passkey/TOTP входы и полный private CRUD на устройстве не объявляются выполненными.

Отдельный production read-only callable `getDirectoryRecentAdditions` после миграции ответил HTTP 200: `items:[]`, `nextCursor:null`, `hasMore:false`. [Evidence](live-recent-read.json). Миграция не создала ложной истории «новых» старых материалов.

## Синхронизация shared Directory source

Без merge всей main перенесены **22 server/rules/scripts файла** из зафиксированных blobs: `a369d58` (migration/recent), `a40367e` (timestamp verification script), `2af7c31` (restricted automation bridge/helper), `da9d141` (read-only registry script). Dirty/uncommitted файлы main не копировались, iOS не редактировался. Canonical rules path в этом Git index/config — `Firebase/firestore.rules`.

Локальные commits: **`cb90996`** — authoritative Android/catalog/cache + live evidence; **`5090f10`** — согласованный Directory backend; **`cc6f06c`** — registry script; **`926f607`** — marker read rule; **`6cb0413`** — version 109/diagnostic smoke build helper. Проверено побайтовое соответствие выбранным main blobs. Functions TypeScript build PASS; 12 selected recent-model/automation-policy/evidence unit tests PASS. Deployment shared функций/Rules из Android checkout не выполнялся; live gate automation не включался.

Диагностический SDK smoke воспроизводится `node Android/scripts/build-production-sdk-smoke.mjs`, затем запуском `DirectoryCloudSdkReadTest` на отдельном AVD с productionDebug APK/test APK. Это build-only opt-in, не Store artifact. Созданный временный SDK AVD остановлен и удалён после сохранения evidence.
