import Foundation

/// Links to the competent authority in the state of the home. Eligibility and
/// amounts are intentionally left to the current authority pages.
enum HousingRegionalContent {
    private static let housingAidURLs: [AustrianFederalState: String] = [
        .burgenland: "https://www.burgenland.at/themen/wohnen/wohnbeihilfe-1/",
        .kaernten: "https://www.ktn.gv.at/Service/Formulare-und-Leistungen/BW-L58",
        .niederoesterreich: "https://www.noe.gv.at/noe/Wohnen-Leben/Foerd_Wohnzuschuss_Wohnbeihilfe.html",
        .oberoesterreich: "https://www.land-oberoesterreich.gv.at/wohnbeihilfe.htm",
        .salzburg: "https://www.salzburg.gv.at/themen/bauen-wohnen/wohnbeihilfe",
        .steiermark: "https://www.soziales.steiermark.at/cms/beitrag/10363956/5361/",
        .tirol: "https://www.tirol.gv.at/bauen-wohnen/wohnbaufoerderung/beihilfe/wohnbeihilfe/",
        .vorarlberg: "https://vorarlberg.at/-/wohnbeihilfe?article_id=83241",
        .wien: "https://www.wien.gv.at/amtswege/wohnbeihilfe-antrag"
    ]

    private static let purchaseAuthorityURLs: [AustrianFederalState: String] = [
        .burgenland: "https://www.burgenland.at/verwaltung/bezirksverwaltungsbehoerden/",
        .kaernten: "https://www.ktn.gv.at/Verwaltung/Amt-der-Kaerntner-Landesregierung/Abteilung-10",
        .niederoesterreich: "https://www.noe.gv.at/noe/Kaufen-Verkaufen/Kaufen_Verkaufen.html",
        .oberoesterreich: "https://www.land-oberoesterreich.gv.at/17097.htm",
        .salzburg: "https://www.salzburg.gv.at/themen/aw/grundverkehr",
        .steiermark: "https://www.verwaltung.steiermark.at/cms/ziel/74838178/DE/",
        .tirol: "https://www.tirol.gv.at/bezirke-gemeinden/",
        .vorarlberg: "https://vorarlberg.at/-/grundverkehr?article_id=240289",
        .wien: "https://www.wien.gv.at/amtswege/auslaendergrunderwerb-genehmigung-negativbestaetigung"
    ]

    static func applies(to topicID: String) -> Bool {
        ["arrival-housing", "temporary-housing", "social-housing",
         "housing-support", "foreign-buyers"].contains(topicID)
    }

    static func sections(for topicID: String, state: AustrianFederalState) -> [DirectoryGuideSection] {
        switch topicID {
        case "arrival-housing", "temporary-housing":
            return [DirectoryRegionalContent.basicCareSection(state)]
        case "social-housing":
            return [
                .init("regional-programs", "building.2", "Програми землі та громад", "Landes- und Gemeindeangebote",
                      "Офіційний портал веде до програм житлової підтримки цієї землі. Муніципальне житло часто розподіляє саме місто або громада; умови проживання, доходу й статусу перевіряйте перед заявою.",
                      "Das amtliche Portal verlinkt Wohnprogramme dieses Landes. Gemeindewohnungen vergibt häufig die Gemeinde oder Stadt; prüfen Sie Wohnsitz-, Einkommens- und Statusregeln vor dem Antrag.",
                      source: stateHousingPrograms(state))
            ]
        case "housing-support":
            guard let url = housingAidURLs[state] else { return [] }
            return [
                .init("regional-aid", "eurosign.circle", "Житлова допомога землі", "Wohnbeihilfe des Landes",
                      "Право на Wohnbeihilfe, потрібний статус, дохід, оренда та документи залежать від землі. Перевірте умови й контакт на її офіційній сторінці. Grundversorgung та WOHNSCHIRM мають окремі правила.",
                      "Anspruch, Aufenthaltsstatus, Einkommen, Miete und Nachweise unterscheiden sich je nach Land. Prüfen Sie Bedingungen und Kontakt auf der amtlichen Landes-Seite. Grundversorgung und WOHNSCHIRM haben eigene Regeln.",
                      source: DirectorySource(name: "\(state.displayName) · Wohnbeihilfe", url: url))
            ]
        case "foreign-buyers":
            guard let url = purchaseAuthorityURLs[state] else { return [] }
            return [
                .init("regional-purchase", "building.columns", "Правила за місцем нерухомості", "Regeln am Ort der Immobilie",
                      "Виберіть тут землю, де розташований об’єкт, навіть якщо у профілі вказана інша. Перевірте в її органі Grundverkehr, чи потрібен дозвіл на купівлю для ваших громадянств і конкретного об’єкта, та зверніться до нотаріуса до Kaufanbot.",
                      "Wählen Sie hier das Bundesland der Immobilie, auch wenn Ihr Profil ein anderes nennt. Klären Sie bei dessen Grundverkehrsbehörde, ob für Ihre Staatsangehörigkeit und das Objekt eine Genehmigung nötig ist, und sprechen Sie vor dem Kaufanbot mit einer Notarin oder einem Notar.",
                      source: DirectorySource(name: "\(state.displayName) · Grundverkehr-Information", url: url))
            ]
        default:
            return []
        }
    }

    private static func stateHousingPrograms(_ state: AustrianFederalState) -> DirectorySource {
        let number: String
        switch state {
        case .burgenland: number = "2260403"
        case .kaernten: number = "2260404"
        case .niederoesterreich: number = "2260405"
        case .oberoesterreich: number = "2260406"
        case .salzburg: number = "2260407"
        case .steiermark: number = "2260408"
        case .tirol: number = "2260409"
        case .vorarlberg: number = "2260410"
        case .wien: number = "2260411"
        }
        return DirectorySource(name: "Österreich.gv.at · \(state.displayName)",
                               url: "https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/bauen/3/Seite.\(number)")
    }
}
