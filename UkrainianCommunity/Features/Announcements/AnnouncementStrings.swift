import Foundation

enum AnnouncementStrings {
    static var title: String { LocalizationStore.localizedString("announcements.title", defaultValue: "Оповіщення користувачів") }
    static var history: String { LocalizationStore.localizedString("announcements.history", defaultValue: "Повідомлення UAC") }
    static var subtitle: String { LocalizationStore.localizedString("announcements.subtitle", defaultValue: "Повідомлення, аудиторія та результати") }
    static var create: String { LocalizationStore.localizedString("announcements.create", defaultValue: "Створити повідомлення") }
    static var save: String { LocalizationStore.localizedString("announcements.save", defaultValue: "Зберегти чернетку") }
    static var preview: String { LocalizationStore.localizedString("announcements.preview", defaultValue: "Попередній перегляд") }
    static var send: String { LocalizationStore.localizedString("announcements.send", defaultValue: "Надіслати / запланувати") }
    static var test: String { LocalizationStore.localizedString("announcements.test", defaultValue: "Надіслати тест собі") }
    static var cancel: String { LocalizationStore.localizedString("announcements.cancel", defaultValue: "Припинити показ") }
    static var registered: String { LocalizationStore.localizedString("announcements.registered", defaultValue: "Усі зареєстровані") }
    static var organizationOwners: String { LocalizationStore.localizedString("announcements.organizationOwners", defaultValue: "Власники організацій") }
    static var appAdmins: String { LocalizationStore.localizedString("announcements.appAdmins", defaultValue: "Адміністратори застосунку") }
    static var organizationAdmins: String { LocalizationStore.localizedString("announcements.organizationAdmins", defaultValue: "Адміністратори організацій") }
    static var organizationModerators: String { LocalizationStore.localizedString("announcements.organizationModerators", defaultValue: "Модератори організацій") }
    static var audience: String { LocalizationStore.localizedString("announcements.audience", defaultValue: "Одержувачі") }
    static var people: String { LocalizationStore.localizedString("announcements.people", defaultValue: "Вибрати користувачів") }
    static var regions: String { LocalizationStore.localizedString("announcements.regions", defaultValue: "Регіон акаунту") }
    static var austria: String { LocalizationStore.localizedString("announcements.austria", defaultValue: "Уся Австрія") }
    static var regionHelp: String { LocalizationStore.localizedString("announcements.regionHelp", defaultValue: "Регіон застосовується до всіх вибраних акаунтів.") }
    static var headline: String { LocalizationStore.localizedString("announcements.headline", defaultValue: "Заголовок") }
    static var body: String { LocalizationStore.localizedString("announcements.body", defaultValue: "Текст повідомлення") }
    static var translate: String { LocalizationStore.localizedString("announcements.translate", defaultValue: "Перекласти на іншу мову") }
    static var overwrite: String { LocalizationStore.localizedString("announcements.overwrite", defaultValue: "Замінити переклад?") }
    static var review: String { LocalizationStore.localizedString("announcements.review", defaultValue: "Я перевірив обидві мовні версії та одержувачів") }
    static var translationReview: String { LocalizationStore.localizedString("announcements.translationReview", defaultValue: "Після редагування перевірте текст обома мовами перед надсиланням.") }
    static var mode: String { LocalizationStore.localizedString("announcements.mode", defaultValue: "Показ повідомлення") }
    static var once: String { LocalizationStore.localizedString("announcements.once", defaultValue: "Показати один раз") }
    static var acknowledge: String { LocalizationStore.localizedString("announcements.acknowledge", defaultValue: "Повторювати до підтвердження") }
    static var ack: String { LocalizationStore.localizedString("announcements.ack", defaultValue: "Ознайомився") }
    static var later: String { LocalizationStore.localizedString("announcements.later", defaultValue: "Пізніше") }
    static var close: String { LocalizationStore.localizedString("announcements.close", defaultValue: "Закрити") }
    static var push: String { LocalizationStore.localizedString("announcements.push", defaultValue: "Додатково надіслати push") }
    static var feedback: String { LocalizationStore.localizedString("announcements.feedback", defaultValue: "Кнопка звернення") }
    static var writeFeedback: String { LocalizationStore.localizedString("announcements.writeFeedback", defaultValue: "Написати через звернення") }
    static var start: String { LocalizationStore.localizedString("announcements.start", defaultValue: "Початок показу") }
    static var expiry: String { LocalizationStore.localizedString("announcements.expiry", defaultValue: "Завершення показу") }
    static var scheduleHelp: String { LocalizationStore.localizedString("announcements.scheduleHelp", defaultValue: "Час Австрії (Europe/Vienna). Максимальний термін — 90 днів.") }
    static var error: String { LocalizationStore.localizedString("announcements.error", defaultValue: "Не вдалося виконати дію. Перевірте з’єднання, права доступу та повторіть спробу.") }
    static var syncPending: String { LocalizationStore.localizedString("announcements.syncPending", defaultValue: "Підтвердження збережено на пристрої. Синхронізація буде повторена.") }
    static var loadMore: String { LocalizationStore.localizedString("announcements.loadMore", defaultValue: "Завантажити ще") }
    static var empty: String { LocalizationStore.localizedString("announcements.empty", defaultValue: "Повідомлень поки немає") }
    static var stats: String { LocalizationStore.localizedString("announcements.stats", defaultValue: "Результати (акаунти)") }
    static var shown: String { LocalizationStore.localizedString("announcements.shown", defaultValue: "Показано") }
    static var confirmed: String { LocalizationStore.localizedString("announcements.confirmed", defaultValue: "Підтверджено") }
    static var action: String { LocalizationStore.localizedString("announcements.action", defaultValue: "Перехід до звернення") }
    static var pushSent: String { LocalizationStore.localizedString("announcements.pushSent", defaultValue: "Push прийнято сервісом") }
    static var pushFailed: String { LocalizationStore.localizedString("announcements.pushFailed", defaultValue: "Помилки push") }
    static var count: String { LocalizationStore.localizedString("announcements.count", defaultValue: "Акаунтів за поточним вибором") }
    static var countAudience: String { LocalizationStore.localizedString("announcements.countAudience", defaultValue: "Порахувати одержувачів") }
    static var sent: String { LocalizationStore.localizedString("announcements.sent", defaultValue: "Повідомлення збережено для надсилання.") }
    static var tested: String { LocalizationStore.localizedString("announcements.tested", defaultValue: "Тест створено для вашого акаунту.") }
    static var retry: String { LocalizationStore.localizedString("announcements.retry", defaultValue: "Оновити") }
    static var signIn: String { LocalizationStore.localizedString("announcements.signIn", defaultValue: "Увійти, щоб написати звернення") }
    static var draft: String { LocalizationStore.localizedString("announcements.draft", defaultValue: "Чернетка") }
    static var published: String { LocalizationStore.localizedString("announcements.published", defaultValue: "Опубліковано / заплановано") }
    static var cancelled: String { LocalizationStore.localizedString("announcements.cancelled", defaultValue: "Показ припинено") }
    static var search: String { LocalizationStore.localizedString("announcements.search", defaultValue: "Пошук серед завантажених користувачів") }
    static var sendConfirm: String { LocalizationStore.localizedString("announcements.sendConfirm", defaultValue: "Надіслати повідомлення вибраній аудиторії?") }
    static var saved: String { LocalizationStore.localizedString("announcements.saved", defaultValue: "Чернетку збережено") }
    static var guestShown: String { LocalizationStore.localizedString("announcements.guestShown", defaultValue: "Показано без входу (попередні версії)") }
    static var guestAck: String { LocalizationStore.localizedString("announcements.guestAck", defaultValue: "Підтверджено без входу (попередні версії)") }
    static func group(_ key: String) -> String { LocalizationStore.localizedString("announcements.\(key)", defaultValue: key) }
}

/// Management-only copy. Kept next to the feature while the shared catalog has
/// unrelated pending changes; both shipping languages are always provided.
enum AnnouncementManagementText {
    private static let copy: [String: (String, String)] = [
            "draft": ("Чернетки", "Entwürfe"), "scheduled": ("Заплановані", "Geplant"),
            "active": ("Діють зараз", "Aktiv"), "completed": ("Завершені", "Abgelaufen"), "cancelled": ("Припинені", "Beendet"),
            "done": ("Готово", "Fertig"),
            "all": ("Усі", "Alle"), "empty": ("У цій категорії повідомлень немає", "Keine Mitteilungen in dieser Kategorie"),
            "selected": ("Вибрані користувачі", "Ausgewählte Nutzer"),
            "search": ("Ім’я або email", "Name oder E-Mail"), "noResults": ("Користувачів не знайдено", "Keine Nutzer gefunden"),
            "addPeople": ("Додати користувачів", "Nutzer hinzufügen"),
            "union": ("Групи й вибрані люди додаються разом. Лише конкретним людям — вимкніть групи. Регіон діє для всіх.", "Gruppen und Personen werden kombiniert. Nur einzelne Empfänger: Gruppen ausschalten. Region gilt für alle."),
            "limit": ("Можна вибрати до 100 користувачів.", "Bis zu 100 Nutzer können ausgewählt werden."),
            "unavailable": ("Акаунт недоступний; повідомлення не буде надіслане", "Konto nicht verfügbar; erhält keine Mitteilung"),
            "reviewTitle": ("Перевірка перед надсиланням", "Vor dem Senden prüfen"),
            "recipientCount": ("Акаунтів за вибраними умовами", "Konten für diese Auswahl"),
            "countHelp": ("Активні акаунти рахуються один раз; це не гарантія доставки. Показ доступний у застосунку iOS. Push отримають пристрої з дозволом на сповіщення. Аудиторія може змінитися до початку показу.", "Aktive Konten zählen einmal; dies ist keine Zustellbestätigung. Die Anzeige ist in der iOS-App verfügbar. Push erhalten Geräte mit Mitteilungserlaubnis. Die Zielgruppe kann sich bis zum Start ändern."),
            "noRecipients": ("За цими умовами немає активних одержувачів. Змініть вибір.", "Keine aktiven Empfänger für diese Auswahl. Bitte Auswahl ändern."),
            "discardTitle": ("Зберегти зміни?", "Änderungen speichern?"),
            "discard": ("Вийти без збереження", "Ohne Speichern schließen"), "continue": ("Продовжити редагування", "Weiter bearbeiten"),
            "stopTitle": ("Припинити показ і подальшу розсилку?", "Anzeige und weiteren Versand beenden?"),
            "stopHelp": ("Уже надіслані push неможливо відкликати. Переглянуте повідомлення залишиться в історії користувача.", "Bereits gesendete Push-Nachrichten können nicht zurückgerufen werden. Gelesene Mitteilungen bleiben im Verlauf."),
            "languages": ("Заповніть заголовок і текст обома мовами.", "Titel und Text in beiden Sprachen ausfüllen."),
            "length": ("Заголовок: до 160 символів; текст: до 6000. Emoji можуть займати декілька символів.", "Titel: maximal 160 Zeichen; Text: maximal 6000. Emoji können mehrere Zeichen belegen."),
            "recipients": ("Виберіть групу або конкретних користувачів.", "Eine Gruppe oder einzelne Nutzer auswählen."),
            "period": ("Завершення має бути після початку та в майбутньому. Максимальна тривалість — 90 днів.", "Das Ende muss nach dem Start und in der Zukunft liegen. Maximale Dauer: 90 Tage."),
            "network": ("Немає зв’язку із сервером. Перевірте інтернет і спробуйте ще раз. Зміни залишилися в редакторі.", "Keine Verbindung zum Server. Internetverbindung prüfen und erneut versuchen. Änderungen bleiben im Editor."),
            "access": ("Для цієї дії потрібен актуальний вхід власника з двофакторним захистом. Увійдіть повторно.", "Eine aktuelle Anmeldung des Eigentümers mit Zwei-Faktor-Schutz ist erforderlich. Bitte erneut anmelden."),
            "conflict": ("Чернетка змінилася на іншому пристрої. Збережіть свій текст і відкрийте її повторно.", "Der Entwurf wurde auf einem anderen Gerät geändert. Text sichern und Entwurf erneut öffnen."),
            "invalid": ("Перевірте текст, одержувачів і період показу. Сервер не прийняв дані.", "Text, Empfänger und Zeitraum prüfen. Der Server hat die Daten nicht angenommen."),
            "precondition": ("Дія зараз недоступна. Перевірте статус повідомлення та актуальність входу; за потреби відкрийте його повторно.", "Aktion derzeit nicht verfügbar. Status und Anmeldung prüfen; Mitteilung gegebenenfalls erneut öffnen."),
            "quota": ("Досягнуто ліміт. Припиніть непотрібні повідомлення або повторіть пізніше.", "Limit erreicht. Nicht benötigte Mitteilungen beenden oder später erneut versuchen."),
            "missing": ("Повідомлення більше недоступне. Оновіть список.", "Mitteilung nicht mehr verfügbar. Liste aktualisieren."),
            "timeout": ("Сервер не відповів вчасно. Результат дії невідомий: спочатку оновіть список і перевірте статус.", "Zeitüberschreitung. Ergebnis unbekannt: zuerst Liste aktualisieren und Status prüfen."),
            "pushState": ("Стан push-розсилки", "Status des Push-Versands"),
            "pending": ("Очікує початку / наступної спроби", "Wartet auf Start / nächsten Versuch"),
            "running": ("Надсилається", "Wird gesendet"), "delivered": ("Обробку завершено", "Verarbeitung abgeschlossen"),
            "failed": ("Помилка; буде повторна спроба", "Fehler; erneuter Versuch folgt"),
            "disabled": ("Push не запитано", "Push nicht angefordert"),
            "unknown": ("Статус невідомий", "Status unbekannt"),
            "pushHelp": ("Покази й підтвердження рахуються за акаунтами. Push — за пристроями; прийняття сервісом не гарантує прочитання.", "Anzeigen und Bestätigungen zählen Konten. Push zählt Geräte; die Annahme durch den Dienst bestätigt kein Lesen."),
            "reload": ("Оновити результати", "Ergebnisse aktualisieren"),
            "now": ("Зараз", "Jetzt"), "yes": ("Так", "Ja"), "no": ("Ні", "Nein"),
            "loadMore": ("Завантажити попередні повідомлення", "Weitere Mitteilungen laden")
    ]
    static func value(_ key: String) -> String {
        guard let pair = copy[key] else { return key }
        return AppLanguage.stored == .ukrainian ? pair.0 : pair.1
    }
}
