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
        case "initial-support": support
        default: nil
        }
    }

    private static let arrival = DirectoryGuide(
        cardSummary: .init(ukrainian: "Житло, адреса й статус після прибуття", german: "Unterkunft, Adresse und Status nach Ankunft"),
        introduction: .init(ukrainian: "Почніть із безпечного місця для проживання. Наступні дії залежать від вашої ситуації та підстави перебування.",
                            german: "Sorgen Sie zuerst für eine sichere Unterkunft. Die nächsten Schritte hängen von Ihrer Situation und Ihrem Aufenthaltsgrund ab."),
        sections: [
            .init("shelter", "house.fill", "Де жити сьогодні", "Unterkunft für heute",
                  "Якщо у вас немає житла й ви прибули з України, перевірте актуальні можливості первинного прийому на сайті BBU або зателефонуйте на їхню лінію +43 1 2676 870 9460. Місця та умови змінюються; не вирушайте до центру без перевірки.",
                  "Wenn Sie aus der Ukraine kommen und keine Unterkunft haben, prüfen Sie die aktuellen Erstankunftsmöglichkeiten bei der BBU oder rufen Sie +43 1 2676 870 9460 an. Plätze und Bedingungen ändern sich; prüfen Sie sie vor der Anreise.", phoneNumber: "+43 1 2676 870 9460"),
            .init("address", "mappin.and.ellipse", "Фактична адреса", "Tatsächliche Wohnadresse",
                  "Коли ви заселилися, дізнайтеся, хто підписує Meldezettel, і зареєструйте адресу в установлені три дні. Для короткого перебування до трьох днів діє виняток. Деталі є в окремому розділі «Реєстрація».",
                  "Nach dem Einzug klären Sie, wer den Meldezettel unterschreibt, und melden die Adresse innerhalb von drei Tagen an. Für Aufenthalte bis zu drei Tagen gibt es eine Ausnahme. Details stehen im Bereich „Anmeldung“."),
            .init("protection", "person.crop.rectangle", "Якщо ви шукаєте захисту з України", "Wenn Sie Schutz aus der Ukraine suchen",
                  "Для посвідчення переміщеної особи потрібна окрема реєстрація в поліції. Перевірте пункт прийому, години та потребу в записі на сторінці BMI. Візьміть паспорт та інші документи, які маєте; звернутися можна і без повного комплекту.",
                  "Für den Ausweis für Vertriebene ist eine gesonderte Erfassung durch die Polizei nötig. Prüfen Sie Stelle, Öffnungszeiten und Terminpflicht beim BMI. Nehmen Sie vorhandene Ausweise und Urkunden mit; die Erfassung ist auch ohne vollständige Unterlagen möglich."),
            .init("next", "arrow.forward.circle.fill", "Що далі", "Danach",
                  "Якщо потрібна базова підтримка, уточніть подання заяви у вашій федеральній землі. Для мовних курсів і орієнтації можна звернутися до Австрійського інтеграційного фонду (ÖIF).",
                  "Wenn Sie Grundversorgung benötigen, klären Sie den Antrag in Ihrem Bundesland. Für Deutschkurse und Orientierung können Sie sich an den Österreichischen Integrationsfonds (ÖIF) wenden.")
        ],
        sources: [bbu, housing, police, integration]
    )

    private static let checklist = DirectoryGuide(
        cardSummary: .init(ukrainian: "Кроки на перші дні в Австрії", german: "Schritte für die ersten Tage in Österreich"),
        introduction: .init(ukrainian: "Послідовність для першого часу. Виконуйте лише ті кроки, які стосуються вашої ситуації.",
                            german: "Eine Reihenfolge für die erste Zeit. Gehen Sie nur die Schritte durch, die auf Ihre Situation zutreffen."),
        sections: [
            .init("one", "1.circle.fill", "1. Знайдіть житло", "1. Unterkunft klären",
                  "Маєте приватне житло — уточніть у людини, яка його надає, порядок підписання Meldezettel. Не маєте житла після прибуття з України — зверніться до BBU щодо актуальних можливостей.",
                  "Bei privater Unterkunft klären Sie mit der Unterkunftgeberin oder dem Unterkunftgeber die Unterschrift auf dem Meldezettel. Ohne Unterkunft nach der Ankunft aus der Ukraine fragen Sie bei der BBU nach aktuellen Möglichkeiten."),
            .init("two", "2.circle.fill", "2. Зареєструйте адресу", "2. Wohnadresse anmelden",
                  "Після фактичного заселення подайте Meldezettel до відповідного Gemeindeamt або Magistrat упродовж трьох днів. Збережіть підтвердження реєстрації.",
                  "Melden Sie nach dem tatsächlichen Einzug Ihre Adresse binnen drei Tagen beim zuständigen Gemeindeamt oder Magistrat an. Bewahren Sie die Meldebestätigung auf."),
            .init("three", "3.circle.fill", "3. З'ясуйте підставу перебування", "3. Aufenthaltsgrund klären",
                  "Якщо ви маєте право на тимчасовий захист як переміщена особа з України, пройдіть реєстрацію в поліції. Це окрема процедура від реєстрації адреси. За інших підстав перевіряйте правила свого статусу в компетентному органі.",
                  "Wenn Sie als aus der Ukraine vertriebene Person Anspruch auf vorübergehenden Schutz haben, lassen Sie sich polizeilich erfassen. Das ist ein anderer Vorgang als die Wohnsitzmeldung. Bei anderen Aufenthaltsgründen gelten die Regeln des jeweiligen Status."),
            .init("four", "4.circle.fill", "4. Запитайте про підтримку", "4. Unterstützung klären",
                  "Якщо ви потребуєте допомоги, з'ясуйте умови Grundversorgung у федеральній землі проживання. ÖIF допомагає з орієнтацією та курсами німецької мови.",
                  "Wenn Sie Hilfe benötigen, erkundigen Sie sich in Ihrem Bundesland nach Grundversorgung. Der ÖIF unterstützt bei Orientierung und Deutschkursen."),
            .init("five", "5.circle.fill", "5. Плануйте наступні звернення", "5. Weitere Wege planen",
                  "Перевірте страхування, школу чи догляд за дітьми та можливості роботи відповідно до вашого статусу. Зберігайте отримані підтвердження й листи від установ.",
                  "Prüfen Sie Versicherung, Schule oder Kinderbetreuung und Arbeitsmöglichkeiten passend zu Ihrem Status. Bewahren Sie Bestätigungen und Schreiben von Behörden auf.")
        ],
        sources: [bbu, police, integration]
    )

    private static let support = DirectoryGuide(
        cardSummary: .init(ukrainian: "Житло, базова підтримка й консультації", german: "Unterkunft, Grundversorgung und Beratung"),
        introduction: .init(ukrainian: "Якщо потрібні житло, орієнтація або допомога з наступними кроками, почніть з відповідної офіційної служби.",
                            german: "Wenn Sie Unterkunft, Orientierung oder Hilfe bei den nächsten Schritten brauchen, wenden Sie sich an die passende offizielle Stelle."),
        sections: [
            .init("bbu", "phone.fill", "Прибуття й житло: BBU", "Ankunft und Unterkunft: BBU",
                  "BBU публікує актуальну інформацію для людей, які прибули з України, та має лінію +43 1 2676 870 9460. На сайті є матеріали українською. Наявність місць для проживання потрібно перевіряти безпосередньо.",
                  "Die BBU veröffentlicht aktuelle Informationen für Menschen aus der Ukraine und ist unter +43 1 2676 870 9460 erreichbar. Verfügbare Unterkünfte sollten Sie direkt prüfen.", phoneNumber: "+43 1 2676 870 9460"),
            .init("basic-care", "hand.raised.fill", "Базова підтримка", "Grundversorgung",
                  "Якщо вам потрібна матеріальна підтримка, дізнайтеся про заяву на Grundversorgung у відповідній федеральній землі. Поліцейська реєстрація і заява на підтримку — різні кроки.",
                  "Wenn Sie materielle Unterstützung brauchen, informieren Sie sich über den Antrag auf Grundversorgung im zuständigen Bundesland. Polizeiliche Erfassung und Antrag auf Unterstützung sind getrennte Schritte."),
            .init("oif", "person.2.fill", "Мова й орієнтація: ÖIF", "Sprache und Orientierung: ÖIF",
                  "ÖIF консультує щодо життя в Австрії, курсів німецької та наступних інтеграційних кроків. На сторінці фонду можна знайти консультаційний центр і спосіб запису.",
                  "Der ÖIF berät zum Leben in Österreich, zu Deutschkursen und weiteren Integrationsschritten. Auf seiner Website finden Sie Beratungsstellen und Informationen zur Terminvereinbarung.")
        ],
        sources: [bbuUK, bbu, integration]
    )
}
