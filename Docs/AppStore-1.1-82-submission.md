# App Store 1.1 — build 82

09.09.2026. Запрос пользователя: подготовить проверенный build 81 к App Store и отправить на App Review при возможности.

## Подготовлено

- Build 81 имеет `INTERNAL_ONLY` и непригоден для App Review. Для App Store собран 82 с тем же кодом: изменён только `CURRENT_PROJECT_VERSION`; исходный коммит архива `0538963`.
- Архив и подпись проверены. 30 privacy manifests совпадают с архивом 81. Шифрование: `usesNonExemptEncryption=false`.
- Apple приняла build 82: `VALID`, `APP_STORE_ELIGIBLE`, ID `75ca6ef3-5ba7-4bc6-9cea-cc00a8ddf03c`.
- Создана версия 1.1: `940a1b2f-2c62-4ff3-8e5b-0e60c47aeeda`. Build 82 прикреплён; выпуск после одобрения остаётся `MANUAL`.
- Описания и 24 скриншота (uk/de-DE, iPhone/iPad) перенесены из предыдущей опубликованной версии. Все screenshot assets `COMPLETE`. What's New обновлено на украинском и немецком.
- Данные Apple Review перенесены; вход существующей review-учётной записью проверен через Firebase Auth, email подтверждён, аккаунт не отключён. Это проверка аутентификации, не полный UI-сценарий ревьюера.
- Ссылки privacy/support отвечают HTTP 200. Инструкции TestFlight обновлены uk/de-DE.
- Создана заявка `16bcc702-46e8-41ed-aff3-b40b942b307a`, версия добавлена: `READY_FOR_REVIEW`, `submittedDate=null`.

## Отправлено на App Review

09.09.2026 в 18:19:49 Europe/Vienna (16:19:49 UTC) Apple приняла финальную отправку. Повторный GET подтвердил `WAITING_FOR_REVIEW` и для заявки, и для версии 1.1; `submittedDate=2026-09-09T16:19:49.565Z`. Прикреплён build 82, выпуск остаётся `MANUAL`. Это ожидание проверки, не одобрение и не публичный выпуск.

Проверка App Privacy закрыта по шести скриншотам авторизованного App Store Connect, предоставленным пользователем 09.09.2026 (время на телефоне 18:14–18:15; вложения C20987F9-797C-405C-BBCA-028F5A226938, фото 1–6). Все 14 категорий, привязка к личности и назначения совпадают с инвентарём и архивом. User ID, Product Interaction, Other Diagnostic Data, Other Data Types и Coarse Location указаны для App Functionality + Analytics; остальные девять — App Functionality. Tracking не указан. URL политики совпадает. Изменения анкеты не потребовались. Источник проверки — скриншоты пользователя, а не вход в локальном браузере.

Подтверждения API: `review-submitted.json` и `review-submitted-readback.json` в каталоге релиза ниже.

Архив и частные данные ревью сохранены только вне Git: `~/Library/Developer/UAC-Releases/1.1-82/`. При upload — пять прежних предупреждений dSYM сторонних Firebase/gRPC-библиотек; загрузка успешна.
