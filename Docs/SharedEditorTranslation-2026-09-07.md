# Единый перевод редакторов и стиль оповещений

Рабочая копия: `/Users/serlest/Developer/UACAnnouncements-20260907`, ветка `codex/user-announcements-20260907`. Доработка по прямому поручению пользователя от 2026-09-07. Финальная 1.0.3 (72) доступна во внутреннем TestFlight: VALID / IN_BETA_TESTING, подтверждено Apple 2026-09-07 11:43 Europe/Vienna. What to Test uk/de-DE записаны и проверены. Commit реализации — `e7575d2`; 71 — промежуточная сборка.

## Поведение

Оповещения используют существующие `ProfileDestinationLayout`, `EditorScreenShell`, `AppEditorSectionCard`, `EditorTextField`, `EditorTextArea` и `appActionButtonStyle`. Общий стиль применён к списку владельца, редактору, предпросмотру, выбору пользователей, всплывающему окну и истории.

Один `ContentTranslationButton` открывает редактируемый перевод. Результат применяется только явным действием. Если перевод заменяет заполненные поля, в окне проверки нужен отдельный переключатель подтверждения; до этого применение недоступно. Это исключает вложенный диалог подтверждения. Отмена не меняет текст. Исходный язык сохраняется; пустые исходные поля не стирают существующий перевод. Применение отклоняется после изменения исходника, целевого текста или аккаунта. Лимиты проверяются перед применением. Сохранение и публикация выполняются прежними редакторами с прежними правами.

| Редактор | Поля |
| --- | --- |
| Оповещение | Заголовок, сообщение; uk→de и прежний de→uk, по выбранной вкладке исходного языка |
| Новость | Заголовок, краткое описание, полный текст; кнопка после полного текста |
| Событие | Заголовок, краткое описание, подробности |
| Организация, основные данные | Название, краткое описание, миссия, полное описание |
| Организация, дополнительные данные | Территория услуг, услуги, особые часы, название и описание предложения |
| Баннер | Заголовок, подзаголовок |
| Поддержка проекта | Заголовок, текст, надпись кнопки |
| Документы | Заголовок и Markdown черновика |

Планировщик открывает те же редакторы новостей/событий. Адреса, URL, контакты, даты и категории не переводятся. Комментарии, обращения и другие формы с единственным языком сохраняют исходное поведение; об их отдельном переводе задано уточнение. В этой итерации охвачены все существующие двуязычные редакторы. Android UI не менялся.

## Общий API для iOS и будущего Android

Callable `translateContent`, регион `europe-west3`. Запрос: `{kind, texts, source?}`; ответ: `{texts}` в том же порядке. `source` по умолчанию `uk`, поэтому запросы build 71 совместимы; `de` разрешён только для owner-only `announcement`. Поддерживаемые kind: news/event/organization/banner/donation/legal/announcement. Прежний `manageAnnouncements:translate` сохранён для build 70 и использует общий provider `translateTexts`.

Нужны App Check, активный подтверждённый аккаунт и существующая MFA-политика. Для banner/donation/legal/announcement нужен owner. Права публикации перевод не меняет.

Ввод: 1–12 непустых полей, до 20 000 символов на поле и 25 000 на запрос. Новый endpoint ограничен 40 запросами / 150 000 символами на пользователя в сутки, минимум 3 секунды между запросами, суммарно 1 000 000 символов в сутки. Хранятся только счётчики: `users/{uid}/privateTranslationLimits/daily` удаляется существующим каскадным удалением аккаунта; общий `contentTranslationLimits/_daily` не содержит идентификаторов пользователей. Исходники и переводы в Firestore/логи не записываются. Ручной ввод остаётся доступен при ошибке или лимите.

## Проверки и артефакты

- 426 Swift tests / 44 suites PASS (`translation72-regression.log`). Отдельные SDK/OS тесты требуют opt-in, как в отчёте build 70.
- 14 backend/Rules tests PASS, 0 FAIL, 0 SKIP (`translation-backend72-tests.log`): контракт, оба направления, owner/verified/MFA, лимиты, сбой provider, отсутствие текста в счётчиках, запрет прямого доступа guest/user/admin/owner.
- UI guest popup/history и event preview PASS; news uk→de → ручная правка → применение → проверка немецкого поля → предпросмотр PASS. Owner reverse/подтверждение/сохранение/предпросмотр/публикация PASS (`translation72-owner-final.log`). Для новости финальная проверка — `translation72-inline-tests.log`; ожидаемый текст UK в owner preview обновлён после обратного перевода.
- Новый стиль визуально проверен по screenshots в `restyle-screenshots/` и `translation-final-screenshots/`. UI-перевод использует детерминированный DEBUG fixture; реальный provider отдельно проверен через Google Cloud Translation (`translation-provider-live.json`). Локальному user ADC нужен quota-project header, runtime использует service account.
- Все 7 `scripts/validate_*.py` PASS; каталог содержит 2765 записей; App Check policy PASS (65 callables).

Все артефакты находятся в `output/announcements/`, не включены в Git.

## Облако

Обновлены `translateContent` и совместимый `manageAnnouncements`. Для финального source-only обновления `translateContent` обычный Firebase CLI дважды столкнулся с HTTP 503 в API списка функций v1. Выполнено точечное обновление через [официальный API v2 с updateMask](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/patch), меняющий только `buildConfig.source`.

Операция завершена: BUILD/SERVICE COMPLETE, ACTIVE; App Check отклоняет запрос без токена с HTTP 401. Read-back подтверждает сохранение runtime account, environment, memory, timeout, max instances, ingress и secret settings. Доказательства: `translation-cloud72-readback.json`, `translation72-v2-operation.json`, `translation72-v2-status.json`. Хеш переданного source ZIP: `7c350f9949c38174b740051dc64a709830905c9027c011b040d958ca3ace0fd7`.

## Сборка

71: archive PASS (0 compiler warnings/errors), подпись PASS, encryption=false, export SUCCEEDED, Apple VALID / IN_BETA_TESTING. Финальная 72 сохраняет обратный перевод и подтверждение замены прямо в окне проверки. Archive PASS, 0 compiler warnings/errors, подпись PASS, encryption=false, EXPORT SUCCEEDED. Apple VALID / IN_BETA_TESTING, notesVerified=true. Доказательства: `archive72.log`, `archive72-verification.json`, `export72-account.log`, `testflight72-apple.json`.

Пять прежних export dSYM warnings для codeless Firebase/gRPC stubs подробно описаны в `UserAnnouncementsImplementationStatus.md`; символы самого приложения сохранены. Физический APNs/App Attest smoke требует доступного iPhone. Публичная публикация и App Review не выполняются.
