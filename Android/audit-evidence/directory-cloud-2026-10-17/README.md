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
