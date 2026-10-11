import Foundation

enum LegalGuides {
    static let orientation = DirectorySource(name: "oesterreich.gv.at · Rechtsauskünfte", url: "https://www.oesterreich.gv.at/de/themen/gesetze_und_recht/buergerservice_rechtsauskuenfte/Seite.980300")
    static let legalAid = DirectorySource(name: "oesterreich.gv.at · Kosten und Verfahrenshilfe", url: "https://www.oesterreich.gv.at/de/themen/gesetze_und_recht/gerichtsorganisation_der_justiz/zivilrecht/2/Seite.1010330")
    static let appeal = DirectorySource(name: "oesterreich.gv.at · Beschwerde bei Verwaltungsgerichten", url: "https://www.oesterreich.gv.at/de/themen/gesetze_und_recht/verwaltungsgerichtsbarkeit/Seite.3130005")
    static let asylum = DirectorySource(name: "oesterreich.gv.at · Asylverfahren", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/asyl-in-oesterreich/Seite.3210002")
    static let bbu = DirectorySource(name: "BBU · Rechtsberatung und Vertretung", url: "https://www.bbu.gv.at/was-wir-tun")
    static let ombudsman = DirectorySource(name: "Volksanwaltschaft · Beschwerdewegweiser", url: "https://volksanwaltschaft.gv.at/fuer-probleme-mit-behoerden/beschwerdewegweiser/")
    static let warranty = DirectorySource(name: "Arbeiterkammer · Gewährleistung", url: "https://www.arbeiterkammer.at/beratung/konsument/konsumundeinkauf/kaufundrechte/Gewaehrleistung_ab_1.1.2022.html")
    static let repairs = DirectorySource(name: "Arbeiterkammer · Recht auf Reparatur", url: "https://www.arbeiterkammer.at/beratung/konsument/konsumundeinkauf/kaufundrechte/Recht-auf-Reparatur.html")
    static let withdrawal = DirectorySource(name: "Arbeiterkammer · Rücktrittsrecht", url: "https://www.arbeiterkammer.at/beratung/konsument/konsumundeinkauf/kaufundrechte/Ruecktrittsrecht.html")
    static let onlineTrade = DirectorySource(name: "Arbeiterkammer · Rechte im Onlinehandel", url: "https://arbeiterkammer.at/beratung/konsument/konsumundeinkauf/kaufundrechte/Rechte_im_Onlinehandel.html")
    static let interpreters = DirectorySource(name: "Justiz · Gerichtsdolmetscherliste", url: "https://edikte.justiz.gv.at/edikte/ex/edparm3.nsf/h/SVPHLdf01")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "legal-aid": legalHelp
        case "authorities": authorities
        case "consumer-rights": consumers
        case "interpreting": interpreting
        default: nil
        }
    }
}
