# Повторный аудит Android — 17 октября 2026

## Область и исходное состояние

- Android: `/Users/serlest/Developer/UAC-Android-1.2-Parity107`, `codex/android-parity-1.2-107`, исходный коммит `29525ba`; рабочее дерево перед аудитом чистое.
- Apple-эталон прочитан из `/Users/serlest/Developer/UkrainianCommunity`, `main`, исходный HEAD `3e87aaf`. Его незакоммиченные project/localization изменения сохранены. iOS не редактировался и не запускался в этом аудите.
- У пользователя установлен Play **1.2 (108)**. Предыдущие исправления `b2e34d1` и `29525ba`, а также этот аудит пока не доставлены новой Play-сборкой. Метаданные версии оставлены 1.2 (108) для диагностической сборки; следующей загрузке потребуется новый versionCode.
- Охвачены пять вкладок, 36 именованных маршрутов профиля и параметризованные семейства маршрутов, настройки, контент/редакторы, роли, транспорт, кеш и сборочная конфигурация.
- Проверки выполнялись на отдельно запущенном `UAC_Step8_API37_Fresh`, API 37, `emulator-5586`. Существующий emulator-5582 не использовался. Изменения разрешены только в Android и этом отчёте; shared Firebase/source согласуются главным чатом отдельно.

**Значение результата:** проведён обзор перечисленных областей, выполнены указанные тесты и исправлены установленные Android-дефекты. Это не означает, что каждый маршрут был пройден с настоящим аккаунтом, каждым провайдером и на физическом телефоне.

## Подтверждённые конфликты и исправления

| ID / приоритет | Причина и воспроизведение | Исправление / доказательство |
|---|---|---|
| A01 — P1 | Удаление статьи/подраздела Directory считало скрытые альтернативы достаточными. Можно было удалить последний видимый материал и получить непубликуемую черновую категорию. Удаление также происходило без подтверждения, в отличие от iOS. | Проверка оставшейся видимой статьи в видимой группе; подтверждение/отмена с захваченным ID и повторной проверкой перед изменением. Три новых UI-сценария: группа, статья, скрытая альтернатива. Публикация проверяется через подставной доступ делегированного редактора и повторный разбор payload. |
| A02 — P2 | Owner decoder баннера отбрасывал неизвестные placements/localizations, а неверные типы и длинный необязательный текст заменял значениями по умолчанию без `repairRequired`. Повреждённая запись могла выглядеть исправной. | Чистый decoder проверяет полную форму документа, типы, placements и валидность итогового draft. Неподдерживаемые/повреждённые значения помечаются для явного ремонта; включение такого баннера остаётся запрещено. Unit-тесты проверяют реальные четыре placements и восемь повреждённых форм. |
| A03 — P2 | `result.copy(donation = optional(...))` захватывал старый receiver до изменения warnings/cachedAt внутри optional. Отказ чтения или offline-происхождение карточки поддержки терялись. | Результат optional сначала сохраняется отдельно, затем копируется в актуальное состояние. Тесты DENIED и повторного чтения offline-кеша. Остальные optional-вызовы просмотрены. |
| A04 — P1 | Редактор, iOS и backend разрешают HTTP browser action баннера, но публичная валидация и SafeLink требовали HTTPS. Такой баннер исчезал либо не имел кнопки. | Отдельная browser-policy для banner action применяется при проверке и в UI. HTTP-адрес доходит до явного подтверждения открытия. Политики медиа, donation и inbox не расширены. |
| A05 — P2 | Directory отклонял допустимый HTTPS-источник с портом 8443 и не показывал ссылку: и canonicalSourceUrl, и reader использовали общую политику только порта 443. | Отдельная HTTPS-policy источников допускает корректный порт, сохраняет запрет credentials/опасных схем/управляющих символов. Проверены нормализация, reader и диалог открытия. |
| A06 — P1 | Ключ raw page cache не включал обычную news category, сортировку и календарные границы. Offline-запрос мог получить данные другого запроса, неправильный порядок или ложную пустоту. | Версионированный ключ включает серверные условия, orderField/direction и фактические start/end границы новостей. Future-event cache хранит нижнюю границу исходного запроса: при продвижении времени разрешён безопасный raw superset, при движении назад требуется сервер. Проверены разные сортировки, категории, дни, продвижение времени и disk round-trip метаданных. |
| A07 — P1 | Главный чат проверил deployed push source: старый server envelope не задаёт clickAction. Android принимал только `at.uac.android.PUSH_TAP`, поэтому стандартный launcher tap такого уведомления игнорировался. | Совместимый приём ACTION_MAIN + CATEGORY_LAUNCHER только с FCM delivery marker, без URI, с ограниченными типами/размером extras, обязательным notificationId и прежним route allowlist. Это только очередь маршрута; существующие UID/auth/app-lock gates хоста не сняты. Native Intent contract-тесты проверяют допустимый legacy payload, повторы, гостя и враждебные варианты. Реальная доставка FCM здесь не проверена. |
| A08 — P2 | Lifecycle UI-тест воспроизвёл потерю позиции чтения после ON_PAUSE/RESUME: revalidation очищала данные, LazyColumn сжимался и забывал положение. | Сохранены ключ первого видимого элемента и offset, затем восстановлены после получения новой структуры списка; fallback index при исчезнувшем ключе. Query identity включает navigationEpoch, поэтому позиция не переносится между аккаунтами/фильтрами. Проверка разрешений и очистка публичных данных при паузе сохранены. Тест добавляет новость во время паузы и проверяет положение прежней карточки после reload. |
| A09 — P2 | Foundation принимает Unicode hostname, а Java URI возвращает host=null для `https://bücher.example/path`. Нормальный источник из iOS нельзя было сохранить/открыть в Android. | Directory canonicalSourceUrl нормализует только hostname через IDNA/punycode, сохраняя проверки credentials/порта/пути. Reader передаёт в SafeLink уже канонический адрес. Unit и UI покрывают `https://bücher.example:8443/path`, небезопасные варианты остаются запрещены. Общая media-policy не расширена. |

Предыдущие три причины из `29525ba` — отклонение `directory` placement, несвязанные profile/public region и `plain` background профиля — повторно включены в регрессионную проверку. Их production read-only snapshot и снимки находятся в [предыдущем отчёте](AndroidRegionBannerProfileFix-2026-10-17.md).

## Матрица фактической проверки

`Код` означает чтение реализации/контрактов; `JVM` — локальные автоматические проверки; `UI` — сценарии с изолированными данными на API 37. UI с fake source не является серверной публикацией.

| Область | Что реально проверено | Что не подтверждено этим аудитом |
|---|---|---|
| Навигация и доступность | BrowseNavigation: пять независимых стеков, 36 profile roots, параметризованные маршруты, очистка private history при смене UID; JVM navigation/app-link tests; UI controls/labels/confirmation/busy states в выбранных семействах. | Ручной TalkBack и все accessibility gestures на физическом телефоне; вручную не открывался каждый private route. |
| Вход и аккаунты | Код Auth gate, verified/legal/MFA readiness, session revision; JVM Auth/Passkey/AppLock/AccountStatus; чтение guest UI и механизма очистки credentials. AuthUiTest в этом запуске отдельно не выполнялся. | Новые живые Google/Apple/passkey/TOTP входы, получение писем, OEM credential manager/биометрия. |
| Профиль, язык, тема, регион | JVM personal editor/session masking и region bootstrap/manual/account switch; PersonalUi account isolation; DE/UK, light/dark, четыре публичных корня и фон профиля/настроек; отдельный cold-process guest-region test из предыдущего исправления. | Сохранение реального production-профиля и физический avatar picker в этом запуске. |
| Баннеры и ссылки | Production-shaped four placements, schedule/region/order validation, image/CTA layouts, owner role/repair/payload tests; HTTP action и Directory HTTPS:8443 до подтверждения; loaded local JPEG regression. | Новый owner upload в production и реальная FCM/analytics attribution. Внешний сайт из теста не открывался. |
| Новости | Query/order/category/date/search/pagination/cache JVM, периодические окна Europe/Vienna, JVM navigation/back contracts; BrowseUiTest в этом запуске отдельно не выполнялся. A06 устраняет offline collision. | Все текущие production-записи и все combinations фильтров на живом сервере. |
| События | Recurrences, cancellation, upcoming/past/age/audience, timezone и pagination JVM; authoring/registration controls/UI, list accessibility. | Реальная оплата/внешняя регистрация, push reminder на физическом устройстве. |
| Организации | Create/edit/request/roles/website contract JVM; seven representative UI scenarios, owner/stale/consent cases, public gallery и profile media. | Production-заявка/модерация/удаление реальной организации и всех её зависимостей. |
| Довідник | Source comparison с текущим iOS exporter, bundled sources/reader/search/regions, owner/delegated grants и editor/translation UI; ordinary/regional/group/topic deletion и publish payload checks. | Новая staging-публикация под живым делегированным аккаунтом; предыдущий результат staging не объявляется повторно выполненным. |
| Создание/редактирование/удаление | Authoring/Publication/Lifecycle JVM и representative UI: consent, explicit confirm, stale revision, pending/unknown outcome, no blind retry. | Полный cloud round-trip для каждого типа destructive operation. |
| Роли и смена аккаунта | Repository authority checks, same SDK Auth binding, no cross-app Firebase handles; owner/editor/ordinary/guest/stale fixtures и Firestore Rules. | Отдельный live identity test для каждой роли и каждого endpoint. |
| Личные действия/сообщество | JVM bookmarks/likes/comments/subscription/RSVP/attendees/subscribers/session masking; UI регистрации из component batch. Community/Attendees/Subscribers UI в этом запуске отдельно не выполнялись. | Живой полный двухаккаунтный social workflow. |
| Обращения, inbox, DSA | UI + JVM reason/declaration/confirmation, clearing, search/cursors, account mask, owner decisions, unavailable/unknown errors, DSA read/review contracts. | Новое настоящее обращение/DSA-решение, письмо или push пользователю. |
| Legal и owner tools | JVM/representative UI legal drafts/publish/evidence, content planning, donation settings, privileged access. | Публикация новых правовых документов, live owner analytics aggregation. Shared legal/server divergence ведёт Apple/root отдельно. |
| Медиа и Storage | Media URL/type/size/cache/picker policies JVM, cover/profile/gallery UI, Storage Rules на паре локальных эмуляторов с одинаковым projectId. | Реальная камера/OEM photo picker, live upload/download с production App Check. |
| Offline и lifecycle | Cache TTL, DENIED/MISSING purge, cancellation, scheduled candidates, region filtering и A06; A08 temporary pause/resume без снятия permission revalidation. | Длительные сетевые переходы на физическом телефоне и OEM process killing. |
| Deep links и push | Custom-scheme allowlist, unknown/hostile URLs, auth gating, pending/restore JVM; native default-launch legacy tap parsing, expiry/ownership contracts. | HTTPS Android App Links не заявлены реализованными: manifest использует custom scheme. Не проверены end-to-end FCM delivery и system tray tap на физическом Play install. |
| Firebase contracts | 25 literal callable names найдены в shared functions source; динамические имена проверяются contract-тестами соответствующих модулей, а не этим поиском. Локальные Rules suites проверяют public/private/role/storage boundaries. | Это не проверка всех deployed hashes/индексов/endpoints; operator REST read не является app-auth/App Check proof. |
| Flavors и release | Только localDebug/stagingDebug/productionRelease; production package/shared project, no debug App Check, Google config validation, explicit Apple/passkey flags, signed R8 APK/AAB и vital lint. | Установка финального artifact через Play, физический smoke и новая загрузка. |

## Выполненные наборы и evidence

- JVM: результаты и окончательный счёт — в итоговой записи ниже; XML: `Android/app/build/test-results/testLocalDebugUnitTest/`.
- Component UI batch: **128/128 PASS**, 23 класса, API 37. Log: `/tmp/uac-full-audit-component-ui.log`. Включены DirectoryEditor/Reader/Editors/Translation, Personal, Organization, Authoring/Publication, FeaturedManagement, Safety, Inbox/FeedbackInbox, LegalManagement, ContentPlanning, DonationSettings, Registrations, DSA, ContentLifecycle/Cover, ProfileMedia/PublicGallery.
- Эти 128 тестов выполнены после A01–A03; A04–A09 дополнительно проверяются финальными целевыми тестами, JVM и новой сборкой.
- Firestore/Storage первый общий запуск: **114 tests: 101 PASS / 13 FAIL**, все отказы в Storage positive scenarios. Причина проверена: сервер запущен как `demo-uac-android`, а storage fixture/Firestore documents создавались как `demo-ukrainian-community-rules` при singleProjectMode. Правила не ослаблялись.
- Изолированный повтор Storage + Firestore с одинаковым `demo-ukrainian-community-rules`, портами 18088/19198: **21/21 PASS**. Log: `/tmp/uac-full-audit-storage-isolated.log`. Проекты/порты остального тестирования не останавливались ради этого повтора.
- Финальная диагностическая productionRelease сборка после A01–A09 завершена без загрузки; hashes приведены ниже.

## Неизменённые границы

- Production данные, пользователи, индексы, правила и конфигурация не изменялись. Публикации, сообщения людям, пуши и магазинные загрузки не выполнялись.
- Приём старого launcher push intent не является доверенным подтверждением отправителя. Payload проходит ограниченный parser; просмотр private destination всё ещё требует текущую сессию и серверные права. Обновление shared server clickAction ведётся главным чатом отдельно.
- Наличие экрана и PASS на fake repository не заменяют реальную серверную запись. Непроверенные cloud/device сценарии перечислены в матрице и остаются отдельной приёмкой.
- Следующий release должен включать код начиная с `b2e34d1`/`29525ba` и этого аудита, получить новый versionCode и пройти установку из Play тестировщиком.

## Итоговая запись

Подтверждённые Android-дефекты A01–A09 исправлены. Проверка исходников завершена в указанном объёме; live cloud/provider и физическая приёмка остаются открытыми и не объявляются выполненными.

- Финальный JVM: **2011/2011 PASS**, 0 failures, 0 errors, 0 skipped; счёт получен суммированием XML `testLocalDebugUnitTest`.
- Финальный целевой API 37 batch: **15/15 PASS**, 93,493 секунды. DirectoryEditor (8), external-link confirmation (1), disk-cache metadata (1), native push Intent (2), pause/resume reading anchor (2), region/banner/profile regression (1). Log: `/tmp/uac-full-audit-targeted-ui-final.log`.
- Ранее component batch: **128/128 PASS**. Целевой batch частично повторяет DirectoryEditor и не суммируется с ним как число уникальных тестов.
- Первый целевой запуск: 14 тестов, 3 отказа. Исправлены реальный A08, неверный callback теста внешней ссылки (onNavigate вместо onTap), восстановлен остановившийся fixture Storage на 9198. Финальный повтор выполнен после исправлений; история отказов сохранена в `/tmp/uac-full-audit-targeted-ui.log`.
- Rules: **93 Firestore + 21 Storage = 114 уникальных PASS** после исправления тестовой топологии; начальные 13 Storage отказов раскрыты выше.
- `testLocalDebugUnitTest`, `assembleLocalDebug`, `assembleLocalDebugAndroidTest`: BUILD SUCCESSFUL; `/tmp/uac-full-audit-final-build.log`.
- `lintLocalDebug`: **BUILD SUCCESSFUL**, 0 errors, 98 warnings, 3 hints (XML). Предупреждения не объявляются устранёнными; среди них dependencies/SDK, resources, Credential Manager suggestions, manifest и UI/API style. Log: `/tmp/uac-full-audit-lint-final.log`; отчёты `Android/app/build/reports/lint-results-localDebug.{xml,html,txt}`.
- Final productionRelease: **BUILD SUCCESSFUL**, 2 мин 12 с; `/tmp/uac-full-audit-release-final.log`. APK signature проверена `apksigner verify`; package `at.serlest.ukrainiancommunity`, version `1.2 (108)`, minSdk 26, targetSdk 36. Release создавался с явными Apple/passkey flags, без local backend/debug App Check.
- Текущий iOS Directory экспортирован Foundation exporter без изменения iOS; bundled JSON совпал побайтно: **25 категорий / 145 статей**. Экспорт `/tmp/uac-full-audit-ios-directory.json`.

Финальные диагностические artifacts:

| Artifact | SHA-256 |
|---|---|
| `Android/app/build/outputs/bundle/productionRelease/app-production-release.aab` | `7538a807b9430b6ae4a7cbd7a9c64162ffe04f6705e62490ef559f1a9925372c` |
| `Android/app/build/outputs/apk/production/release/app-production-release.apk` | `7936b0a616a537961be7355ae9a05de92cde6fe728b362505c888be4e33eeef4` |

Эти artifacts не загружены в магазин. Play 108 не содержит этот пакет исправлений. Перед следующей доставкой нужен новый versionCode и согласованное включение shared изменений Apple/main; shared commits `36a511a` / `eeae33e` сообщены главным чатом как pushed, но здесь не сливались и новый server deploy не выполнялся.

Оставшаяся приёмка: настоящий вход Google/Apple/passkey/TOTP; защищённые cloud CRUD под реальными ролями и двумя аккаунтами; production App Check/Storage; FCM доставка и системное открытие; камера/биометрия/TalkBack/OEM lifecycle на физическом Android; установка следующей версии из Play. Это ограничения доказательств, а не утверждение об идеальной работе всего приложения.
