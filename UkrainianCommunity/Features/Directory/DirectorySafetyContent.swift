import Foundation

struct SafetyContact: Identifiable {
    let number: String
    let title: DirectoryText
    let detail: DirectoryText

    var id: String { number }
    var phoneURL: URL { URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))")! }
}

struct SafetySection: Identifiable {
    let id: String
    let title: DirectoryText
    let symbol: String
    let body: DirectoryText
    let contacts: [SafetyContact]
}

struct SafetyGuide {
    let summary: DirectoryText
    let sections: [SafetySection]
    let sources: [DirectorySource]
}

enum DirectorySafetyContent {
    static let reviewedOn = "10.10.2026"
    static let guides = protectionGuides
        .merging(victimSupportGuides) { _, newer in newer }
        .merging(incidentGuides) { _, newer in newer }
        .merging(outdoorGuides) { _, newer in newer }

    static let police = SafetyContact(
        number: "133", title: .init(ukrainian: "Поліція", german: "Polizei"),
        detail: .init(
            ukrainian: "Негайна небезпека або насильство", german: "Akute Gefahr oder Gewalt")
    )
    static let europeanEmergency = SafetyContact(
        number: "112",
        title: .init(ukrainian: "Європейський екстрений номер", german: "Euro-Notruf"),
        detail: .init(ukrainian: "Допомога в екстреній ситуації", german: "Hilfe im Notfall")
    )
    static let ambulance = SafetyContact(
        number: "144", title: .init(ukrainian: "Швидка допомога", german: "Rettung"),
        detail: .init(ukrainian: "Невідкладна медична допомога", german: "Medizinischer Notfall")
    )
    static let fire = SafetyContact(
        number: "122", title: .init(ukrainian: "Пожежна служба", german: "Feuerwehr"),
        detail: .init(ukrainian: "Пожежа та порятунок", german: "Brand und Rettung")
    )
    static let womenHelpline = SafetyContact(
        number: "0800 222 555",
        title: .init(
            ukrainian: "Допомога жінкам, які зазнали насильства",
            german: "Frauenhelpline gegen Gewalt"),
        detail: .init(
            ukrainian: "Безкоштовно, цілодобово, по всій Австрії",
            german: "Kostenlos, rund um die Uhr, österreichweit")
    )
    static let protectionCentre = SafetyContact(
        number: "0800 700 217",
        title: .init(ukrainian: "Центри захисту від насильства", german: "Gewaltschutzzentren"),
        detail: .init(
            ukrainian: "Консультація і підтримка після насильства",
            german: "Beratung und Unterstützung nach Gewalt")
    )
    static let menHelpline = SafetyContact(
        number: "0800 400 777",
        title: .init(ukrainian: "Кризова допомога чоловікам", german: "Männerberatung 24/7"),
        detail: .init(ukrainian: "Безкоштовно, конфіденційно, цілодобово",
                      german: "Kostenlos, vertraulich, rund um die Uhr")
    )
    static let gas = SafetyContact(
        number: "128", title: .init(ukrainian: "Аварійна газова служба", german: "Gasnotruf"),
        detail: .init(
            ukrainian: "Телефонуйте ззовні будівлі", german: "Von außerhalb des Gebäudes anrufen"))
    static let mountain = SafetyContact(
        number: "140", title: .init(ukrainian: "Гірська рятувальна служба", german: "Bergrettung"),
        detail: .init(
            ukrainian: "Поза Форарльбергом", german: "Außerhalb Vorarlbergs"))
    static let vorarlbergMountain = SafetyContact(
        number: "144",
        title: .init(ukrainian: "Гірська допомога у Форарльберзі", german: "Bergnotruf in Vorarlberg"),
        detail: .init(ukrainian: "Рятувальна служба 144", german: "Rettungsnotruf 144")
    )
    static let waterRescue = SafetyContact(
        number: "130", title: .init(ukrainian: "Водна рятувальна служба", german: "Wasserrettung"),
        detail: .init(ukrainian: "Диспетчерська у Каринтії та Верхній Австрії",
                      german: "Landesleitstelle in Kärnten und Oberösterreich")
    )
    static let poison = SafetyContact(
        number: "01 406 43 43",
        title: .init(
            ukrainian: "Інформація про отруєння", german: "Vergiftungsinformationszentrale"),
        detail: .init(ukrainian: "Цілодобова консультація", german: "Beratung rund um die Uhr"))
    static let children = SafetyContact(
        number: "147",
        title: .init(ukrainian: "Підтримка дітей та підлітків", german: "Rat auf Draht"),
        detail: .init(ukrainian: "Анонімно та безкоштовно", german: "Anonym und kostenlos"))
    static let missingChildren = SafetyContact(
        number: "116 000", title: .init(ukrainian: "Зниклі діти", german: "Vermisste Kinder"),
        detail: .init(ukrainian: "Гаряча лінія підтримки", german: "Beratungshotline"))
    static let equality = SafetyContact(
        number: "0800 206 119",
        title: .init(
            ukrainian: "Служба рівного ставлення", german: "Gleichbehandlungsanwaltschaft"),
        detail: .init(ukrainian: "Пн–чт 9–15, пт 9–12", german: "Mo–Do 9–15, Fr 9–12 Uhr"))
    static let crisis = SafetyContact(
        number: "142", title: .init(ukrainian: "Телефон довіри", german: "Telefonseelsorge"),
        detail: .init(ukrainian: "Підтримка у кризі", german: "Hilfe in Krisen"))
    static let victims = SafetyContact(
        number: "0800 112 112",
        title: .init(ukrainian: "Підтримка потерпілих", german: "Opfer-Notruf"),
        detail: .init(
            ukrainian: "У робочі дні 08:00–20:00 для постраждалих від злочину",
            german: "Werktags 08:00–20:00 für Opfer von Straftaten"))

    static let emergencySource = DirectorySource(
        name: "oesterreich.gv.at · Notrufnummern",
        url:
            "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/notrufnummern"
    )
    static let violenceSource = DirectorySource(
        name: "oesterreich.gv.at · Betretungs- und Annäherungsverbot",
        url:
            "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/5/Seite.299420"
    )
    static let supportSource = DirectorySource(
        name: "Gewaltschutzzentren Österreich · Українською",
        url:
            "https://www.gewaltschutzzentrum.at/uk/%D0%B7%D0%B0%D0%B3%D0%B0%D0%BB%D1%8C%D0%BD%D1%96-%D0%BA%D0%BE%D0%BD%D1%81%D1%83%D0%BB%D1%8C%D1%82%D0%B0%D1%86%D1%96%D1%97-%D1%82%D0%B0-%D0%BF%D1%96%D0%B4%D1%82%D1%80%D0%B8%D0%BC%D0%BA%D0%B0/"
    )

    static func section(
        _ id: String, _ ukTitle: String, _ deTitle: String, _ symbol: String,
        _ ukBody: String, _ deBody: String, _ contacts: [SafetyContact] = []
    ) -> SafetySection {
        SafetySection(
            id: id, title: .init(ukrainian: ukTitle, german: deTitle), symbol: symbol,
            body: .init(ukrainian: ukBody, german: deBody), contacts: contacts)
    }

    static func guide(
        _ uk: String, _ de: String, _ sections: [SafetySection],
        _ sources: [DirectorySource]
    ) -> SafetyGuide {
        SafetyGuide(summary: .init(ukrainian: uk, german: de), sections: sections, sources: sources)
    }
}
