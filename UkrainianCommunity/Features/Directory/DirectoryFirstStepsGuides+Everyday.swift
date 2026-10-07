import Foundation

extension FirstStepsGuides {
    static let healthInsurance = DirectoryGuide(
        cardSummary: .init(ukrainian: "Невідкладна допомога й перевірка страхування",
                           german: "Notfallhilfe und Versicherungsschutz prüfen"),
        introduction: .init(ukrainian: "Після прибуття перевірте, як саме покриваються медичні витрати. Тимчасовий захист не означає автоматичного страхування.",
                            german: "Prüfen Sie nach der Ankunft, wie Behandlungskosten gedeckt sind. Vorübergehender Schutz bedeutet keine automatische Krankenversicherung."),
        sections: [
            .init("emergency", "cross.case.fill", "Якщо допомога потрібна зараз", "Wenn Sie jetzt Hilfe brauchen",
                  "При невідкладному стані телефонуйте 144 або 112. У лікарні скажіть, що ви щойно прибули з України, і повідомте, чи вже маєте страхування. Невідкладну допомогу нададуть, але витрати можуть не покриватися автоматично.",
                  "Bei einem medizinischen Notfall wählen Sie 144 oder 112. Teilen Sie dem Krankenhaus mit, dass Sie gerade aus der Ukraine angekommen sind, und ob Sie versichert sind. Notfallhilfe ist möglich, die Kosten sind aber nicht automatisch gedeckt."),
            .init("advice", "phone.fill", "Якщо не знаєте, куди звернутися", "Wenn Sie die richtige Stelle nicht kennen",
                  "Для медичного питання без безпосередньої загрози життю телефонуйте 1450. Ця служба цілодобово підкаже, куди звернутися. За загрози життю використовуйте 144 або 112.",
                  "Bei gesundheitlichen Fragen ohne unmittelbare Lebensgefahr wählen Sie 1450. Die Beratung nennt Ihnen rund um die Uhr die passende Anlaufstelle. Bei Lebensgefahr wählen Sie 144 oder 112.", phoneNumber: "1450"),
            .init("options", "checkmark.shield.fill", "Перевірте спосіб страхування", "Versicherungsweg prüfen",
                  "Можливі шляхи — страхування через роботу, співстрахування через члена сім’ї, добровільне страхування або страхування в межах Grundversorgung за наявності права на неї. Уточніть свій випадок в ÖGK чи відповідальному органі землі.",
                  "Mögliche Wege sind Versicherung über Arbeit, Mitversicherung über Angehörige, Selbstversicherung oder Versicherung im Rahmen der Grundversorgung bei Anspruch darauf. Klären Sie Ihren Fall mit der ÖGK oder der zuständigen Landesstelle."),
            .init("proof", "doc.text.fill", "Підтвердження для лікаря", "Nachweis für die Arztpraxis",
                  "Запитайте в страховій установі, чи страхування вже активне та який документ пред’являти. При страхуванні через Grundversorgung замість пластикової e-card може бути тимчасовий e-card-Ersatzbeleg.",
                  "Fragen Sie bei der Versicherung nach, ob der Schutz bereits aktiv ist und welchen Nachweis Sie vorlegen sollen. Bei Versicherung über Grundversorgung kann statt einer e-card ein vorläufiger e-card-Ersatzbeleg ausgestellt werden.")
        ],
        sources: [
            DirectorySource(name: "BBU · Медичне страхування та невідкладна допомога",
                            url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian"),
            DirectorySource(name: "AMS · Krankenversicherung für Vertriebene",
                            url: "https://www.ams.at/arbeitsuchende/topicliste/blaue-karte"),
            DirectorySource(name: "Gesundheitsportal · Telefonische Beratung 1450",
                            url: "https://www.gesundheit.gv.at/service/notruf/hotline.html")
        ]
    )

    static let children = DirectoryGuide(
        cardSummary: .init(ukrainian: "Школа, дитсадок і документи дитини",
                           german: "Schule, Kindergarten und Unterlagen des Kindes"),
        introduction: .init(ukrainian: "Для дітей, які живуть в Австрії, діють правила відвідування школи й дитсадка незалежно від громадянства.",
                            german: "Für Kinder, die in Österreich leben, gelten Schul- und Kindergartenregeln unabhängig von der Staatsangehörigkeit."),
        sections: [
            .init("address", "house.fill", "Адреса й документи дитини", "Adresse und Unterlagen des Kindes",
                  "Після заселення зареєструйте адресу дитини разом зі своєю. Зберіть наявні документи про особу, вік і попереднє навчання; відсутність шкільних документів обговоріть із приймаючою школою.",
                  "Melden Sie nach dem Einzug auch die Adresse des Kindes an. Halten Sie vorhandene Ausweise sowie Nachweise zu Alter und bisheriger Schule bereit; fehlende Schulunterlagen besprechen Sie mit der aufnehmenden Schule."),
            .init("school", "books.vertical.fill", "Школа", "Schule",
                  "Діти, які постійно перебувають в Австрії, мають відвідувати школу протягом дев’яти навчальних років. Зверніться до школи за місцем проживання або до освітньої дирекції своєї землі, щоб дізнатися про зарахування та мовну підтримку. Відсутність медичного страхування не скасовує обов’язку відвідувати школу.",
                  "Kinder, die sich dauerhaft in Österreich aufhalten, unterliegen neun Schuljahren der Schulpflicht. Fragen Sie bei einer Schule am Wohnort oder der Bildungsdirektion Ihres Bundeslandes nach Aufnahme und Sprachförderung. Fehlende Krankenversicherung hebt die Schulpflicht nicht auf."),
            .init("kindergarten", "figure.and.child.holdinghands", "Дитсадок", "Kindergarten",
                  "Для дитини, якій до 1 вересня виповнилося п’ять років, зазвичай обов’язковий один рік дитсадка. Порядок запису й наявність місць уточніть у громаді або міському управлінні за місцем проживання.",
                  "Für Kinder, die bis zum 1. September fünf Jahre alt sind, ist in der Regel ein Kindergartenjahr verpflichtend. Anmeldung und freie Plätze klären Sie bei der Gemeinde oder Stadtverwaltung Ihres Wohnorts.")
        ],
        sources: [DirectorySource(name: "BBU · Шкільна освіта для дітей",
                                  url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")]
    )

    static let workLanguage = DirectoryGuide(
        cardSummary: .init(ukrainian: "Пошук роботи через AMS і курси ÖIF",
                           german: "Arbeitssuche beim AMS und Deutschkurse beim ÖIF"),
        introduction: .init(ukrainian: "Роботу й німецьку мову можна планувати паралельно. AMS та ÖIF допомагають із різними частинами цього шляху.",
                            german: "Arbeitssuche und Deutschlernen können parallel beginnen. AMS und ÖIF helfen bei unterschiedlichen Schritten."),
        sections: [
            .init("ams", "briefcase.fill", "Пошук роботи: AMS", "Arbeitssuche: AMS",
                  "Якщо ви маєте право на роботу та шукаєте її, зверніться до AMS за місцем проживання. Візьміть посвідчення переміщеної особи, якщо воно вже є, і документи про освіту та досвід. AMS розповість про вакансії й можливості навчання.",
                  "Wenn Sie arbeiten dürfen und Arbeit suchen, wenden Sie sich an die AMS-Geschäftsstelle Ihres Wohnorts. Bringen Sie den Ausweis für Vertriebene, falls vorhanden, und Unterlagen zu Ausbildung und Berufserfahrung mit. Das AMS informiert über Stellen und Qualifizierung."),
            .init("oif", "character.book.closed.fill", "Німецька мова: ÖIF", "Deutschlernen: ÖIF",
                  "ÖIF пропонує консультації та курси німецької для переміщених осіб з України. На сторінці ÖIF виберіть свою федеральну землю й перевірте запис, потрібні документи та онлайн-курси.",
                  "Der ÖIF bietet Vertriebenen aus der Ukraine Beratung und Deutschkurse. Wählen Sie auf der ÖIF-Seite Ihr Bundesland und prüfen Sie Anmeldung, Unterlagen und Onlinekurse."),
            .init("sequence", "arrow.triangle.branch", "Що підготувати", "Was vorbereiten",
                  "Запишіть свою адресу, мови, професію й досвід роботи; збережіть дипломи та сертифікати. Якщо документів ще немає, уточніть у AMS або ÖIF, з чого можна почати зараз.",
                  "Notieren Sie Adresse, Sprachen, Beruf und Erfahrung; bewahren Sie Zeugnisse und Zertifikate auf. Wenn Unterlagen noch fehlen, fragen Sie bei AMS oder ÖIF, womit Sie bereits beginnen können.")
        ],
        sources: [
            DirectorySource(name: "AMS · Informationen für Menschen aus der Ukraine",
                            url: "https://www.ams.at/arbeitsuchende/arbeiten-in-oesterreich-und-der-eu/ukraine/ukraine-informationen-deutsch"),
            DirectorySource(name: "ÖIF · Deutschkurse für ukrainische Vertriebene",
                            url: "https://www.integration.at/themen/ukraine/")
        ]
    )
}
