import Foundation

/// Direct route to the competent local ticket and timetable provider.
enum TransportRegionalContent {
    private static func provider(for state: AustrianFederalState) -> DirectorySource {
        switch state {
        case .burgenland, .niederoesterreich, .wien:
            DirectorySource(name: "VOR · Wien, Niederösterreich, Burgenland", url: "https://www.vor.at/")
        case .kaernten:
            DirectorySource(name: "Kärntner Linien · Verkehrsverbund Kärnten", url: "https://www.kaerntner-linien.at/")
        case .oberoesterreich:
            DirectorySource(name: "OÖVV · Oberösterreich", url: "https://www.ooevv.at/de/")
        case .salzburg:
            DirectorySource(name: "Salzburg Verkehr · Salzburger Verkehrsverbund", url: "https://salzburg-verkehr.at/")
        case .steiermark:
            DirectorySource(name: "Verbund Linie · Steiermark", url: "https://www.verbundlinie.at/de/")
        case .tirol:
            DirectorySource(name: "VVT · Verkehrsverbund Tirol", url: "https://www.vvt.at/")
        case .vorarlberg:
            DirectorySource(name: "VMOBIL · Verkehrsverbund Vorarlberg", url: "https://www.vmobil.at/de")
        }
    }

    static func sections(for state: AustrianFederalState) -> [DirectoryGuideSection] {
        let source = provider(for: state)
        return [
            .init("regional-transport", "tram", "Маршрут і квиток у вашій землі", "Fahrplan und Ticket in Ihrem Bundesland",
                  "Для землі \(state.displayName) відкрийте \(source.name): введіть початок і кінець маршруту, перевірте ціну, чинність квитка й повідомлення про рух. Якщо зараз їдете в іншій землі, переключіть вибір вище. Для поїздки через межу об’єднання перевірте весь маршрут перед оплатою.",
                  "Für \(state.displayName) \(source.name) öffnen: Start und Ziel eingeben, Preis, Ticketgültigkeit und Verkehrsmeldungen prüfen. Reisen Sie gerade in einem anderen Bundesland, Auswahl oben ändern. Bei Verbundgrenzen die ganze Strecke vor Zahlung prüfen.",
                  source: source)
        ]
    }
}
