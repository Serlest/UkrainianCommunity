import Foundation

extension RegistrationGuides {
    static let moving = DirectoryGuide(
        cardSummary: .init(ukrainian: "Нова адреса, діти й повідомлення установ",
                           german: "Neue Adresse, Kinder und Mitteilungen an Stellen"),
        introduction: .init(ukrainian: "Переїзд на іншу адресу й зміна статусу вже наявної адреси — різні процедури з різними строками.",
                            german: "Der Umzug an eine andere Adresse und die Änderung eines bestehenden Wohnsitzes sind verschiedene Verfahren mit unterschiedlichen Fristen."),
        sections: [
            .init("new", "house.fill", "Переїзд на іншу адресу", "Umzug an eine andere Adresse",
                  "Протягом трьох днів після заселення зареєструйте нову адресу з новим Meldezettel та підписом людини, яка надала житло. Для дітей, які живуть із вами, потрібні окремі форми. Орган за новою головною адресою може водночас зняти вас з обліку за старою.",
                  "Melden Sie die neue Unterkunft binnen drei Tagen nach dem Einzug mit neuem Meldezettel und Unterschrift der Unterkunftgeberin oder des Unterkunftgebers an. Für mitwohnende Kinder sind eigene Formulare nötig. Die Behörde des neuen Hauptwohnsitzes kann zugleich den alten abmelden."),
            .init("type", "arrow.left.arrow.right", "Головна чи додаткова адреса", "Haupt- oder Nebenwohnsitz",
                  "Якщо адреси не змінюються, але головне місце проживання стає додатковим або навпаки, це Ummeldung; строк — один місяць. Діти не перереєстровуються автоматично. Якщо ви справді переїхали на нову адресу, діє триденний строк реєстрації нового місця.",
                  "Bleiben die Adressen gleich, aber Haupt- und Nebenwohnsitz tauschen ihre Rolle, ist das eine Ummeldung binnen eines Monats. Kinder werden nicht automatisch umgemeldet. Bei einem tatsächlichen Umzug an eine neue Adresse gilt die dreitägige Anmeldefrist."),
            .init("notify", "envelope.fill", "Кого повідомити після переїзду", "Wen nach dem Umzug informieren",
                  "Перевірте, кому ще потрібна нова адреса: BFA, органу Grundversorgung, роботодавцю чи AMS, страховій касі, школі та банку — залежно від ваших справ. Для переміщених осіб актуальна адреса особливо важлива для доставки посвідчення BFA.",
                  "Prüfen Sie, wer Ihre neue Adresse benötigt: BFA, Grundversorgungsstelle, Arbeitgeber oder AMS, Krankenversicherung, Schule und Bank – je nach Ihrer Situation. Für Vertriebene ist sie besonders wichtig, damit das BFA den Ausweis zustellen kann.")
        ],
        sources: [
            addressSource,
            DirectorySource(name: "oesterreich.gv.at · Ummeldung",
                            url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180210"),
            DirectorySource(name: "oesterreich.gv.at · Nach dem Umzug",
                            url: "https://www.oesterreich.gv.at/de/lebenslagen/Ich-wohne-bald-in-einem-neuen-Zuhause/Nach-dem-Umzug"),
            registrationSource
        ]
    )

    static let leaving = DirectoryGuide(
        cardSummary: .init(ukrainian: "Зняття адреси з обліку й повідомлення BFA",
                           german: "Wohnsitz abmelden und BFA informieren"),
        introduction: .init(ukrainian: "Ці дії стосуються остаточного виїзду або відмови від австрійського житла, а не короткої поїздки.",
                            german: "Diese Schritte betreffen den dauerhaften Wegzug oder die Aufgabe der Unterkunft in Österreich, nicht eine kurze Reise."),
        sections: [
            .init("address", "house.fill", "Зніміть адресу з обліку", "Wohnsitz abmelden",
                  "Якщо ви відмовляєтеся від житла й не реєструєте нову адресу в Австрії, подайте Abmeldung до Meldebehörde. Це можна зробити протягом трьох днів до або після виїзду. Якщо переїжджаєте всередині Австрії, зняття старої адреси часто поєднується з реєстрацією нової.",
                  "Wenn Sie die Unterkunft aufgeben und keine neue Adresse in Österreich anmelden, melden Sie den Wohnsitz bei der Meldebehörde ab. Das ist binnen drei Tagen vor oder nach dem Auszug möglich. Bei einem Umzug innerhalb Österreichs kann die Abmeldung oft mit der neuen Anmeldung verbunden werden."),
            .init("bfa", "person.crop.rectangle", "Якщо маєте тимчасовий захист", "Bei vorübergehendem Schutz",
                  "При остаточному виїзді з Австрії повідомте регіональне відділення BFA у землі, де було ваше головне місце проживання, і поверніть посвідчення переміщеної особи особисто або поштою. Тимчасова поїздка й перенесення центру життя в іншу країну мають різні наслідки; за сумнівів уточніть їх у BFA перед виїздом.",
                  "Bei dauerhaftem Wegzug aus Österreich informieren Sie die BFA-Regionaldirektion des bisherigen Hauptwohnsitzes und geben den Ausweis für Vertriebene persönlich oder per Post zurück. Eine kurze Reise und die Verlagerung des Lebensmittelpunkts in ein anderes Land haben unterschiedliche Folgen; klären Sie Zweifel vor der Abreise mit dem BFA."),
            .init("support", "checklist", "Закрийте інші справи", "Weitere Stellen informieren",
                  "Якщо отримуєте Grundversorgung чи інші виплати, своєчасно повідомте відповідальні служби. Окремо перевірте школу або дитсадок, роботу, страхування, житловий договір і банківські послуги. Збережіть підтвердження зняття з обліку.",
                  "Informieren Sie bei Grundversorgung oder anderen Leistungen rechtzeitig die zuständigen Stellen. Prüfen Sie außerdem Schule oder Kindergarten, Arbeit, Versicherung, Mietvertrag und Bank. Bewahren Sie die Abmeldebestätigung auf.")
        ],
        sources: [
            DirectorySource(name: "oesterreich.gv.at · Wohnsitz abmelden",
                            url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180220"),
            registrationSource,
            bfaContactSource
        ]
    )

    static let appointments = DirectoryGuide(
        cardSummary: .init(ukrainian: "Який орган потрібен і як перевірити запис",
                           german: "Zuständige Stelle finden und Termin prüfen"),
        introduction: .init(ukrainian: "У різних процедур різні установи. Перед поїздкою перевірте правила саме того органу, який займається вашим питанням.",
                            german: "Für verschiedene Verfahren sind unterschiedliche Stellen zuständig. Prüfen Sie vor der Fahrt die Regeln der konkret zuständigen Behörde."),
        sections: [
            .init("address", "mappin.and.ellipse", "Meldezettel: місцевий орган", "Meldezettel: örtliche Behörde",
                  "Адресу реєструє Meldebehörde за місцем проживання: Gemeindeamt, Magistrat або віденський Magistratisches Bezirksamt. Через триденний строк перевіряйте дозволені способи подання одразу після заселення; єдиної системи запису для всіх громад немає.",
                  "Den Wohnsitz meldet die Meldebehörde am Wohnort an: Gemeindeamt, Magistrat oder in Wien das Magistratische Bezirksamt. Wegen der Dreitagesfrist prüfen Sie die zulässigen Einreichwege direkt nach dem Einzug; ein einheitliches Terminsystem aller Gemeinden gibt es nicht."),
            .init("police", "person.crop.rectangle", "Тимчасовий захист: пункт поліції", "Vorübergehender Schutz: Polizeistelle",
                  "Для первинної реєстрації переміщених осіб відкрийте перелік Erfassungsstellen на сайті BMI. У таблиці вказані контакт, години, доступність і необхідність запису; порядок різниться за землею та пунктом.",
                  "Für die erste Erfassung von Vertriebenen öffnen Sie die Erfassungsstellen-Liste beim BMI. Dort stehen Kontakt, Zeiten, Barrierefreiheit und Terminpflicht; das Vorgehen variiert nach Bundesland und Stelle."),
            .init("bfa", "envelope.fill", "Питання про посвідчення: BFA", "Fragen zum Ausweis: BFA",
                  "Після поліцейської реєстрації індивідуальні питання щодо посвідчення адресуйте відповідальному регіональному відділенню BFA. На офіційній сторінці контактів є адреси й телефони за землями; для звернення підготуйте ім’я, дату народження та IFA-номер, якщо знаєте його.",
                  "Nach der polizeilichen Erfassung richten Sie Einzelfragen zum Ausweis an die zuständige BFA-Regionaldirektion. Die Kontaktseite nennt Adressen und Telefonnummern nach Bundesland; halten Sie Namen, Geburtsdatum und die IFA-Zahl bereit, falls bekannt.")
        ],
        sources: [addressSource, registrationSource, bfaContactSource]
    )
}
