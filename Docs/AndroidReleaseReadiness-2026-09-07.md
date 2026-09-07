# Android release readiness — 2026-09-07

Эталон продукта — iOS TestFlight **1.0.2 (build 68) = 100%**. Здесь разделены две оценки, чтобы зелёные локальные тесты не выдавать за готовность Google Play.

## Итоговая оценка

- **Функциональный паритет Android: 90%.** Основные гостевые, пользовательские, организационные и owner/admin сценарии build 68 перенесены, включая A01–A12, gallery build-68 contract, presence, FCM и двухъязычный интерфейс.
- **Готовность к выпуску: 78%.** Локальный release snapshot собран и проверен, но выпуск блокируют юридическая синхронизация, реальные cloud/device сценарии и настройка Play Console.

Это не разрешение на публикацию. Production Firebase, iOS и Google Play не изменялись.

## Состояние функций

| Область | Реализовано в Android | До публикации |
| --- | --- | --- |
| A01 — модерация | Content/organization review, role/MFA gates, recovery | Реальный privileged TOTP + cloud read-back |
| A02 — статусы пользователей | Поиск, security metadata, 5 status actions, self/owner guards | Cloud side-effects и audit read-back |
| A03 — platform roles | Назначение/снятие admin, owner/self protection, journal | Проверка custom claims после TOTP-вызова |
| A04 — support inbox | Reply/close/delete, фильтры, bounded recovery | Cloud delete/read-back; global clear вне готового scope |
| A05 — DSA | Statement, case context, system messages, read-only review | Appeal submission/reviewer decisions требуют серверных version/idempotency/receipt гарантий |
| A06 — legal/org access | Legal evidence paging, organization access/update, consent V2 | Cloud completeness и privileged receipts |
| A07 — featured | Create/edit/media/activate/sort/delete, DE/UK UI | Cloud media/callable read-back |
| A08 — content planning | Drafts, attention, scheduled/history, editor lease/finalize/fail | Реальный multi-client lease proof |
| A09 — analytics | Consent V2, event tracking/dedupe, owner reports/details | Production-like event/read-back validation |
| A10 — presence | Cloud heartbeat, sequence and lease, logout/offline cleanup | Multi-account timing proof на реальных устройствах |
| A11 — system logs | List/filter/detail/review/delete/clear/metrics, sanitization | Privileged cloud retention/read-back |
| A12 — push | FCM registration ownership, preferences, inbox sync, routes, foreground/background/cold handling | Реальная доставка FCM и owner test-push на физическом устройстве |

## Сборки и финальные receipts

| Проверка | Результат текущего frozen snapshot |
| --- | --- |
| Unit | **1901/1901 PASS**, 108 suites, 0 failures/errors/skips |
| Lint | **PASS**, 0 errors (warnings не являются блокером этого snapshot) |
| Functions Android push | **7/7 PASS** для изолированного notification-модуля |
| API 37 component matrix, font 200% | **316/316 PASS** |
| API 26 component matrix, font 200% | **316/316 PASS** |
| API 37 Main journey matrix, font 100% | **38/38 PASS** |
| API 26 Main journey matrix, font 200% | **38/38 PASS** |
| Local debug APK | `b3a168f0c9e498f7668cc79d94138aa66463fbedabfd0ccb2ccfa34d3bbd5b75` |
| Staging debug APK | Fresh build/install/cold start в cloud mode; `9f57a8b6dceae53681d7b2b355eb30de9669bd20d45f7a6627a8c69e6c770d2f` |
| Production AAB | Signed/R8/lintVital **PASS**; package `at.serlest.ukrainiancommunity`, version `1.0.2 (1)`; `532ad36439eed294b2a7e743f427198827f19e263fcf430d1e3f1264835176b1` |

Матрицы instrumentation запускаются раздельно, потому что в репозитории есть намеренно взаимоисключающие runner modes (offline/online/multiphase/opt-in). Недифференцированный запуск всех классов не является валидной release-проверкой.

## Визуальный аудит

Публичные Home/Events/Organizations приведены к иерархии build 68: header → hero/banner → компактные фильтры → лента. Баннер поддерживает swipe, dots, auto-advance и TalkBack; добавлены pull-to-refresh, quick filters, modal search/filter, DE/UK и large-text сценарии. Исправлен найденный staging-дефект: отсутствие необязательного `appConfig/donation` больше не показывает ложное предупреждение «содержимое недоступно».

Локальный API37 screenshot подтверждает композицию и читаемость. До публикации всё ещё нужны side-by-side iOS build 68 ↔ Android на физическом устройстве для guest/signed-in/owner, light/dark, DE/UK, font 100/200%, а также ручной TalkBack-аудит. Android-компоненты не обязаны копировать системные iOS controls, но сохраняют продуктовую иерархию и расположение ключевых блоков.

## Безопасность и границы

- `localDebug` — только `at.uac.android.local`, без Firebase default provider и FCM.
- `stagingDebug` — `at.serlest.ukrainiancommunity.staging` и отдельный project `uac-android-test-20260903`; App Check debug token зарегистрирован только там.
- `productionRelease` — `at.serlest.ukrainiancommunity`, Play Integrity provider, cleartext запрещён, R8 включён, Firebase messaging auto-init управляется приложением.
- Upload key хранится вне репозитория в `/Users/serlest/Library/Application Support/UAC/AndroidSigning/`; требуется независимая защищённая резервная копия.
- Android push изменяет только Android `clickAction`; полный Functions TypeScript build и notification-тесты проходят, но Functions deploy не выполнялся.
- iOS/Swift/Xcode, Firestore Rules, Storage Rules и production data не менялись этой Android-подготовкой.

## Обязательные блокеры до release candidate

1. Утвердить и опубликовать новую версию Privacy/Terms для iOS + Android: Android/BiometricPrompt, FCM/Firebase Installation ID, Play Integrity и фактический presence contract **heartbeat 90 s / lease 180 s**. Нельзя молча переписывать опубликованную iOS-версию 2026.12.
2. Авторизованно развернуть и прочитать обратно `/delete-account`, обновлённый `/support` и юридические страницы; проверить обслуживаемый email-процесс удаления. Исходники страниц подготовлены, deployment не выполнялся.
3. На физическом Android пройти staging/production-like Auth verify/reset, TOTP, App Check/Play Integrity, FCM foreground/background/cold, Storage/gallery, callables/account deletion и exact read-back.
4. Проверить 16 KB page-size runtime на совместимом устройстве/AVD. Статический audit прошёл: AGP 9.0.1, ELF LOAD alignment `2**14`, RELRO и ZIP alignment 16 KB.
5. Настроить Play Console: package ownership, Play App Signing/upload certificate, internal track, Data Safety, UGC/news declarations, content rating, target audience, reviewer accounts/TOTP и store listing.
6. Подготовить финальные store assets: 512×512 icon, 1024×500 feature graphic, чистые DE/UK screenshots телефона без тестовых данных.
7. Либо разместить HTTPS `assetlinks.json` и доказать verified App Links, либо явно оставить strict custom scheme в первом релизе.
8. Закрыть серверный CAS/version contract там, где owner-management операция требует `expectedVersion`; клиент не должен маскировать отсутствие серверной гарантии.

## Решение по выпуску

**Локальный код и подписанный AAB готовы к следующему release gate, но отправлять в Play пока нельзя.** Следующий допустимый этап — юридическое обновление + test-cloud/physical-device preflight + Play Console internal testing. Upload, production deploy и public rollout остаются отдельными действиями.
