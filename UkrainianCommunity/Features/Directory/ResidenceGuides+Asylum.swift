import Foundation

extension ResidenceGuides {
    static let internationalProtection = DirectoryGuide(
        cardSummary: .init(ukrainian: "Індивідуальний захист, права й особливе возз’єднання", german: "Individueller Schutz, Rechte und besonderer Familiennachzug"),
        introduction: .init(ukrainian: "Притулок (статус біженця), субсидіарний захист і тимчасовий захист переміщених — три різні правові режими. Заява на міжнародний захист розглядається індивідуально.", german: "Flüchtlingseigenschaft, subsidiärer Schutz und vorübergehender Vertriebenenschutz sind drei verschiedene Rechtslagen. Ein Antrag auf internationalen Schutz wird individuell geprüft."),
        sections: [
            .init("difference", "shield", "Які є рішення", "Welche Entscheidungen es gibt",
                  "Статус біженця пов’язаний із визначеними причинами переслідування. Субсидіарний захист може надаватися, якщо загрожує серйозна шкода при поверненні, хоча умови статусу біженця не виконані. У процедурі можуть перевіряти й гуманітарну підставу. Тимчасовий захист для людей з України не є автоматично заявою на притулок.",
                  "Flüchtlingseigenschaft betrifft bestimmte Verfolgungsgründe. Subsidiärer Schutz kann bei drohendem ernstem Schaden im Herkunftsland gewährt werden, wenn die Voraussetzungen für Flüchtlingsschutz fehlen. Auch humanitäre Gründe können geprüft werden. Ukraine-Vertriebenenschutz ist nicht automatisch ein Asylantrag.", source: asylum),
            .init("procedure", "building.2", "Заява та процедура", "Antrag und Verfahren",
                  "Міжнародний захист розглядає BFA за чинними правилами. Після змін права ЄС у 2026 році процедура й документи можуть залежати від обставин. Для особистої ситуації перевірте актуальну сторінку BFA й зверніться по незалежну правову консультацію до подання або оскарження рішення.",
                  "Über internationalen Schutz entscheidet das BFA nach aktuellem Recht. Nach den EU-Rechtsänderungen 2026 können Verfahren und Dokumente vom Einzelfall abhängen. Prüfen Sie für Ihren Fall die aktuellen BFA-Informationen und holen Sie vor Antrag oder Beschwerde unabhängige Rechtsberatung ein.", source: asylum),
            .init("rights", "briefcase", "Після позитивного рішення", "Nach positiver Entscheidung",
                  "Визнані біженці та особи із субсидіарним захистом мають доступ до ринку праці. Документ і строк права перебування різняться; продовження субсидіарного захисту має власний порядок. Зберігайте рішення BFA й уважно стежте за строками в ньому.",
                  "Anerkannte Flüchtlinge und subsidiär Schutzberechtigte haben Zugang zum Arbeitsmarkt. Dokument und Aufenthaltsdauer unterscheiden sich; die Verlängerung subsidiären Schutzes folgt eigenen Regeln. Bewahren Sie den BFA-Bescheid auf und beachten Sie die darin genannten Fristen.", source: asylum),
            .init("family", "person.2.fill", "Возз’єднання сім’ї", "Familienzusammenführung",
                  "Для сім’ї визнаного біженця або людини з субсидіарним захистом діє окрема процедура § 46a NAG. Якщо біженця визнано остаточним рішенням, подання протягом трьох місяців може звільнити сім’ю від доказу коштів, житла й страхування; якщо консульство не дає термін, надішліть запит на прийом електронною поштою в межах цього строку й збережіть доказ. Для субсидіарного захисту зазвичай потрібно, щоб особа мала його щонайменше два роки. Заява зазвичай подається особисто в австрійському представництві; збір 218 €.",
                  "Für Familien anerkannter Flüchtlinge oder subsidiär Schutzberechtigter gilt das eigene Verfahren nach § 46a NAG. Ein Antrag binnen drei Monaten nach rechtskräftiger Flüchtlingsanerkennung kann die Nachweise für Mittel, Unterkunft und Versicherung entbehrlich machen; bietet die Botschaft keinen Termin an, erbitten Sie ihn innerhalb der Frist per E-Mail und bewahren den Nachweis auf. Bei subsidiärem Schutz muss die Bezugsperson ihn grundsätzlich seit mindestens zwei Jahren haben. Der Erstantrag erfolgt meist persönlich bei der österreichischen Vertretung; Gebühr: 218 €.", source: asylumFamily)
        ], sources: [asylum, asylumFamily]
    )
}
