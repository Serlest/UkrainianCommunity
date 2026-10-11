import Foundation

enum CommunityGuides {
    static let authoritySearch = DirectorySource(name: "oesterreich.gv.at · Behördensuche", url: "https://www.oesterreich.gv.at/de/orgsearch")
    static let centers = DirectorySource(name: "ÖIF · Standorte in Österreich", url: "https://www.integrationsfonds.at/der-oeif/standorte/uebersicht-standorte/")
    static let ukraine = DirectorySource(name: "ÖIF · Informationen für Vertriebene", url: "https://www.integration.at/themen/ukraine/")
    static let women = DirectorySource(name: "ÖIF · Frauenzentren", url: "https://www.integrationsfonds.at/angebote/integrationsmassnahmen/frauen/")
    static let events = DirectorySource(name: "ÖIF · Termine", url: "https://www.integrationsfonds.at/der-oeif/termine/")
    static let associationRegister = DirectorySource(name: "oesterreich.gv.at · Vereinsregister", url: "https://www.oesterreich.gv.at/de/themen/reisen_und_freizeit/vereine/Seite.220700")
    static let volunteerCenters = DirectorySource(name: "Freiwilligenweb · Freiwilligenzentren", url: "https://www.freiwilligenweb.at/nuetzliches/freiwilligenzentren/")
    static let volunteerProjects = DirectorySource(name: "Servicestelle freiwillig engagiert · Projekte", url: "https://www.freiwillig-engagiert.at/jetzt-engagieren")
    static let volunteerRegister = DirectorySource(name: "Freiwilligenweb · FWO-Register", url: "https://www.freiwilligenweb.at/freiwilligenorganisationen/")
    static let volunteerRights = DirectorySource(name: "Freiwilligenweb · Rechtliche Rahmenbedingungen", url: "https://www.freiwilligenweb.at/freiwilliges-engagement/rechtliche-rahmenbedingungen/")
    static let volunteerRecord = DirectorySource(name: "Freiwilligenweb · Freiwilligen-Nachweis", url: "https://www.freiwilligenweb.at/freiwilliges-engagement/freiwilligen-nachweis/")
    static let amsChanges = DirectorySource(name: "AMS · Meldepflichten", url: "https://www.ams.at/arbeitsuchende/arbeitslos-was-tun/ihre-meldepflichten")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "local-services": localServices
        case "community": community
        case "volunteering": volunteeringGuide
        default: nil
        }
    }
}
