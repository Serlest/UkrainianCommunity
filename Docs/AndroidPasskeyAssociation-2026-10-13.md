# Android passkey: привязка приложения и проверка

Статус 13 октября 2026: клиентский код и серверная проверка происхождения готовы, флаги сборок выключены. Публикация и проверка реального ключа ещё не выполнены.

1. В Google Play Console взять SHA-256 **App signing certificate** для `at.serlest.ukrainiancommunity`. Для staging взять SHA-256 сертификата APK, который действительно будет установлен на тестовом устройстве. Upload key и локальный debug key нельзя выдавать за Play signing key.
2. Запустить `node Android/scripts/prepare-passkey-association.mjs at.serlest.ukrainiancommunity <SHA-256>` и отдельно для staging. Скрипт проверит форму отпечатка, выведет запись `assetlinksEntry` и `serverOrigin`; он не записывает файл и не публикует сайт.
3. После проверки сертификатов собрать массив записей в `website/.well-known/assetlinks.json`, развернуть его на `https://ukrainiancommunity-dbd5f.web.app/.well-known/assetlinks.json` и прочитать снаружи: HTTP 200, `Content-Type: application/json`, правильные пакет и отпечаток. Развёртывание Hosting требует отдельного контролируемого плана, поскольку на сайте есть другие файлы.
4. Настроить `UAC_PASSKEY_ANDROID_ORIGINS` на backend как список точных `serverOrigin` через запятую. Сервер добавит их к существующему iOS/web origin. Клиент не может передать разрешённый origin в callable. После развертывания функций проверить список сред и серверный read-back.
5. Только после пунктов 1–4 включить `UAC_STAGING_PASSKEY_ENABLED=true` в тестовой сборке. Проверить создание, вход, удаление, повторный вход после удаления и роль владельца с настоящим TOTP на физическом устройстве. В production флаг включать лишь после этой приёмки.

Техническое основание: [Android Digital Asset Links](https://developer.android.com/identity/credential-manager/prerequisites), [проверка Android WebAuthn-origin](https://developer.android.com/identity/passkeys/create-passkeys), [Credential Manager sign-in](https://developer.android.com/identity/passkeys/sign-in-with-passkeys).
