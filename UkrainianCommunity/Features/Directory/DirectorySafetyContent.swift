import Foundation

struct SafetyContact: Identifiable {
    let number: String
    let title: DirectoryText
    let detail: DirectoryText

    var id: String { number }
    var phoneURL: URL { URL(string: "tel:\(number.replacingOccurrences(of: " ", with: ""))")! }
}

struct SafetySource: Identifiable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }
}

enum DirectorySafetyContent {
    static let publishedTopicIDs: Set<String> = ["emergency", "domestic-violence"]
    static let reviewedOn = "07.10.2026"

    static let police = SafetyContact(
        number: "133", title: .init(ukrainian: "Поліція", german: "Polizei"),
        detail: .init(ukrainian: "Негайна небезпека або насильство", german: "Akute Gefahr oder Gewalt")
    )
    static let europeanEmergency = SafetyContact(
        number: "112", title: .init(ukrainian: "Європейський екстрений номер", german: "Euro-Notruf"),
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
        number: "0800 222 555", title: .init(ukrainian: "Допомога жінкам, які зазнали насильства", german: "Frauenhelpline gegen Gewalt"),
        detail: .init(ukrainian: "Безкоштовно, цілодобово, по всій Австрії", german: "Kostenlos, rund um die Uhr, österreichweit")
    )
    static let protectionCentre = SafetyContact(
        number: "0800 700 217", title: .init(ukrainian: "Центри захисту від насильства", german: "Gewaltschutzzentren"),
        detail: .init(ukrainian: "Консультація і підтримка після насильства", german: "Beratung und Unterstützung nach Gewalt")
    )

    static let emergencySource = SafetySource(
        name: "oesterreich.gv.at · Notrufnummern",
        url: URL(string: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/notrufnummern")!
    )
    static let violenceSource = SafetySource(
        name: "oesterreich.gv.at · Häusliche Gewalt",
        url: URL(string: "https://www.oesterreich.gv.at/de/themen/notfaelle_unfaelle_und_kriminalitaet/hilfe-bei-gewalt/2/Seite.290501")!
    )
    static let supportSource = SafetySource(
        name: "Gewaltschutzzentren Österreich · Українською",
        url: URL(string: "https://www.gewaltschutzzentrum.at/uk/%D0%B7%D0%B0%D0%B3%D0%B0%D0%BB%D1%8C%D0%BD%D1%96-%D0%BA%D0%BE%D0%BD%D1%81%D1%83%D0%BB%D1%8C%D1%82%D0%B0%D1%86%D1%96%D1%97-%D1%82%D0%B0-%D0%BF%D1%96%D0%B4%D1%82%D1%80%D0%B8%D0%BC%D0%BA%D0%B0/")!
    )
}
