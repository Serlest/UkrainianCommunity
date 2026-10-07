import Foundation

enum RegistrationGuides {
    private static let address = DirectorySource(name: "oesterreich.gv.at · Wohnsitz anmelden", url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180200")
    private static let form = DirectorySource(name: "oesterreich.gv.at · Meldezettel (PDF)", url: "https://www.oesterreich.gv.at/dam/jcr%3Ad0c97509-1a04-4b5a-8626-8a5f9e6b4b39/Meldezettel_2023_ausfuellbar.pdf")
    private static let change = DirectorySource(name: "oesterreich.gv.at · Ummeldung", url: "https://www.oesterreich.gv.at/de/lexicon/U/Seite.9911002html")
    private static let police = DirectorySource(name: "BMI · Erfassungsstellen Ukraine", url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    private static let authority = DirectorySource(name: "oesterreich.gv.at · Behördensuche", url: "https://www.oesterreich.gv.at/de/orgsearch")
    private static let bmiAppointments = DirectorySource(name: "oesterreich.gv.at · BMI-Termine", url: "https://www.oesterreich.gv.at/de/landingpages/Online_Terminvereinbarung")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "residence-registration": residence
        case "protection-registration": protection
        case "address-change": moving
        case "appointments": appointments
        default: nil
        }
    }

    private static let residence = DirectoryGuide(
        cardSummary: .init(ukrainian: "Строк, Meldezettel і потрібні документи", german: "Frist, Meldezettel und Unterlagen"),
        introduction: .init(ukrainian: "Реєстрація адреси (Wohnsitzmeldung) підтверджує, де ви фактично живете. Це окрема процедура від оформлення права на перебування.",
                            german: "Die Wohnsitzmeldung bestätigt Ihre tatsächliche Unterkunft. Sie ist vom Verfahren zum Aufenthaltsrecht getrennt."),
        sections: [
            .init("when", "calendar.badge.clock", "Коли й куди", "Wann und wo",
                  "Подайте заяву протягом трьох днів після фактичного заселення до Meldebehörde за новою адресою: Gemeindeamt або Magistrat, у Відні — Magistratisches Bezirksamt. Не реєструйте адресу до заселення.",
                  "Melden Sie sich binnen drei Tagen nach dem tatsächlichen Einzug bei der Meldebehörde der neuen Adresse an: Gemeindeamt oder Magistrat, in Wien ein Magistratisches Bezirksamt. Eine Anmeldung vor dem Einzug ist nicht zulässig."),
            .init("form", "doc.text.fill", "Форма Meldezettel", "Formular Meldezettel",
                  "Заповніть окремий Meldezettel для кожної людини. Його підписуєте ви та особа, яка фактично надає житло (Unterkunftgeber). Для неповнолітніх, які живуть з вами, також потрібна реєстрація.",
                  "Füllen Sie für jede Person einen eigenen Meldezettel aus. Sie und die Person, die Ihnen die Unterkunft tatsächlich gewährt (Unterkunftgeber), unterschreiben. Auch minderjährige Kinder im gemeinsamen Haushalt müssen gemeldet werden."),
            .init("documents", "person.text.rectangle", "Що взяти", "Unterlagen",
                  "Візьміть підписаний Meldezettel та офіційні документи для підтвердження імені, дати й місця народження та громадянства — наприклад паспорт і свідоцтво про народження. Для осіб без австрійського громадянства потрібен проїзний документ.",
                  "Bringen Sie den unterschriebenen Meldezettel sowie amtliche Urkunden zu Name, Geburtsdatum, Geburtsort und Staatsangehörigkeit mit, etwa Reisepass und Geburtsurkunde. Für Personen ohne österreichische Staatsbürgerschaft ist ein Reisedokument erforderlich."),
            .init("submit", "checkmark.seal.fill", "Подання і результат", "Abgabe und Ergebnis",
                  "Звернення можливе особисто, поштою або через уповноважену людину. Онлайн-сервіс доступний за окремих умов, зокрема якщо ви вже були зареєстровані в Австрії. Заява електронною поштою не приймається. Реєстрація безкоштовна; збережіть Meldebestätigung.",
                  "Die Meldung ist persönlich, postalisch oder durch eine Botin bzw. einen Boten möglich. Der Online-Dienst setzt unter anderem eine frühere Meldung in Österreich voraus. Eine Anmeldung per E-Mail ist nicht möglich. Die Anmeldung ist kostenlos; bewahren Sie die Meldebestätigung auf.")
        ],
        sources: [address, form]
    )

    private static let protection = DirectoryGuide(
        cardSummary: .init(ukrainian: "Поліція, документи й посвідчення переміщеної особи", german: "Polizei, Unterlagen und Ausweis für Vertriebene"),
        introduction: .init(ukrainian: "Для людей з України, які мають право на тимчасовий захист, потрібна реєстрація в поліції. Вона відрізняється від Meldezettel і не замінює реєстрацію адреси.",
                            german: "Für Menschen aus der Ukraine mit Anspruch auf vorübergehenden Schutz ist eine polizeiliche Erfassung nötig. Sie unterscheidet sich vom Meldezettel und ersetzt die Wohnsitzmeldung nicht."),
        sections: [
            .init("eligibility", "person.crop.rectangle", "Спочатку перевірте умови", "Zuerst Voraussetzungen prüfen",
                  "Право на тимчасовий захист залежить від вашої ситуації. Якщо ви вже мали захист в іншій країні або ваші документи неповні, прочитайте актуальні пояснення BMI перед зверненням.",
                  "Der Anspruch auf vorübergehenden Schutz hängt von Ihrer Situation ab. Wenn Sie bereits in einem anderen Land Schutz hatten oder Unterlagen fehlen, lesen Sie vor dem Termin die aktuellen Hinweise des BMI."),
            .init("office", "building.2.fill", "Знайдіть пункт поліції", "Erfassungsstelle finden",
                  "На сторінці BMI відкрийте перелік пунктів Erfassungsstellen. Виберіть пункт у вашій федеральній землі й перевірте адресу, години прийому та чи потрібен запис.",
                  "Öffnen Sie beim BMI die Liste der Erfassungsstellen. Wählen Sie eine Stelle in Ihrem Bundesland und prüfen Sie Adresse, Öffnungszeiten und Terminpflicht."),
            .init("papers", "doc.text.fill", "Підготуйте документи", "Unterlagen vorbereiten",
                  "Візьміть паспорт, свідоцтво про народження, документи про сімейний стан та інші посвідчення, які маєте. BMI радить звертатися навіть тоді, коли не вдалося взяти всі документи.",
                  "Nehmen Sie vorhandene Reisepässe, Geburtsurkunden, Personenstandsurkunden und andere Ausweise mit. Laut BMI sollten Sie sich auch erfassen lassen, wenn Sie nicht alle Unterlagen mitnehmen konnten."),
            .init("process", "person.text.rectangle", "Що відбувається під час реєстрації", "Ablauf der Erfassung",
                  "Поліція записує персональні дані й дані документів, робить фото та просить заповнити й підписати форму. У людей віком від 14 років також беруть відбитки пальців.",
                  "Die Polizei erfasst persönliche Daten und Dokumente, fertigt ein Foto an und lässt ein Formular ausfüllen und unterschreiben. Ab 14 Jahren werden auch Fingerabdrücke abgenommen."),
            .init("card", "envelope.fill", "Після реєстрації", "Nach der Erfassung",
                  "BFA надсилає посвідчення переміщеної особи на зареєстровану актуальну адресу або вказану адресу для доставки. Якщо для оформлення бракує даних, BFA зв'яжеться з вами. Стежте, щоб реєстрація вашої адреси залишалася актуальною.",
                  "Das BFA sendet den Ausweis für Vertriebene an die aktuelle Meldeadresse oder die angegebene Zustelladresse. Falls Angaben fehlen, meldet sich das BFA bei Ihnen. Halten Sie Ihre Wohnsitzmeldung aktuell.")
        ],
        sources: [police, address]
    )

    private static let moving = DirectoryGuide(
        cardSummary: .init(ukrainian: "Нова адреса та повідомлення установ", german: "Neue Adresse und wichtige Mitteilungen"),
        introduction: .init(ukrainian: "Нову адресу потрібно зареєструвати після переїзду. Слово Ummeldung у правилах також означає зміну головного й додаткового місця проживання — це інша ситуація.",
                            german: "Nach einem Umzug müssen Sie die neue Adresse anmelden. „Ummeldung“ bezeichnet im Melderecht auch den Wechsel zwischen Haupt- und Nebenwohnsitz – das ist ein anderer Fall."),
        sections: [
            .init("new", "house.fill", "Переїзд на нову адресу", "Umzug an eine neue Adresse",
                  "Зареєструйте нове місце проживання протягом трьох днів після заселення. Знадобиться новий Meldezettel з підписом особи, яка надає житло. При реєстрації нового головного місця проживання відповідний орган може одночасно зняти вас з обліку за попередньою адресою.",
                  "Melden Sie die neue Unterkunft binnen drei Tagen nach dem Einzug an. Sie benötigen einen neuen Meldezettel mit Unterschrift der Unterkunftgeberin bzw. des Unterkunftgebers. Bei Anmeldung eines neuen Hauptwohnsitzes kann die Behörde zugleich den bisherigen Wohnsitz abmelden."),
            .init("type", "arrow.left.arrow.right", "Головна й додаткова адреса", "Haupt- und Nebenwohnsitz",
                  "Якщо адреса не змінюється, але головне місце проживання стає додатковим або навпаки, діє процедура Ummeldung. Для неї офіційний портал указує строк один місяць.",
                  "Wenn die Adresse bleibt, aber ein Hauptwohnsitz zum Nebenwohnsitz wird oder umgekehrt, handelt es sich um eine Ummeldung. Dafür nennt das offizielle Portal eine Frist von einem Monat."),
            .init("notify", "envelope.fill", "Повідомте важливі установи", "Wichtige Stellen informieren",
                  "Оновіть адресу там, де від неї залежать листи або послуги. Для переміщених осіб з України чинна реєстрація адреси важлива, щоб BFA могло надіслати посвідчення та зв'язатися з вами.",
                  "Aktualisieren Sie Ihre Adresse dort, wo sie für Post oder Leistungen benötigt wird. Für Vertriebene aus der Ukraine ist die aktuelle Wohnsitzmeldung wichtig, damit das BFA den Ausweis zusenden und Kontakt aufnehmen kann.")
        ],
        sources: [address, change, police]
    )

    private static let appointments = DirectoryGuide(
        cardSummary: .init(ukrainian: "Знайдіть установу й підготуйтеся до візиту", german: "Behörde finden und Besuch vorbereiten"),
        introduction: .init(ukrainian: "Спочатку визначте, яка саме процедура потрібна. Реєстрація адреси, поліцейська реєстрація переміщених осіб та інші звернення мають різні установи й правила запису.",
                            german: "Klären Sie zuerst das Anliegen. Wohnsitzmeldung, polizeiliche Erfassung von Vertriebenen und andere Amtswege haben unterschiedliche Stellen und Terminregeln."),
        sections: [
            .init("choose", "building.2.fill", "Знайдіть відповідну установу", "Zuständige Stelle finden",
                  "Для адреси звертайтеся до Meldebehörde за новим місцем проживання. Для реєстрації переміщених осіб з України перевіряйте перелік пунктів поліції на сайті BMI. Для інших питань скористайтеся пошуком установ на oesterreich.gv.at.",
                  "Für die Wohnsitzmeldung ist die Meldebehörde der neuen Adresse zuständig. Für die Erfassung von Vertriebenen aus der Ukraine prüfen Sie die Polizeistellen beim BMI. Für andere Anliegen nutzen Sie die Behördensuche auf oesterreich.gv.at."),
            .init("check", "calendar", "Перевірте порядок прийому", "Terminregel prüfen",
                  "На сторінці конкретної установи перевірте години роботи, потребу в попередньому записі та документи. Центральний сервіс запису BMI охоплює лише перелічені там процедури; він не замінює записи всіх місцевих установ.",
                  "Prüfen Sie auf der Seite der konkreten Stelle Öffnungszeiten, Terminpflicht und Unterlagen. Der zentrale BMI-Terminservice gilt nur für die dort aufgeführten Anliegen und ersetzt nicht die Buchung bei allen lokalen Behörden."),
            .init("prepare", "doc.on.doc.fill", "Перед візитом", "Vor dem Besuch",
                  "Збережіть підтвердження запису, адресу установи та перелік потрібних документів. Якщо процедура термінова, зокрема реєстрація адреси в триденний строк, орієнтуйтеся на офіційно дозволені способи подання.",
                  "Bewahren Sie Terminbestätigung, Anschrift und Unterlagenliste auf. Bei fristgebundenen Anliegen wie der Wohnsitzmeldung innerhalb von drei Tagen prüfen Sie die amtlich erlaubten Einreichwege.")
        ],
        sources: [address, police, authority, bmiAppointments]
    )
}
