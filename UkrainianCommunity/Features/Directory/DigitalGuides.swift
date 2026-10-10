import Foundation

enum DigitalGuides {
    private static let services = DirectorySource(name: "oesterreich.gv.at · Online-Verfahren", url: "https://www.oesterreich.gv.at/de/themen/egovernment_moderne_verwaltung/4")
    private static let identity = DirectorySource(name: "oesterreich.gv.at · ID Austria", url: "https://www.oesterreich.gv.at/id-austria")
    private static let foreignID = DirectorySource(name: "oesterreich.gv.at · ID Austria Registrierung", url: "https://www.oesterreich.gv.at/id-austria/haeufige-fragen/registrierung.html")
    private static let app = DirectorySource(name: "oesterreich.gv.at · App ID Austria", url: "https://www.oesterreich.gv.at/de/ueber-oesterreichgvat/neu/Transkription-Video-ID-Austria")
    private static let elga = DirectorySource(name: "Gesundheitsportal · ELGA Login", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/elga/elga-login-teilnahme.html")
    private static let phishing = DirectorySource(name: "Bundeskriminalamt · Phishing", url: "https://www.bundeskriminalamt.at/212/internet/phishing_smishing.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "online-services": return onlineServices
        case "digital-identity": return digitalIdentity
        case "online-safety": return onlineSafety
        default: return nil
        }
    }

    private static let onlineServices = DirectoryGuide(
        cardSummary: .init(ukrainian: "Заяви онлайн, FinanzOnline, ELGA й електронні повідомлення", german: "Online-Anträge, FinanzOnline, ELGA und elektronische Nachrichten"),
        introduction: .init(ukrainian: "Не кожну австрійську процедуру можна зробити онлайн; доступність залежить від установи й іноді землі.", german: "Nicht jeder Amtsweg ist online möglich; Angebot hängt von Behörde und teils vom Bundesland ab."),
        sections: [
            .init("find", "magnifyingglass", "Знайдіть офіційну процедуру", "Amtlichen Weg finden", "Почніть на oesterreich.gv.at: оберіть життєву ситуацію й перевірте, чи потрібна ID Austria або EU Login, які документи та яка установа відповідальна. Регіональні послуги можуть бути доступні лише в окремих громадах.", "Auf oesterreich.gv.at Lebenslage wählen und prüfen, ob ID Austria oder EU Login, welche Unterlagen und welche Behörde erforderlich sind. Regionale Verfahren gibt es nicht in jeder Gemeinde.", source: services),
            .init("submit", "doc.badge.arrow.up", "Збережіть доказ подання", "Einbringungsnachweis sichern", "Перед відправленням перевірте дані, додатки й строк. Завантажте підтвердження, номер справи та копію форми. Електронну скриньку й звичайну пошту перевіряйте регулярно: повідомлення може вимагати дії в короткий строк.", "Vor Absenden Daten, Beilagen und Frist prüfen. Bestätigung, Geschäftszahl und Formularkopie sichern. Elektronischen Postkorb und Briefpost regelmäßig prüfen: Eine Zustellung kann kurze Fristen auslösen.", source: services),
            .init("health", "cross.case", "Доступ до медичних даних", "Gesundheitsdaten einsehen", "Через ELGA можна переглядати наявні eBefunde та eMedikation, керувати участю й правами доступу. Для входу потрібна ID Austria; відсутність документа в ELGA не означає, що обстеження не проводили. Медичні питання уточнюйте у лікаря.", "Über ELGA vorhandene eBefunde und eMedikation einsehen sowie Teilnahme und Zugriffe verwalten. Anmeldung mit ID Austria; ein fehlender Eintrag beweist nicht, dass keine Untersuchung stattfand. Medizinische Fragen mit der behandelnden Stelle klären.", source: elga)
        ], sources: [services, elga]
    )

    private static let digitalIdentity = DirectoryGuide(
        cardSummary: .init(ukrainian: "Отримання ID Austria, вимоги та відновлення доступу", german: "ID Austria beantragen, Voraussetzungen und Zugang sichern"),
        introduction: .init(ukrainian: "ID Austria — безплатна цифрова ідентифікація. Іноземне громадянство саме по собі не виключає реєстрацію.", german: "ID Austria ist kostenlos. Eine ausländische Staatsangehörigkeit schließt die Registrierung nicht grundsätzlich aus."),
        sections: [
            .init("eligibility", "person.crop.circle.badge.checkmark", "Перевірте умови", "Voraussetzungen prüfen", "Потрібно мати щонайменше 14 років, мати відповідний документ і засіб підтвердження. Іноземці реєструються, зокрема, в Landespolizeidirektion або Finanzamt за наявності зв’язку з Австрією; зазвичай потрібна особиста перевірка особи. Перед записом перевірте конкретний список документів, фото та можливість запису.", "Ab 14 Jahren, mit geeignetem Ausweis und Authentifizierungsfaktor. Ausländische Staatsangehörige können sich etwa bei Landespolizeidirektion oder Finanzamt mit Inlandsbezug registrieren; Identität wird normalerweise persönlich geprüft. Vor Termin Ausweise, Foto und Buchungsvorgaben prüfen.", source: foreignID),
            .init("activate", "iphone.gen3", "Активуйте в офіційному застосунку", "In offizieller App aktivieren", "Дотримуйтесь інструкцій порталу ID Austria та офіційного застосунку «ID Austria», який замінив «Digitales Amt». Реєстрація безплатна; окремі документи чи державні послуги можуть бути платними. Не підтверджуйте запит на підпис, який ви самі не починали.", "Anweisungen des ID Austria Portals und der offiziellen App „ID Austria“ befolgen; sie hat „Digitales Amt“ abgelöst. Registrierung ist kostenlos; einzelne Dokumente oder Behördenleistungen können Gebühren haben. Nie einen nicht selbst ausgelösten Signaturauftrag freigeben.", source: app),
            .init("recover", "key", "Бережіть і відновлюйте доступ", "Zugang schützen und wiederherstellen", "Збережіть спосіб відновлення, оновлюйте номер телефону й захистіть сам пристрій. При втраті телефона негайно перевірте офіційну процедуру блокування або перенесення ID Austria. Для іноземних громадян строк чинності може бути обмежений; перевіряйте дату у своєму профілі.", "Wiederherstellung vorbereiten, Telefonnummer aktuell halten und Gerät sperren. Bei Verlust offizielle Sperr- oder Umzugsanleitung sofort prüfen. Für ausländische Staatsangehörige kann die Gültigkeit begrenzt sein; Datum im eigenen Profil prüfen.", source: foreignID)
        ], sources: [identity, foreignID, app]
    )

    private static let onlineSafety = DirectoryGuide(
        cardSummary: .init(ukrainian: "Фішинг, захист доступу й дії після шахрайства", german: "Phishing, Kontoschutz und Schritte nach Betrug"),
        introduction: .init(ukrainian: "Шахраї можуть видавати себе за банк, пошту чи державну службу. Перевіряйте адресу сайту самостійно.", german: "Betrüger geben sich als Bank, Post oder Behörde aus. Webadresse selbst prüfen."),
        sections: [
            .init("before", "lock.shield", "Розпізнайте підробку", "Fälschung erkennen", "Не відкривайте посилання з неочікуваного SMS, листа або QR-коду для введення пароля, банківських даних чи кодів. Самостійно відкрийте офіційний сайт або застосунок, зателефонуйте на номер з договору. Увімкніть окремі паролі та двофакторний захист.", "Keine Zugangsdaten, Bankdaten oder Codes über unerwartete SMS-, E-Mail- oder QR-Links eingeben. Offizielle Website oder App selbst öffnen und Nummer aus Vertrag anrufen. Eigene Passwörter und zweiten Faktor verwenden.", source: phishing),
            .init("after", "exclamationmark.shield", "Якщо дані вже передані", "Wenn Daten weitergegeben wurden", "Негайно блокуйте картку й онлайн-банкінг через банк, змініть паролі з безпечного пристрою, перевірте рахунок та повідомте банк про незаконні платежі. Збережіть повідомлення, адреси, скріншоти та чеки; зверніться до поліції із заявою.", "Karte und Online-Banking sofort über die Bank sperren, Passwörter von sicherem Gerät ändern, Umsätze prüfen und Bank über unbefugte Buchungen informieren. Nachrichten, Links, Screenshots und Belege sichern und Anzeige bei der Polizei erstatten.", source: phishing),
            .init("report", "envelope.badge", "Повідомте про шахрайство", "Betrug melden", "Підозру можна повідомити Cybercrime-Meldestelle Bundeskriminalamt; таке повідомлення не замінює заяву до поліції. Якщо є фінансова шкода або викрадені документи, повідомте також банк і орган, що видав документ.", "Verdacht kann an die Cybercrime-Meldestelle des Bundeskriminalamts gemeldet werden; das ersetzt keine Polizeianzeige. Bei Geldschaden oder gestohlenen Dokumenten auch Bank und ausstellende Behörde informieren.", source: phishing)
        ], sources: [phishing]
    )
}
