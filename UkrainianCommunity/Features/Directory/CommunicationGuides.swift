import Foundation

enum CommunicationGuides {
    private static let contracts = DirectorySource(name: "RTR · Telefon- und Internetverträge", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_Vertraege.de.html")
    private static let billing = DirectorySource(name: "RTR · Rechnungen für Telekom und Internet", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_Rechnung.de.html")
    private static let dispute = DirectorySource(name: "RTR · Einspruch und Schlichtung", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/faq/einspruch_und_schlichtung.de.html")
    private static let post = DirectorySource(name: "Österreichische Post · Briefempfang", url: "https://www.post.at/p/c/brief-empfangen")
    private static let forwardingTariff = DirectorySource(name: "Österreichische Post · Nachsendeauftrag und Tarife", url: "https://www.post.at/p/a/nachsenden")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "phone": return phone
        case "internet": return internet
        case "postal": return postal
        default: return nil
        }
    }

    private static let phone = DirectoryGuide(
        cardSummary: .init(ukrainian: "SIM, тарифи, роумінг і спірний рахунок", german: "SIM, Tarife, Roaming und strittige Rechnung"),
        introduction: .init(ukrainian: "Для австрійського номера оберіть передплачену SIM або договір. Перевірте повну ціну та умови виходу до активації.", german: "Für eine österreichische Nummer zwischen Wertkarte und Vertrag wählen. Gesamtpreis und Ausstieg vor Aktivierung prüfen."),
        sections: [
            .init("choose", "simcard", "Оберіть тариф", "Tarif wählen", "Порівняйте щомісячну плату, активацію, обсяг даних, хвилини, роумінг і мінімальний строк. Передплачена SIM теж потребує ідентифікації; запитайте про можливу плату за реєстрацію. Збережіть тарифний лист і підтвердження умов.", "Grundentgelt, Aktivierung, Daten, Minuten, Roaming und Bindung vergleichen. Auch Wertkarten brauchen Identifizierung; mögliche Registrierungsentgelte erfragen. Tarifblatt und Vertragsbestätigung sichern.", source: contracts),
            .init("move", "arrow.left.arrow.right", "При переїзді або зміні номера", "Bei Umzug oder Nummernwechsel", "Оновіть номер у банку, ID Austria, лікаря та установах, де отримуєте коди. Перед розірванням договору перевірте мінімальний строк, письмову форму й останній рахунок; перенесення номера узгодьте з новим оператором.", "Nummer bei Bank, ID Austria, Arzt und Behörden mit Freigabecodes ändern. Vor Kündigung Bindung, Form und Schlussrechnung prüfen; Rufnummernmitnahme mit neuem Anbieter abstimmen.", source: contracts),
            .init("invoice", "doc.text.magnifyingglass", "Оскаржте неправильний рахунок", "Falsche Rechnung beeinspruchen", "Звірте тариф і деталізацію. Письмовий Einspruch оператору потрібно подати протягом трьох місяців від отримання рахунка; сам Einspruch не зупиняє строк оплати. Для відстрочки спірної суми та посередництва зверніться до RTR, зберігши листи й рахунки.", "Tarif und Einzelentgelte prüfen. Schriftlichen Einspruch binnen drei Monaten nach Rechnungserhalt an den Anbieter richten; er hemmt die Fälligkeit nicht. Für Aufschub der strittigen Summe und Schlichtung RTR kontaktieren; Schreiben und Rechnungen aufbewahren.", source: billing)
        ], sources: [contracts, billing, dispute]
    )

    private static let internet = DirectoryGuide(
        cardSummary: .init(ukrainian: "Домашній інтернет, строк договору та проблеми зі зв’язком", german: "Festnetz, Vertragsbindung und Verbindungsprobleme"),
        introduction: .init(ukrainian: "Уточніть доступність послуги саме за адресою житла та хто відповідає за підключення.", german: "Verfügbarkeit an der konkreten Wohnadresse und Zuständigkeit für den Anschluss klären."),
        sections: [
            .init("before", "wifi", "До замовлення", "Vor Bestellung", "Перевірте доступну технологію, заявлену швидкість, активацію, вартість роутера, монтаж і мінімальний строк. Якщо ви орендуєте житло, погодьте свердління або кабельні роботи з власником. Попросіть письмове резюме договору.", "Technik, zugesagte Geschwindigkeit, Aktivierung, Router, Installation und Bindung prüfen. Bohrungen oder Leitungsarbeiten in Mietwohnung mit Vermieter abstimmen. Vertragszusammenfassung schriftlich verlangen.", source: contracts),
            .init("fault", "waveform.path", "Якщо інтернет не працює", "Wenn die Verbindung ausfällt", "Перевірте живлення й кабелі, запишіть час перерви та зверніться до служби підтримки з номером договору. Збережіть номер звернення й вимірювання, які оператор просить зробити. Узгодьте ремонт і письмове пояснення доцільності знижки за тривалу проблему.", "Strom und Kabel prüfen, Ausfallzeiten notieren und mit Vertragsnummer beim Support melden. Ticketnummer und vom Anbieter angeforderte Messungen aufbewahren. Reparatur und mögliche Entgeltminderung bei längerem Mangel schriftlich klären.", source: dispute),
            .init("cancel", "arrow.uturn.backward", "Завершення договору при переїзді", "Vertrag beim Umzug beenden", "Переїзд сам по собі не гарантує безкоштовного дострокового розірвання. Запитайте провайдера, чи можна перенести послугу на нову адресу та скільки це коштує. Звірте мінімальний строк; після його завершення для споживача строк розірвання зазвичай не може бути довшим за місяць. Надішліть заяву доказово й дочекайтеся письмового підтвердження та кінцевого рахунка.", "Umzug erlaubt nicht automatisch kostenlose vorzeitige Vertragsauflösung. Anbieter nach Verfügbarkeit und Kosten an neuer Adresse fragen. Mindestbindung prüfen; danach darf die Kündigungsfrist für Verbraucher grundsätzlich höchstens einen Monat betragen. Nachweisbar kündigen und Bestätigung sowie Schlussrechnung sichern.", source: contracts)
        ], sources: [contracts, dispute]
    )

    private static let postal = DirectoryGuide(
        cardSummary: .init(ukrainian: "Адреса для листів, переадресація та важливі повідомлення", german: "Postadresse, Nachsendung und wichtige Zustellungen"),
        introduction: .init(ukrainian: "Листи установ можуть містити строки. Після переїзду оновіть адресу безпосередньо в кожній установі.", german: "Behördenbriefe können Fristen auslösen. Nach Umzug die Adresse bei jeder Stelle direkt ändern."),
        sections: [
            .init("receive", "envelope", "Організуйте отримання", "Empfang organisieren", "Переконайтеся, що ім’я на скриньці та дзвінку збігається з документами. Якщо немає надійної скриньки, запитайте про Postlagernd або Postfach та їхні умови. Перевіряйте повідомлення про рекомендовані листи й строки зберігання.", "Namen an Briefkasten und Klingel wie in den Dokumenten angeben. Ohne sicheren Briefkasten Postlagernd oder Postfach samt Bedingungen prüfen. Verständigungen über eingeschriebene Sendungen und Abholfristen beachten.", source: post),
            .init("forward", "arrowshape.turn.up.right", "Переадресація при переїзді", "Nachsendung beim Umzug", "Оформіть Nachsendeauftrag щонайменше за три робочі дні до переїзду. Станом на 2026 рік пересилання листів і дрібних відправлень у межах Австрії коштує 21,90 € за перші три календарні місяці; посилки оплачуються окремо. Пошта пересилає лише відправлення, передані їй, а не іншим службам доставки. Це не замінює зміну адреси в банку, страховика та установах.", "Nachsendeauftrag mindestens drei Werktage vor dem Umzug einrichten. Stand 2026 kosten Briefe und Päckchen innerhalb Österreichs 21,90 € für die ersten drei Kalendermonate; Pakete kosten extra. Die Post leitet nur Sendungen weiter, die ihr selbst übergeben wurden. Adressänderung bei Bank, Kasse und Behörden bleibt nötig.", source: forwardingTariff),
            .init("proof", "checkmark.seal", "Збережіть підтвердження", "Nachweise behalten", "Для заяв і скарг зберігайте копію, чек відправлення, номер відстеження та дату вручення. Якщо потрібне підтвердження подання до певного дня, завчасно перевірте, чи відповідна установа приймає електронне подання або пошту і яка дата вважається своєчасною.", "Für Anträge und Beschwerden Kopie, Einlieferungsbeleg, Sendungsnummer und Zustelldatum sichern. Vor Fristablauf prüfen, ob die konkrete Behörde elektronische oder postalische Einbringung akzeptiert und welcher Zeitpunkt zählt.", source: post)
        ], sources: [post, forwardingTariff]
    )
}
