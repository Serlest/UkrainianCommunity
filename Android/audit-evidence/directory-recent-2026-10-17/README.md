# Android Directory — «Останнє додане» / «Zuletzt hinzugefügt»

Дата: 17.10.2026. База: `c2834f1`, ветка `codex/android-parity-1.2-107`. Изменения ограничены `Android/`; shared Functions/Rules и Apple здесь не редактировались.

## Реализация

- Самостоятельные записи ленты находятся на главном экране Directory **после Safety и перед Start**. Это одна лента всех тем/федеральных земель, без применения глобального фильтра. Новая iOS реализация просмотрена read-only для сверки размещения и назначения.
- Публичный `getDirectoryRecentAdditions`, `europe-west3`, `{limit:20,cursor:null|{seconds,nanoseconds,id}}`, используется через существующий AppBackend/CallableGateway. Отдельные Firebase-проекты, учетные записи или коллекции клиент не создает. Запрос только читает.
- Response проверяется до показа: kind/ID/slug/region, nullable section, revision, ISO publishedAt, DE/UK заголовки, дубликаты, календарный порядок и продвижение cursor. Курсор сохраняет наносекунды. В текущем backend `publishedAt` сериализован до миллисекунд; при одинаковой отображаемой миллисекунде клиент сохраняет серверный порядок и не пересортировывает ID.
- Только дата из ответа, без присвоения bundled материалам исторических дат. Начальное пустое состояние отличается от ошибки. Loading/error/retry/refresh/load-more работают отдельно; повтор не теряет первую страницу. Пустой scan page с `hasMore` не объявляется окончательно пустой историей.
- Карточка показывает тип, локализованный регион/всю Австрию, заголовок, категорию и (для блока) тему, дату Europe/Vienna. Длинные названия ограничены тремя строками и открывают полный текущий материал по нажатию.
- Переход ведёт в текущую исходную тему. Cloud reader запрашивает категорию с `Source.SERVER`, повторно проверяет видимость категории/группы/темы/блока и один раз прокручивает к section anchor. Последующие обновления каталога не возвращают читателя принудительно к началу блока. Исчезнувший/скрытый блок показывает notice, сетевой отказ — retry. Историческое тело из ленты не используется.
- Региональная ссылка использует локальное состояние reader: выбор и дальнейшая смена региона в таком reader не меняют общий фильтр. Для ссылки на обычный блок начальный регион — вся Австрия.
- Public deep links: `ukrainiancommunity://directory/recent`, `ukrainiancommunity://directory/<category>/<topic>?section=<section>&region=<region>`. Принимаются только известные параметры и slug/region allowlist. `directory/manage`, произвольные private routes, traversal, encoded path, повторные/посторонние параметры, fragment и credentials отклоняются. Pending destination проходит ту же проверку после восстановления процесса. Остальные app-link/auth gates сохранены.

## Проверка

- JVM **2019/2019 PASS**, 0 errors/failures/skipped. Включены 8 новых `DirectoryRecentTest`: callable/cursor wire, mixed feed, millisecond/nanosecond precision, invalid response, safe/restored links, initial error/retry/pagination/refresh/empty, visibility, empty scan continuation.
- Local debug APK и instrumentation APK собраны. Финальный UI batch **8/8 PASS**, API 37, отдельный `UAC_Step8_API37_Fresh`, serial `emulator-5586`, 11,612 с: 5 новых DirectoryRecent UI + 3 существующих DirectoryReader UI.
- Проверено: loading/error/retry/load-more/refresh, DE/light, UK/dark, пустое состояние без дат, реальные строки ленты на root между Safety/Start (test source), региональный anchor и локальная смена региона, исчезнувший anchor, существующие bundled статьи/search/region.
- `lintLocalDebug`: BUILD SUCCESSFUL, 0 errors, 99 warnings, 4 hints; оставшиеся предупреждения не объявляются устранёнными.
- Manifest resolver на установленном local APK вернул `at.uac.android.local/at.uac.android.MainActivity` для `ukrainiancommunity://directory/recent`.
- Снимки ниже сделаны инструментальными тестами с явно синтетической записью «Neue Hilfe» / «Нова допомога» и датой fixture. Это UI evidence, не production публикация. Существующие Safety/Directory материалы прочитаны из reviewed bundle. После просмотра исправлен белый фон оболочки dark-теста; финальный dark screenshot проверен повторно.
- Logs: `/tmp/uac-directory-recent-build-final.log`, `/tmp/uac-directory-recent-ui-final.log`. XML: `Android/app/build/test-results/testLocalDebugUnitTest/`.

## Диагностическая production сборка

Финальный signed R8 APK/AAB: **BUILD SUCCESSFUL**, 1 мин 36 с; log `/tmp/uac-directory-recent-release-final.log`. Подпись APK проверена `apksigner verify`; package `at.serlest.ukrainiancommunity`, version `1.2 (108)`, minSdk 26, targetSdk 36. Использован существующий Keychain wrapper и прежние explicit Apple/passkey flags; secrets не выводились. Прямой production compile без environment был отклонён штатным configuration gate, после чего сборка выполнена wrapper-ом. Загрузки в Play не было.

| Artifact | SHA-256 |
|---|---|
| productionRelease AAB | `e5f72aadd646ecab27b80c92c0549bd1f4858f22bbcd6c2e7334c3340027ec4d` |
| productionRelease APK | `70bc5063341ead7d9416b704c2aa89486a5b51029011706ba161366520695084` |

## Ограничения и доставка

- Реальный callable round-trip с новым backend и новая cloud публикация в этом Android запуске не выполнялись: backend разрабатывается главным чатом отдельно. UI/source tests не заменяют серверный интеграционный тест. Доступность production callable здесь не объявляется подтвержденной.
- Новый reader server-refresh работает в cloud flavors; local flavor сохраняет существующий bundled fixture reader. Поэтому API 37 UI проверяет клиентскую навигацию/видимость/anchor с изолированными данными, а не App Check или production Firestore.
- Transport принимает public read без собственного требования авторизованного UID; существующие общие startup/auth/app-lock gates приложения не менялись. Public classification ссылки не обходит эти gates.
- Version остается `1.2 (108)`; в Play новый код не загружался. Следующая загрузка требует нового versionCode. Физический телефон, Play install и end-to-end cloud приемка остаются отдельными шагами.

## Снимки

- [Root: Safety → recent feed → Start](directory-recent-root-placement.png)
- [DE / light](directory-recent-de-light.png)
- [UK / dark](directory-recent-uk-dark.png)
- [Локальная смена региона в reader](directory-recent-region-anchor.png)
