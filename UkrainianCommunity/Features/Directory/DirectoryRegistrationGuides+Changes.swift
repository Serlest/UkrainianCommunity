import Foundation

extension RegistrationGuides {
    static let moving = DirectoryGuide(
        cardSummary: .init(ukrainian: "Нова адреса, діти й повідомлення установ",
                           german: "Neue Adresse, Kinder und Mitteilungen an Stellen"),
        introduction: .init(ukrainian: "Переїзд на іншу адресу й зміна статусу вже наявної адреси — різні процедури з різними строками.",
                            german: "Der Umzug an eine andere Adresse und die Änderung eines bestehenden Wohnsitzes sind verschiedene Verfahren mit unterschiedlichen Fristen."),
        sections: [
            .init("new", "arrow.triangle.2.circlepath", "Переїзд на іншу адресу", "Umzug an eine andere Adresse",
                  "Протягом трьох днів після заселення зареєструйте нову адресу з новим Meldezettel та підписом людини, яка надала житло. Для дітей, які живуть із вами, потрібні окремі форми. Орган за новою головною адресою може водночас зняти вас з обліку за старою.",
                  "Melden Sie die neue Unterkunft binnen drei Tagen nach dem Einzug mit neuem Meldezettel und Unterschrift der Unterkunftgeberin oder des Unterkunftgebers an. Für mitwohnende Kinder sind eigene Formulare nötig. Die Behörde des neuen Hauptwohnsitzes kann zugleich den alten abmelden.", source: addressSource),
            .init("type", "arrow.left.arrow.right", "Головна чи додаткова адреса", "Haupt- oder Nebenwohnsitz",
                  "Якщо адреси не змінюються, але головне місце проживання стає додатковим або навпаки, це Ummeldung; строк — один місяць. Діти не перереєстровуються автоматично. Якщо ви справді переїхали на нову адресу, діє триденний строк реєстрації нового місця.",
                  "Bleiben die Adressen gleich, aber Haupt- und Nebenwohnsitz tauschen ihre Rolle, ist das eine Ummeldung binnen eines Monats. Kinder werden nicht automatisch umgemeldet. Bei einem tatsächlichen Umzug an eine neue Adresse gilt die dreitägige Anmeldefrist.", source: addressChangeSource),
            .init("notify", "envelope.fill", "Кого повідомити після переїзду", "Wen nach dem Umzug informieren",
                  "Перевірте, кому ще потрібна нова адреса: BFA, органу Grundversorgung, роботодавцю чи AMS, страховій касі, школі та банку — залежно від ваших справ. Для переміщених осіб актуальна адреса особливо важлива для доставки посвідчення BFA.",
                  "Prüfen Sie, wer Ihre neue Adresse benötigt: BFA, Grundversorgungsstelle, Arbeitgeber oder AMS, Krankenversicherung, Schule und Bank – je nach Ihrer Situation. Für Vertriebene ist sie besonders wichtig, damit das BFA den Ausweis zustellen kann.", source: movingChecklistSource)
        ],
        sources: [registrationSource]
    )

    static let leaving = DirectoryGuide(
        cardSummary: .init(ukrainian: "Зняття адреси з обліку й повідомлення BFA",
                           german: "Wohnsitz abmelden und BFA informieren"),
        introduction: .init(ukrainian: "Ці дії стосуються остаточного виїзду або відмови від австрійського житла, а не короткої поїздки.",
                            german: "Diese Schritte betreffen den dauerhaften Wegzug oder die Aufgabe der Unterkunft in Österreich, nicht eine kurze Reise."),
        sections: [
            .init("address", "airplane", "Зніміть адресу з обліку", "Wohnsitz abmelden",
                  "Якщо ви відмовляєтеся від житла й не реєструєте нову адресу в Австрії, подайте Abmeldung до Meldebehörde. Це можна зробити протягом трьох днів до або після виїзду. Якщо переїжджаєте всередині Австрії, зняття старої адреси часто поєднується з реєстрацією нової.",
                  "Wenn Sie die Unterkunft aufgeben und keine neue Adresse in Österreich anmelden, melden Sie den Wohnsitz bei der Meldebehörde ab. Das ist binnen drei Tagen vor oder nach dem Auszug möglich. Bei einem Umzug innerhalb Österreichs kann die Abmeldung oft mit der neuen Anmeldung verbunden werden.", source: addressDepartureSource),
            .init("bfa", "person.crop.rectangle", "Якщо маєте тимчасовий захист", "Bei vorübergehendem Schutz",
                  "При остаточному виїзді з Австрії повідомте регіональне відділення BFA у землі, де було ваше головне місце проживання, і поверніть посвідчення переміщеної особи особисто або поштою. Тимчасова поїздка й перенесення центру життя в іншу країну мають різні наслідки; за сумнівів уточніть їх у BFA перед виїздом.",
                  "Bei dauerhaftem Wegzug aus Österreich informieren Sie die BFA-Regionaldirektion des bisherigen Hauptwohnsitzes und geben den Ausweis für Vertriebene persönlich oder per Post zurück. Eine kurze Reise und die Verlagerung des Lebensmittelpunkts in ein anderes Land haben unterschiedliche Folgen; klären Sie Zweifel vor der Abreise mit dem BFA.", source: registrationSource),
            .init("support", "checklist", "Закрийте інші справи", "Weitere Stellen informieren",
                  "Якщо отримуєте Grundversorgung чи інші виплати, своєчасно повідомте відповідальні служби. Окремо перевірте школу або дитсадок, роботу, страхування, житловий договір і банківські послуги. Збережіть підтвердження зняття з обліку.",
                  "Informieren Sie bei Grundversorgung oder anderen Leistungen rechtzeitig die zuständigen Stellen. Prüfen Sie außerdem Schule oder Kindergarten, Arbeit, Versicherung, Mietvertrag und Bank. Bewahren Sie die Abmeldebestätigung auf.", source: registrationSource)
        ],
        sources: [bfaContactSource]
    )
}
