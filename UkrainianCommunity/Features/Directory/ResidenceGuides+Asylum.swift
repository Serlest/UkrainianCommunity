import Foundation

extension ResidenceGuides {
    static let internationalProtection = DirectoryGuide(
        cardSummary: .init(ukrainian: "Індивідуальний захист, права й особливе возз’єднання", german: "Individueller Schutz, Rechte und besonderer Familiennachzug"),
        introduction: .init(ukrainian: "Притулок (статус біженця), субсидіарний захист і тимчасовий захист переміщених — три різні правові режими. Заява на міжнародний захист розглядається індивідуально.", german: "Flüchtlingseigenschaft, subsidiärer Schutz und vorübergehender Vertriebenenschutz sind drei verschiedene Rechtslagen. Ein Antrag auf internationalen Schutz wird individuell geprüft."),
        sections: [
            .init("difference", "shield", "Які є рішення", "Welche Entscheidungen es gibt",
                  "Статус біженця пов’язаний із визначеними причинами переслідування. Субсидіарний захист може надаватися, якщо загрожує серйозна шкода при поверненні, хоча умови статусу біженця не виконані. У процедурі можуть перевіряти й гуманітарну підставу. Тимчасовий захист для людей з України не є автоматично заявою на притулок.",
                  "Flüchtlingseigenschaft betrifft bestimmte Verfolgungsgründe. Subsidiärer Schutz kann bei drohendem ernstem Schaden im Herkunftsland gewährt werden, wenn die Voraussetzungen für Flüchtlingsschutz fehlen. Auch humanitäre Gründe können geprüft werden. Ukraine-Vertriebenenschutz ist nicht automatisch ein Asylantrag."),
            .init("procedure", "building.2", "Заява та процедура", "Antrag und Verfahren",
                  "Міжнародний захист розглядає BFA за чинними правилами. Після змін права ЄС у 2026 році процедура й документи можуть залежати від обставин. Для особистої ситуації перевірте актуальну сторінку BFA й зверніться по незалежну правову консультацію до подання або оскарження рішення.",
                  "Über internationalen Schutz entscheidet das BFA nach aktuellem Recht. Nach den EU-Rechtsänderungen 2026 können Verfahren und Dokumente vom Einzelfall abhängen. Prüfen Sie für Ihren Fall die aktuellen BFA-Informationen und holen Sie vor Antrag oder Beschwerde unabhängige Rechtsberatung ein."),
            .init("rights", "briefcase", "Після позитивного рішення", "Nach positiver Entscheidung",
                  "Визнані біженці та особи із субсидіарним захистом мають доступ до ринку праці. Документ і строк права перебування різняться; продовження субсидіарного захисту має власний порядок. Зберігайте рішення BFA й уважно стежте за строками в ньому.",
                  "Anerkannte Flüchtlinge und subsidiär Schutzberechtigte haben Zugang zum Arbeitsmarkt. Dokument und Aufenthaltsdauer unterscheiden sich; die Verlängerung subsidiären Schutzes folgt eigenen Regeln. Bewahren Sie den BFA-Bescheid auf und beachten Sie die darin genannten Fristen."),
            .init("family", "person.2.fill", "Возз’єднання сім’ї", "Familienzusammenführung",
                  "Для сім’ї людей із міжнародним захистом тепер діють спеціальні правила § 46a NAG, зокрема щодо членів сім’ї, квот і строків. Для деяких сімей біженців заява протягом трьох місяців після остаточного визнання впливає на вимоги до коштів, житла й страхування. Не пропустіть цей строк; перевірте офіційну сторінку та консульство.",
                  "Für Familien international Schutzberechtigter gelten besondere Regeln nach § 46a NAG, etwa zu Angehörigen, Quoten und Fristen. Bei manchen Flüchtlingsfamilien wirkt sich ein Antrag binnen drei Monaten nach rechtskräftiger Zuerkennung auf Anforderungen zu Mitteln, Unterkunft und Versicherung aus. Versäumen Sie die Frist nicht; prüfen Sie die amtliche Seite und die Vertretungsbehörde.")
        ], sources: [asylum, asylumFamily]
    )
}
