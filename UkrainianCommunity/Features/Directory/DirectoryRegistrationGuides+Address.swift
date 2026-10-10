import Foundation

extension RegistrationGuides {
    static let residence = DirectoryGuide(
        cardSummary: .init(ukrainian: "Строк, підпис на Meldezettel і подання",
                           german: "Frist, Unterschrift und Abgabe des Meldezettels"),
        introduction: .init(ukrainian: "Реєстрація адреси повідомляє державі, де ви фактично живете. Вона не замінює поліцейську реєстрацію для тимчасового захисту.",
                            german: "Die Wohnsitzmeldung erfasst, wo Sie tatsächlich wohnen. Sie ersetzt nicht die polizeiliche Erfassung für vorübergehenden Schutz."),
        sections: [
            .init("when", "calendar.badge.clock", "Коли й куди", "Wann und wo",
                  "Зареєструйте адресу протягом трьох днів після фактичного заселення у Meldebehörde за місцем проживання: Gemeindeamt або Magistrat, у Відні — Magistratisches Bezirksamt. До заселення реєструватися не можна.",
                  "Melden Sie Ihre Adresse binnen drei Tagen nach dem tatsächlichen Einzug bei der Meldebehörde an: Gemeindeamt oder Magistrat, in Wien beim Magistratischen Bezirksamt. Vor dem Einzug ist eine Anmeldung nicht zulässig.", source: addressSource),
            .init("form", "doc.text.fill", "Заповніть Meldezettel", "Meldezettel ausfüllen",
                  "Для кожної людини, зокрема дитини, потрібен окремий Meldezettel. Ви підписуєте свої дані, а особа, яка фактично надала вам житло (Unterkunftgeber), підтверджує проживання власним підписом. Підписати може й головний орендар, який вас поселив.",
                  "Für jede Person, auch für jedes Kind, ist ein eigener Meldezettel nötig. Sie unterschreiben Ihre Angaben; die Person, die Ihnen tatsächlich Unterkunft gewährt (Unterkunftgeber), bestätigt dies mit ihrer Unterschrift. Das kann auch die Hauptmieterin oder der Hauptmieter sein, die bzw. der Sie aufnimmt.", source: formSource),
            .init("documents", "person.text.rectangle", "Підготуйте документи", "Unterlagen vorbereiten",
                  "Візьміть підписаний Meldezettel та офіційні документи про ім’я, дату й місце народження та громадянство — наприклад паспорт і свідоцтво про народження. Для людей без австрійського громадянства офіційний перелік також називає проїзний документ; якщо його немає, уточніть порядок у Meldebehörde.",
                  "Bringen Sie den unterschriebenen Meldezettel und amtliche Urkunden zu Name, Geburtsdatum, Geburtsort und Staatsangehörigkeit mit, etwa Reisepass und Geburtsurkunde. Für Personen ohne österreichische Staatsbürgerschaft nennt die amtliche Liste außerdem ein Reisedokument; fehlt es, klären Sie das Vorgehen mit der Meldebehörde.", source: addressSource),
            .init("submit", "checkmark.seal.fill", "Подайте заяву й збережіть результат", "Meldung abgeben und Bestätigung aufbewahren",
                  "Подати можна особисто, поштою або через посильного; для останніх двох способів потрібні оригінали документів або нотаріально чи судово засвідчені копії. Онлайн-сервіс потребує ID Austria чи EU Login і попередньої реєстрації в Австрії. Електронна пошта й факс не приймаються. Процедура безкоштовна; збережіть Meldebestätigung.",
                  "Die Abgabe ist persönlich, postalisch oder durch einen Boten möglich; bei den letzten beiden Wegen sind Originalurkunden oder notariell bzw. gerichtlich beglaubigte Abschriften nötig. Der Online-Dienst erfordert ID Austria oder EU Login und eine frühere Meldung in Österreich. E-Mail und Fax sind nicht zulässig. Die Meldung ist kostenlos; bewahren Sie die Meldebestätigung auf.", source: addressSource)
        ],
        sources: [addressSource, formSource]
    )

    static let housingTypes = DirectoryGuide(
        cardSummary: .init(ukrainian: "Приватне, організоване, готель, без адреси чи транзит",
                           german: "Privat, organisiert, Hotel, ohne Adresse oder Transit"),
        introduction: .init(ukrainian: "Оберіть саме свою ситуацію з житлом. Правила відрізняються; не використовуйте адресу, за якою ви фактично не живете.",
                            german: "Wählen Sie Ihre tatsächliche Wohnsituation. Die Regeln unterscheiden sich; verwenden Sie keine Adresse, an der Sie nicht wohnen."),
        sections: [
            .init("private", "house.fill", "Живете в когось приватно", "Sie wohnen privat bei jemandem",
                  "Якщо ви живете у знайомих або орендуєте кімнату, зареєструйте фактичну адресу. Підпис Unterkunftgeber ставить той, хто вас справді поселив: власник, головний орендар або навіть піднаймач. Виняток для безоплатного проживання до двох місяців можливий лише тоді, коли ви вже зареєстровані в іншому місці Австрії; для новоприбулих це не загальне звільнення.",
                  "Wenn Sie bei Bekannten oder in einem gemieteten Zimmer wohnen, melden Sie die tatsächliche Adresse. Als Unterkunftgeber unterschreibt die Person, die Sie tatsächlich aufgenommen hat: Eigentümer, Hauptmieter oder auch Untermieter. Die Ausnahme für höchstens zwei Monate kostenlose Unterkunft gilt nur, wenn Sie bereits anderswo in Österreich gemeldet sind; für Neuankommende ist das keine allgemeine Befreiung.", source: addressSource),
            .init("organized", "building.2.fill", "Організоване житло", "Organisierte Unterkunft",
                  "Якщо вас розмістили в житлі системи Grundversorgung, надавач житла організовує реєстрацію; працівники закладу можуть допомогти. Перевірте, що ваша адреса справді внесена, і збережіть підтвердження. Заяву на головне місце проживання ви підписуєте самі.",
                  "Bei organisierter Unterkunft im Rahmen der Grundversorgung veranlasst der Quartiergeber die Meldung; das Betreuungsteam kann helfen. Prüfen Sie, ob Ihre Adresse tatsächlich eingetragen wurde, und bewahren Sie die Bestätigung auf. Den Antrag auf Hauptwohnsitzmeldung unterschreiben Sie selbst.", source: registrationSource),
            .init("hotel", "bed.double.fill", "Готель чи пансіон", "Hotel oder Pension",
                  "Готель чи інший заклад розміщення записує гостей за правилами Gästeblatt. Якщо ви залишаєтеся надовго або переїжджаєте в окреме житло, уточніть у Meldebehörde, чи потрібна додаткова реєстрація адреси.",
                  "Ein Hotel oder anderer Beherbergungsbetrieb trägt Gäste nach den Regeln zum Gästeblatt ein. Bei längerem Aufenthalt oder Wechsel in eine eigene Unterkunft klären Sie mit der Meldebehörde, ob eine zusätzliche Wohnsitzmeldung nötig ist.", source: addressSource),
            .init("without", "questionmark.circle.fill", "Немає постійної адреси", "Keine feste Unterkunft",
                  "Не реєструйте вигадану адресу. Якщо ви без житла, зверніться до Meldebehörde і соціальної служби. Hauptwohnsitzbestätigung для бездомних має окремі умови: зокрема, щонайменше місяць центру життєвих інтересів у цій громаді та контактне місце, яке ви регулярно відвідуєте. Це не миттєва заміна Meldezettel після прибуття.",
                  "Melden Sie keine fiktive Adresse. Ohne Unterkunft wenden Sie sich an Meldebehörde und Sozialberatung. Eine Hauptwohnsitzbestätigung für Obdachlose hat eigene Voraussetzungen: insbesondere seit mindestens einem Monat den Lebensmittelpunkt in der Gemeinde und eine regelmäßig aufgesuchte Kontaktstelle. Sie ersetzt nicht sofort nach Ankunft den Meldezettel.", source: addressSource),
            .init("transit", "clock.fill", "Лише короткий транзит", "Nur kurzer Transit",
                  "Якщо житло в Австрії надано не довше ніж на три дні, закон передбачає виняток із обов’язку реєстрації адреси. Це не означає автоматичного звільнення від інших процедур, якщо ви вирішили залишитися в Австрії.",
                  "Wird Ihnen in Österreich höchstens drei Tage Unterkunft gewährt, gilt eine Ausnahme von der Wohnsitzmeldung. Das befreit Sie nicht automatisch von anderen Verfahren, wenn Sie sich für einen Aufenthalt in Österreich entscheiden.", source: addressSource)
        ],
        sources: [addressSource, registrationSource]
    )
}
