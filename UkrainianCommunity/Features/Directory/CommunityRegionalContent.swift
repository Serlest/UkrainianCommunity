import Foundation

enum CommunityRegionalContent {
    private struct Center {
        let address: String
        let page: String
    }

    private static let centers: [AustrianFederalState: Center] = [
        .burgenland: .init(address: "Thomas-Alva-Edison-Straße 2, 7000 Eisenstadt", page: "burgenland"),
        .kaernten: .init(address: "10. Oktoberstraße 15, 9020 Klagenfurt", page: "kaernten"),
        .niederoesterreich: .init(address: "Wiener Straße 12, 3100 St. Pölten", page: "niederoesterreich"),
        .oberoesterreich: .init(address: "Weingartshofstraße 25, 4020 Linz", page: "oberoesterreich"),
        .salzburg: .init(address: "Inge Morath-Platz 18, 5020 Salzburg", page: "salzburg"),
        .steiermark: .init(address: "Reitschulgasse 19, 8010 Graz", page: "steiermark"),
        .tirol: .init(address: "Lieberstraße 3, 6020 Innsbruck", page: "tirol"),
        .vorarlberg: .init(address: "Bahnhofstraße 10, 6900 Bregenz", page: "vorarlberg"),
        .wien: .init(address: "Landstraßer Hauptstraße 26, 1030 Wien", page: "wien")
    ]

    static func sections(for state: AustrianFederalState) -> [DirectoryGuideSection] {
        guard let center = centers[state] else { return [] }
        let source = DirectorySource(name: "ÖIF · Integrationszentrum \(state.displayName)",
                                     url: "https://www.integrationsfonds.at/der-oeif/standorte/\(center.page)/")
        return [
            .init("regional-integration", "person.2", "Інтеграційний центр вашої землі", "Integrationszentrum Ihres Bundeslandes",
                  "Для землі \(state.displayName) ÖIF вказує адресу: \(center.address). Перед поїздкою перевірте на сторінці центру час роботи та спосіб запису. За номером 050 46 80 уточніть, чи вам потрібна консультація тут або ближча пропозиція у вашому районі.",
                  "Für \(state.displayName) nennt der ÖIF die Adresse \(center.address). Vor Anreise Öffnungszeiten und Terminweg auf der Standortseite prüfen. Unter 050 46 80 klären, ob Beratung hier oder ein näheres Angebot im eigenen Bezirk passt.",
                  phoneNumber: "050 46 80", source: source)
        ]
    }
}
