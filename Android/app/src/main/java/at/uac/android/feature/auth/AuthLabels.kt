package at.uac.android.feature.auth

internal fun authText(language: String, german: String, ukrainian: String): String =
    if (language == "uk") ukrainian else german

fun AuthProblem.message(language: String): String {
    val pair =
        when (this) {
            AuthProblem.INVALID_EMAIL ->
                "Bitte eine gültige E-Mail-Adresse eingeben." to
                    "Введіть коректну адресу електронної пошти."
            AuthProblem.PASSWORD_REQUIRED -> "Bitte das Passwort eingeben." to "Введіть пароль."
            AuthProblem.WEAK_PASSWORD ->
                "Das Passwort muss 10 bis 128 Zeichen lang sein." to
                    "Пароль має містити від 10 до 128 символів."
            AuthProblem.PASSWORD_MISMATCH ->
                "Die Passwörter stimmen nicht überein." to "Паролі не збігаються."
            AuthProblem.NAME_REQUIRED ->
                "Bitte einen Anzeigenamen mit 1 bis 160 Zeichen eingeben." to
                    "Введіть ім’я для показу від 1 до 160 символів."
            AuthProblem.REGION_REQUIRED ->
                "Bitte dein Bundesland auswählen." to "Оберіть вашу федеральну землю."
            AuthProblem.CONSENT_REQUIRED ->
                "Bedingungen und Datenschutzhinweise lesen und das Mindestalter von 14 Jahren bestätigen." to
                    "Ознайомтеся з умовами й політикою конфіденційності та підтвердьте вік від 14 років."
            AuthProblem.INVALID_TELEGRAM ->
                "Der Telegram-Name muss 5–32 Buchstaben, Ziffern oder Unterstriche enthalten." to
                    "Ім’я Telegram має містити 5–32 латинські літери, цифри або підкреслення."
            AuthProblem.INVALID_CREDENTIALS ->
                "E-Mail-Adresse oder Passwort stimmen nicht." to
                    "Неправильна адреса пошти або пароль."
            AuthProblem.EMAIL_EXISTS ->
                "Diese E-Mail-Adresse wird bereits verwendet. Melde dich an oder setze dein Passwort zurück." to
                    "Цю адресу вже використано. Увійдіть або відновіть пароль."
            AuthProblem.NETWORK ->
                "Keine sichere Verbindung. Bitte erneut versuchen; nicht bestätigte Änderungen werden nicht als erfolgreich angezeigt." to
                    "Немає надійного з’єднання. Спробуйте ще раз; непідтверджені зміни не позначаються успішними."
            AuthProblem.RATE_LIMITED ->
                "Bitte kurz warten und dann erneut versuchen." to
                    "Трохи зачекайте та спробуйте знову."
            AuthProblem.DISABLED ->
                "Dieses Konto ist deaktiviert. Bitte wende dich an den Support." to
                    "Цей акаунт вимкнено. Зверніться до підтримки."
            AuthProblem.OPERATION_DISABLED ->
                "Diese Anmeldemethode ist derzeit nicht verfügbar." to
                    "Цей спосіб входу наразі недоступний."
            AuthProblem.PROFILE_MISSING ->
                "Das Kontoprofil fehlt. Es wurde kein Ersatzkonto erzeugt." to
                    "Профіль акаунта відсутній. Замість нього не було створено інший акаунт."
            AuthProblem.INVALID_PROFILE ->
                "Das Kontoprofil konnte nicht sicher geprüft werden." to
                    "Не вдалося безпечно перевірити профіль акаунта."
            AuthProblem.PERMISSION_DENIED ->
                "Dafür fehlt die Berechtigung. Bitte die Sitzung erneut prüfen." to
                    "Бракує дозволу для цієї дії. Перевірте сеанс ще раз."
            AuthProblem.SESSION_CHANGED ->
                "Die Sitzung hat sich geändert. Bitte erneut anmelden." to
                    "Сеанс змінився. Увійдіть знову."
            AuthProblem.VERIFICATION_PENDING ->
                "Die E-Mail-Adresse ist noch nicht bestätigt." to
                    "Електронну адресу ще не підтверджено."
            AuthProblem.CODE_INVALID ->
                "Der Link ist ungültig oder gehört nicht zu diesem Vorgang." to
                    "Посилання недійсне або належить іншій дії."
            AuthProblem.CODE_EXPIRED ->
                "Dieser Link ist abgelaufen. Bitte einen neuen anfordern." to
                    "Строк дії посилання минув. Запросіть нове."
            AuthProblem.SECOND_FACTOR_REQUIRED ->
                "Dieses Konto benötigt eine Zwei-Faktor-Anmeldung. Der lokale Test bestätigt keine echte TOTP-Sitzung." to
                    "Акаунт потребує двофакторного входу. Локальний тест не підтверджує справжній сеанс TOTP."
            AuthProblem.LOCAL_ONLY ->
                "Dieser isolierte Test erlaubt nur erfundene Adressen mit .invalid, z. B. test@example.invalid." to
                    "Цей ізольований тест дозволяє лише вигадані адреси з .invalid, наприклад test@example.invalid."
            AuthProblem.LEGAL_CHANGED ->
                "Die aktuelle Dokumentversion hat sich geändert. Bitte den neuen Text lesen und erneut ausdrücklich zustimmen." to
                    "Чинна версія документа змінилася. Прочитайте новий текст і надайте згоду ще раз."
            AuthProblem.LEGAL_UNCONFIRMED ->
                "Die Bestätigung konnte noch nicht sicher geprüft werden. Bitte zuerst die Sitzung aktualisieren; es wird keine Zustimmung erfunden." to
                    "Підтвердження ще не вдалося надійно перевірити. Спочатку оновіть сеанс; згода не буде вигаданою."
            AuthProblem.MFA_CODE_INVALID ->
                "Bitte den aktuellen Zifferncode aus deiner Authenticator-App eingeben. Prüfe auch die Gerätezeit." to
                    "Введіть поточний цифровий код із застосунку-аутентифікатора. Перевірте також час на пристрої."
            AuthProblem.MFA_EXPIRED ->
                "Diese Sicherheitsanfrage ist abgelaufen. Bitte abbrechen und erneut starten." to
                    "Строк дії цього запиту безпеки минув. Скасуйте його та почніть знову."
            AuthProblem.MFA_UNSUPPORTED ->
                "Dieser zweite Faktor ist nicht verfügbar. Bitte einen unterstützten Authenticator verwenden oder den Support kontaktieren." to
                    "Цей другий фактор недоступний. Скористайтеся підтримуваним аутентифікатором або зверніться до підтримки."
            AuthProblem.MFA_ALREADY_ENROLLED ->
                "Ein Authenticator ist bereits verbunden. Bitte zuerst den aktuellen Sicherheitsstatus prüfen." to
                    "Аутентифікатор уже підключений. Спочатку перевірте поточний стан безпеки."
            AuthProblem.MFA_LAST_FACTOR ->
                "Der letzte Authenticator eines geschützten Administrationskontos kann hier nicht entfernt werden." to
                    "Останній аутентифікатор захищеного адміністративного акаунта тут видалити не можна."
            AuthProblem.MFA_UNCONFIRMED ->
                "Das Ergebnis ist noch nicht sicher bestätigt. Bitte den Sicherheitsstatus prüfen, bevor du die Änderung wiederholst." to
                    "Результат ще не підтверджено надійно. Перевірте стан безпеки, перш ніж повторювати зміну."
            AuthProblem.RECENT_LOGIN_REQUIRED ->
                "Bitte deine Anmeldung mit dem aktuellen Passwort erneut bestätigen." to
                    "Підтвердьте вхід ще раз поточним паролем."
            AuthProblem.UNKNOWN ->
                "Der Vorgang konnte nicht abgeschlossen werden. Bitte erneut versuchen." to
                    "Не вдалося завершити дію. Спробуйте ще раз."
        }
    return authText(language, pair.first, pair.second)
}

fun AuthNotice.message(language: String): String =
    when (this) {
        AuthNotice.VERIFICATION_SENT ->
            authText(
                language,
                "Bestätigungslink im lokalen E-Mail-Test erstellt. Es wird keine echte E-Mail versendet.",
                "Посилання підтвердження створено в локальному тесті пошти. Справжній лист не надсилається.",
            )
        AuthNotice.RESET_SENT ->
            authText(
                language,
                "Falls ein passendes Konto existiert, wurde ein lokaler Link zur Passwortänderung erstellt.",
                "Якщо відповідний акаунт існує, створено локальне посилання зміни пароля.",
            )
        AuthNotice.PASSWORD_CHANGED ->
            authText(
                language,
                "Passwort geändert. Bitte mit dem neuen Passwort anmelden.",
                "Пароль змінено. Увійдіть із новим паролем.",
            )
        AuthNotice.EMAIL_VERIFIED ->
            authText(language, "E-Mail-Adresse bestätigt.", "Електронну адресу підтверджено.")
        AuthNotice.LEGAL_ACCEPTED ->
            authText(
                language,
                "Zustimmung auf dem Server bestätigt.",
                "Згоду підтверджено на сервері.",
            )
        AuthNotice.MFA_ENROLLED ->
            authText(
                language,
                "Authenticator verbunden. Eine Anmeldung mit seinem Code muss separat bestätigt werden.",
                "Аутентифікатор підключено. Вхід із його кодом потрібно підтвердити окремо.",
            )
        AuthNotice.MFA_REMOVED ->
            authText(
                language,
                "Entfernung des Authenticators bestätigt.",
                "Видалення аутентифікатора підтверджено.",
            )
        AuthNotice.MFA_VERIFIED ->
            authText(
                language,
                "Anmeldung mit Authenticator bestätigt.",
                "Вхід з аутентифікатором підтверджено.",
            )
        AuthNotice.MFA_ACTIVATED ->
            authText(
                language,
                "Schutz des Administrationskontos auf dem Server bestätigt.",
                "Захист адміністративного акаунта підтверджено на сервері.",
            )
    }
