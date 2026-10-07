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
                  "Melden Sie Ihre Adresse binnen drei Tagen nach dem tatsächlichen Einzug bei der Meldebehörde an: Gemeindeamt oder Magistrat, in Wien beim Magistratischen Bezirksamt. Vor dem Einzug ist eine Anmeldung nicht zulässig."),
            .init("form", "doc.text.fill", "Заповніть Meldezettel", "Meldezettel ausfüllen",
                  "Для кожної людини, зокрема дитини, потрібен окремий Meldezettel. Ви підписуєте свої дані, а особа, яка фактично надала вам житло (Unterkunftgeber), підтверджує проживання власним підписом. Підписати може й головний орендар, який вас поселив.",
                  "Für jede Person, auch für jedes Kind, ist ein eigener Meldezettel nötig. Sie unterschreiben Ihre Angaben; die Person, die Ihnen tatsächlich Unterkunft gewährt (Unterkunftgeber), bestätigt dies mit ihrer Unterschrift. Das kann auch die Hauptmieterin oder der Hauptmieter sein, die bzw. der Sie aufnimmt."),
            .init("documents", "person.text.rectangle", "Підготуйте документи", "Unterlagen vorbereiten",
                  "Візьміть підписаний Meldezettel та офіційні документи про ім’я, дату й місце народження та громадянство — наприклад паспорт і свідоцтво про народження. Для людей без австрійського громадянства офіційний перелік також називає проїзний документ; якщо його немає, уточніть порядок у Meldebehörde.",
                  "Bringen Sie den unterschriebenen Meldezettel und amtliche Urkunden zu Name, Geburtsdatum, Geburtsort und Staatsangehörigkeit mit, etwa Reisepass und Geburtsurkunde. Für Personen ohne österreichische Staatsbürgerschaft nennt die amtliche Liste außerdem ein Reisedokument; fehlt es, klären Sie das Vorgehen mit der Meldebehörde."),
            .init("submit", "checkmark.seal.fill", "Подайте заяву й збережіть результат", "Meldung abgeben und Bestätigung aufbewahren",
                  "Подати можна особисто, поштою або через посильного; для останніх двох способів потрібні оригінали документів або нотаріально чи судово засвідчені копії. Онлайн-сервіс потребує ID Austria чи EU Login і попередньої реєстрації в Австрії. Електронна пошта й факс не приймаються. Процедура безкоштовна; збережіть Meldebestätigung.",
                  "Die Abgabe ist persönlich, postalisch oder durch einen Boten möglich; bei den letzten beiden Wegen sind Originalurkunden oder notariell bzw. gerichtlich beglaubigte Abschriften nötig. Der Online-Dienst erfordert ID Austria oder EU Login und eine frühere Meldung in Österreich. E-Mail und Fax sind nicht zulässig. Die Meldung ist kostenlos; bewahren Sie die Meldebestätigung auf.")
        ],
        sources: [addressSource, formSource]
    )

    static let housingTypes = DirectoryGuide(
        cardSummary: .init(ukrainian: "Приватне житло, центр прийому, готель або бездомність",
                           german: "Privatquartier, organisierte Unterkunft, Hotel oder Obdachlosigkeit"),
        introduction: .init(ukrainian: "Спосіб повідомлення адреси залежить від виду житла. Не вказуйте адресу, за якою ви не живете.",
                            german: "Wie die Adresse gemeldet wird, hängt von der Unterkunft ab. Geben Sie keine Adresse an, an der Sie nicht wohnen."),
        sections: [
            .init("private", "house.fill", "Живете в когось приватно", "Sie wohnen privat bei jemandem",
                  "Після заселення подайте Meldezettel протягом трьох днів. Його підписує людина, яка фактично надала вам житло: власник, головний орендар або інша відповідальна особа. Договір оренди сам по собі не замінює реєстрації.",
                  "Nach dem Einzug geben Sie binnen drei Tagen den Meldezettel ab. Es unterschreibt die Person, die Ihnen die Unterkunft tatsächlich gewährt: Eigentümerin oder Eigentümer, Hauptmieterin oder Hauptmieter oder eine andere zuständige Person. Ein Mietvertrag ersetzt die Meldung nicht."),
            .init("organized", "building.2.fill", "Організоване житло", "Organisierte Unterkunft",
                  "Якщо вас розмістили в житлі системи Grundversorgung, надавач житла організовує реєстрацію; працівники закладу можуть допомогти. Перевірте, що ваша адреса справді внесена, і збережіть підтвердження. Заяву на головне місце проживання ви підписуєте самі.",
                  "Bei organisierter Unterkunft im Rahmen der Grundversorgung veranlasst der Quartiergeber die Meldung; das Betreuungsteam kann helfen. Prüfen Sie, ob Ihre Adresse tatsächlich eingetragen wurde, und bewahren Sie die Bestätigung auf. Den Antrag auf Hauptwohnsitzmeldung unterschreiben Sie selbst."),
            .init("hotel", "bed.double.fill", "Готель чи пансіон", "Hotel oder Pension",
                  "Готель чи інший заклад розміщення записує гостей за правилами Gästeblatt. Якщо ви залишаєтеся надовго або переїжджаєте в окреме житло, уточніть у Meldebehörde, чи потрібна додаткова реєстрація адреси.",
                  "Ein Hotel oder anderer Beherbergungsbetrieb trägt Gäste nach den Regeln zum Gästeblatt ein. Bei längerem Aufenthalt oder Wechsel in eine eigene Unterkunft klären Sie mit der Meldebehörde, ob eine zusätzliche Wohnsitzmeldung nötig ist."),
            .init("without", "questionmark.circle.fill", "Немає постійної адреси", "Keine feste Unterkunft",
                  "Не реєструйте вигадану адресу. Якщо ви без житла, зверніться до Meldebehörde і соціальної служби. Hauptwohnsitzbestätigung для бездомних має окремі умови: зокрема, щонайменше місяць центру життєвих інтересів у цій громаді та контактне місце, яке ви регулярно відвідуєте. Це не миттєва заміна Meldezettel після прибуття.",
                  "Melden Sie keine fiktive Adresse. Ohne Unterkunft wenden Sie sich an Meldebehörde und Sozialberatung. Eine Hauptwohnsitzbestätigung für Obdachlose hat eigene Voraussetzungen: insbesondere seit mindestens einem Monat den Lebensmittelpunkt in der Gemeinde und eine regelmäßig aufgesuchte Kontaktstelle. Sie ersetzt nicht sofort nach Ankunft den Meldezettel."),
            .init("transit", "clock.fill", "Лише короткий транзит", "Nur kurzer Transit",
                  "Якщо житло в Австрії надано не довше ніж на три дні, закон передбачає виняток із обов’язку реєстрації адреси. Це не означає автоматичного звільнення від інших процедур, якщо ви вирішили залишитися в Австрії.",
                  "Wird Ihnen in Österreich höchstens drei Tage Unterkunft gewährt, gilt eine Ausnahme von der Wohnsitzmeldung. Das befreit Sie nicht automatisch von anderen Verfahren, wenn Sie sich für einen Aufenthalt in Österreich entscheiden.")
        ],
        sources: [addressSource, registrationSource]
    )
}
