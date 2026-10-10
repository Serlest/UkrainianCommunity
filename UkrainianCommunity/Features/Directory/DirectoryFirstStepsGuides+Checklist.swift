import Foundation

extension FirstStepsGuides {
    static let checklist = DirectoryGuide(
        cardSummary: .init(ukrainian: "Адреса, статус, підтримка, школа та наступні звернення",
                           german: "Wohnsitz, Status, Versorgung, Schule und nächste Termine"),
        introduction: .init(
            ukrainian: "Після безпечної ночівлі з’ясуйте статус, зареєструйте адресу й, за потреби, подайте заяву на допомогу. Частину кроків можна робити паралельно; посвідчення надійде пізніше.",
            german: "Nach einer sicheren Übernachtung klären Sie Ihren Status, melden den Wohnsitz an und beantragen bei Bedarf Hilfe. Einiges kann parallel erfolgen; der Ausweis kommt später."
        ),
        sections: [
            .init("address", "1.circle.fill", "Зареєструйте фактичну адресу", "Tatsächlichen Wohnsitz anmelden",
                  "При приватному проживанні подайте Meldezettel до Gemeindeamt або Magistrat протягом трьох днів після заселення. Потрібен підпис людини, яка надала житло, а для кожної особи — окремий бланк. В організованому житлі запитайте адміністрацію, хто оформляє реєстрацію і коли ви отримаєте Meldebestätigung. Збережіть її: адреса потрібна і для листів від BFA.",
                  "Bei privater Unterkunft melden Sie den Wohnsitz binnen drei Tagen nach dem Einzug bei Gemeindeamt oder Magistrat an. Der Unterkunftgeber unterschreibt; jede Person braucht ein eigenes Formular. Fragen Sie in einer organisierten Unterkunft, wer die Meldung veranlasst und wann Sie die Meldebestätigung erhalten. Bewahren Sie sie auf: Das BFA braucht eine zustellbare Adresse.",
                  source: address),
            .init("status", "2.circle.fill", "Перевірте підставу перебування", "Aufenthaltsgrund prüfen",
                  "Перевірте на сторінці BMI, чи належите ви до груп тимчасового захисту: самого проживання в Україні замало. Для нових випадків після 4 серпня 2026 року може знадобитися доказ виконання військових обов’язків за українським правом, наприклад підтвердження законного виїзду або звільнення від обов’язку. Це правило не застосовують до тих, хто вже мав захист в Австрії 4 серпня 2026 року й зберіг його без перерви. Після захисту в іншій країні ЄС підготуйте доказ припинення захисту та соціальних виплат там; за сумнівів зверніться до BBU.",
                  "Prüfen Sie auf der BMI-Seite, ob Sie zu den Gruppen mit vorübergehendem Schutz gehören: Ein früherer Wohnsitz in der Ukraine genügt nicht immer. Für neue Fälle nach dem 4. August 2026 kann ein Nachweis über die Erfüllung ukrainischer militärischer Pflichten nötig sein, etwa eine rechtmäßige Ausreise oder Befreiung. Wer bereits am 4. August 2026 Schutz in Österreich hatte und ihn ununterbrochen behielt, ist von dieser neuen Regel ausgenommen. Nach Schutz in einem anderen EU-Staat benötigen Sie Nachweise über dessen Ende und das Ende der dortigen Sozialleistungen; lassen Sie Zweifelsfälle von der BBU klären.",
                  source: police),
            .init("police", "3.circle.fill", "Якщо маєте право — пройдіть реєстрацію в поліції", "Bei Anspruch polizeilich erfassen lassen",
                  "Знайдіть на сторінці BMI пункт своєї землі, перевірте години й потребу в записі. Візьміть паспорт, свідоцтва та інші документи, які маєте; якщо чогось бракує, все одно зверніться. Збережіть підтвердження реєстрації. BFA оформлює Ausweis für Vertriebene за отриманими даними й надсилає його на зареєстровану адресу; це може зайняти кілька тижнів.",
                  "Suchen Sie auf der BMI-Seite eine Erfassungsstelle Ihres Bundeslands und prüfen Sie Zeiten und Terminpflicht. Bringen Sie Reisepass, Urkunden und andere vorhandene Dokumente mit; gehen Sie auch bei Lücken hin. Heben Sie den Registrierungsbeleg auf. Das BFA erstellt den Ausweis für Vertriebene anhand der erfassten Daten und sendet ihn an die gemeldete Adresse; das kann einige Wochen dauern.",
                  source: police),
            .init("support", "4.circle.fill", "Якщо потрібна допомога — подайте окрему заяву", "Bei Bedarf Grundversorgung gesondert beantragen",
                  "Якщо ви маєте право на тимчасовий захист і потребуєте коштів, житла або медичного покриття, зверніться до служби Grundversorgung у вашій землі. Запитайте, куди подати заяву, які документи потрібні та чи можна отримати житло або окремі види допомоги. Поліцейська реєстрація сама по собі не призначає виплати й не активує страхування; за іншого статусу уточніть свою програму підтримки.",
                  "Wenn Sie vorübergehenden Schutz beanspruchen können und Geld, Unterkunft oder Krankenversicherung brauchen, kontaktieren Sie die Grundversorgungsstelle Ihres Bundeslands. Fragen Sie nach Antragsstelle, Unterlagen und Unterkunft oder einzelnen Leistungen. Die polizeiliche Erfassung bewilligt weder Geldleistungen noch aktiviert sie automatisch die Versicherung; bei anderem Status klären Sie den passenden Hilfsweg.",
                  source: housing),
            .init("insurance", "5.circle.fill", "Підтвердіть медичне страхування", "Krankenversicherung nachweisen",
                  "Не вважайте Ausweis für Vertriebene доказом страхування: автоматичного покриття лише через цей статус немає. Перевірте страхування через роботу, родину або погоджену Grundversorgung. При самостійному страхуванні може діяти шестимісячний строк очікування на медичні послуги; уточніть в ÖGK внесок і винятки після попереднього страхування.",
                  "Der Ausweis für Vertriebene ist kein Versicherungsnachweis: Dieser Status allein begründet keine automatische Krankenversicherung. Prüfen Sie Schutz durch Arbeit, Mitversicherung oder bewilligte Grundversorgung. Bei Selbstversicherung kann eine Wartezeit von sechs Monaten für Leistungen gelten; fragen Sie die ÖGK nach Beitrag und Ausnahmen bei vorheriger Versicherung.",
                  source: bbuFAQ),
            .init("children", "6.circle.fill", "Для дітей з’ясуйте школу й садок", "Schule und Kindergarten für Kinder klären",
                  "Якщо дитина житиме в Австрії, зверніться до найближчої школи або Bildungsdirektion, щоб визначити місце навчання; для молодших дітей запитайте Gemeinde про садок. Шкільний обов’язок залежить від віку й тривалого проживання, а не від наявності картки страхування. Візьміть наявні шкільні документи, але не відкладайте звернення через їх відсутність.",
                  "Wird ein Kind in Österreich leben, fragen Sie eine nahe Schule oder Bildungsdirektion nach dem Schulplatz; für jüngere Kinder die Gemeinde nach Kindergarten. Die Schulpflicht hängt von Alter und dauerhaftem Aufenthalt ab, nicht von einer Versicherungskarte. Bringen Sie vorhandene Schulunterlagen mit, verschieben Sie die Anfrage aber nicht wegen fehlender Papiere.",
                  source: school),
            .init("work", "7.circle.fill", "Для пошуку роботи зверніться до AMS", "Für die Arbeitssuche zum AMS",
                  "Після отримання Ausweis für Vertriebene зверніться до AMS за місцем проживання для реєстрації як шукача роботи. Візьміть посвідчення та, якщо є, резюме й документи про освіту або досвід. AMS допоможе з пошуком роботи; якщо ви отримуєте Grundversorgung, повідомляйте її службу про початок роботи та дохід.",
                  "Mit dem Ausweis für Vertriebene können Sie sich beim AMS Ihres Wohnbezirks arbeitssuchend melden. Nehmen Sie den Ausweis und, soweit vorhanden, Lebenslauf sowie Ausbildungs- oder Berufsnachweise mit. Das AMS unterstützt die Arbeitssuche; wenn Sie Grundversorgung beziehen, melden Sie dort Arbeitsbeginn und Einkommen.",
                  source: work),
            .init("language", "8.circle.fill", "Оберіть мовну підтримку", "Sprachliche Unterstützung finden",
                  "Перевірте курси німецької ÖIF у вашій землі та умови запису на консультацію. На сторінці ÖIF є також безкоштовні онлайн-заняття, з яких можна почати до очного курсу. Попросіть пояснити, які документи потрібні саме для вашого запису й чи є місце на потрібному рівні.",
                  "Prüfen Sie Deutschkurse des ÖIF in Ihrem Bundesland und die Anmeldung zur Beratung. Auf der ÖIF-Seite finden Sie auch kostenlose Online-Angebote, mit denen Sie vor einem Präsenzkurs beginnen können. Fragen Sie, welche Unterlagen Ihr Termin erfordert und ob es einen Platz auf Ihrem Niveau gibt.",
                  source: language)
        ],
        sources: [bbu]
    )
}
