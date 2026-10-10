import Foundation

enum FirstStepsGuides {
    private static let bbu = DirectorySource(name: "BBU · Ukraine", url: "https://www.bbu.gv.at/ukraine")
    private static let bbuUK = DirectorySource(name: "BBU · Інформація українською", url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")
    private static let police = DirectorySource(name: "BMI · Erfassung und Aufenthalt", url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    private static let housing = DirectorySource(name: "BMI · Unterkunft suchen", url: "https://www.bmi.gv.at/ukraine/suche_unterkunft.html")
    private static let integration = DirectorySource(name: "ÖIF · Integrationsberatung", url: "https://www.integrationsfonds.at/angebote/integrationsmassnahmen/integrationsberatung/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "arrival": arrival
        case "checklist": checklist
        default: nil
        }
    }

    private static let arrival = DirectoryGuide(
        cardSummary: .init(ukrainian: "Приватне житло або перевірка місць через BBU", german: "Private Unterkunft oder freie Plätze bei der BBU prüfen"),
        introduction: .init(ukrainian: "Спочатку з’ясуйте, де безпечно переночувати. Наявність організованого житла потрібно перевіряти перед поїздкою.",
                            german: "Klären Sie zuerst, wo Sie sicher übernachten können. Prüfen Sie organisierte Unterkünfte vor der Anreise."),
        sections: [
            .init("shelter", "house.fill", "Де жити сьогодні", "Unterkunft für heute",
                  "Якщо ви прибули з України без житла, перевірте на сторінці BBU таблицю пунктів первинного прийому або телефонуйте +43 1 2676 870 9460. Не кожен пункт має місця для ночівлі: зокрема, консультаційний центр у Відні їх не надає. Уточніть умови саме своєї землі до поїздки; для першого прибуття, втрати житла й повторного в’їзду можуть діяти різні правила.",
                  "Wenn Sie aus der Ukraine ohne Unterkunft ankommen, prüfen Sie die Erstankunftstabelle der BBU oder rufen Sie +43 1 2676 870 9460 an. Nicht jede Anlaufstelle bietet Schlafplätze; das Wiener Beratungszentrum etwa nicht. Klären Sie die Regeln Ihres Bundeslandes vor der Anreise: Für Ersteinreise, Wohnungsverlust und erneute Einreise können unterschiedliche Bedingungen gelten.", phoneNumber: "+43 1 2676 870 9460"),
            .init("address", "mappin.and.ellipse", "Фактична адреса", "Tatsächliche Wohnadresse",
                  "Якщо ви оселилися приватно, уточніть, хто підпише Meldezettel. Після фактичного заселення зареєструйте адресу протягом трьох днів; докладні кроки є в розділі «Реєстрація».",
                  "Bei privater Unterkunft klären Sie, wer den Meldezettel unterschreibt. Melden Sie die Adresse binnen drei Tagen nach dem tatsächlichen Einzug; die Schritte stehen im Bereich „Anmeldung“."),
            .init("medical", "cross.case.fill", "Якщо потрібна невідкладна медична допомога", "Bei einem medizinischen Notfall",
                  "Телефонуйте 144 або 112. Невідкладну допомогу нададуть і до оформлення документів, але витрати не завжди покриваються автоматично. Повідомте лікарні, що ви щойно прибули, і якнайшвидше уточніть страхування та можливість базового забезпечення.",
                  "Rufen Sie 144 oder 112 an. Notfallversorgung ist auch vor der Registrierung möglich, die Kosten werden aber nicht automatisch übernommen. Sagen Sie dem Krankenhaus, dass Sie gerade angekommen sind, und klären Sie Versicherung und Grundversorgung so bald wie möglich.")
        ],
        sources: [bbu, bbuUK, housing]
    )

    private static let checklist = DirectoryGuide(
        cardSummary: .init(ukrainian: "Адреса, поліція, підтримка й наступні звернення", german: "Adresse, Polizei, Versorgung und weitere Wege"),
        introduction: .init(ukrainian: "Орієнтир для людей, які прибули з України. Реєстрація адреси, поліцейська реєстрація та заява на допомогу — три різні дії.",
                            german: "Orientierung für Menschen aus der Ukraine. Wohnsitzmeldung, polizeiliche Erfassung und Antrag auf Grundversorgung sind drei verschiedene Schritte."),
        sections: [
            .init("one", "1.circle.fill", "1. Знайдіть житло", "1. Unterkunft klären",
                  "Маєте приватне житло — уточніть, хто підпише Meldezettel. Не маєте житла — перевірте актуальні можливості первинного прийому в BBU, перш ніж їхати до центру.",
                  "Bei privater Unterkunft klären Sie die Unterschrift auf dem Meldezettel. Ohne Unterkunft prüfen Sie bei der BBU die aktuellen Erstankunftsmöglichkeiten vor der Anreise."),
            .init("two", "2.circle.fill", "2. Зареєструйте адресу", "2. Wohnadresse anmelden",
                  "Після фактичного заселення подайте Meldezettel до відповідного Gemeindeamt або Magistrat упродовж трьох днів. Збережіть підтвердження реєстрації.",
                  "Melden Sie nach dem tatsächlichen Einzug Ihre Adresse binnen drei Tagen beim zuständigen Gemeindeamt oder Magistrat an. Bewahren Sie die Meldebestätigung auf."),
            .init("three", "3.circle.fill", "3. З'ясуйте підставу перебування", "3. Aufenthaltsgrund klären",
                  "Якщо ви маєте право на тимчасовий захист як переміщена особа з України, пройдіть реєстрацію в поліції. Це окрема процедура від реєстрації адреси. За інших підстав перевіряйте правила свого статусу в компетентному органі.",
                  "Wenn Sie als aus der Ukraine vertriebene Person Anspruch auf vorübergehenden Schutz haben, lassen Sie sich polizeilich erfassen. Das ist ein anderer Vorgang als die Wohnsitzmeldung. Bei anderen Aufenthaltsgründen gelten die Regeln des jeweiligen Status."),
            .init("four", "4.circle.fill", "4. Запитайте про підтримку", "4. Unterstützung klären",
                  "Якщо потрібні гроші, житло чи страхування, дізнайтеся, як подати заяву на Grundversorgung у вашій федеральній землі. Поліцейська реєстрація сама по собі не є заявою на допомогу.",
                  "Wenn Sie Geld, Unterkunft oder Versicherung benötigen, klären Sie den Antrag auf Grundversorgung in Ihrem Bundesland. Die polizeiliche Erfassung ist noch kein Antrag auf Hilfe."),
            .init("five", "5.circle.fill", "5. Перевірте медичне страхування", "5. Krankenversicherung prüfen",
                  "Тимчасовий захист сам по собі не дає автоматичного медичного страхування. З’ясуйте, чи ви застраховані через роботу, члена сім’ї, самостійно або в межах Grundversorgung.",
                  "Vorübergehender Schutz allein bewirkt keine automatische Krankenversicherung. Prüfen Sie Versicherung durch Arbeit, Angehörige, Selbstversicherung oder Grundversorgung."),
            .init("six", "6.circle.fill", "6. Діти, робота й мова", "6. Kinder, Arbeit und Deutsch",
                  "Для дітей уточніть школу чи дитсадок. Для пошуку роботи зверніться до AMS, для курсів німецької й орієнтації — до ÖIF. Зберігайте документи та листи від установ.",
                  "Klären Sie Schule oder Kindergarten für Kinder. Für die Arbeitssuche wenden Sie sich an das AMS, für Deutschkurse und Orientierung an den ÖIF. Bewahren Sie Unterlagen und Behördenschreiben auf.")
        ],
        sources: [bbu, bbuUK, police, integration]
    )
}
