import Foundation

enum CareGuides {
    static let apply = DirectorySource(name: "oesterreich.gv.at · Antrag auf Pflegegeld", url: "https://www.oesterreich.gv.at/de/themen/pflege/4/1/Seite.360517")
    static let amounts = DirectorySource(name: "oesterreich.gv.at · Höhe des Pflegegeldes", url: "https://www.oesterreich.gv.at/de/themen/pflege/4/Seite.360516")
    static let eligibility = DirectorySource(name: "oesterreich.gv.at · Voraussetzungen für Pflegegeld", url: "https://www.oesterreich.gv.at/de/themen/pflege/4/Seite.360512")
    static let appeal = DirectorySource(name: "pflege.gv.at · Pflegegeldklage", url: "https://pflege.gv.at/bs/node/69")
    static let homeVisit = DirectorySource(name: "pflege.gv.at · Hausbesuche durch Pflegepersonen", url: "https://pflege.gv.at/de/hausbesuche-durch-diplomierte-gesundheits-und-krankenpflegepersonen")
    static let relatives = DirectorySource(name: "Sozialministeriumservice · Unterstützung für pflegende Angehörige", url: "https://www.sozialministeriumservice.gv.at/Angehoerige/Pflege_und_Betreuung/Pflegende_Angehoerige/Unterstuetzung_fuer_pflegende_Angehoerige.de.html")
    static let leave = DirectorySource(name: "pflege.gv.at · Pflegefreistellung und Pflegekarenz", url: "https://pflege.gv.at/de/pflegefreistellung-pflegeteilzeit-und-pflegekarenz")
    static let mobile = DirectorySource(name: "oesterreich.gv.at · Soziale Dienste", url: "https://www.oesterreich.gv.at/de/themen/pflege/soziale_dienste/Seite.1210200")
    static let nursing = DirectorySource(name: "pflege.gv.at · Mobile Hauskrankenpflege", url: "https://pflege.gv.at/de/hauskrankenpflege")
    static let respite = DirectorySource(name: "pflege.gv.at · Kurzzeit- und Ersatzpflege", url: "https://pflege.gv.at/de/kurzzeitpflege-ersatzpflege-und-urlaubspflege")
    static let transition = DirectorySource(name: "pflege.gv.at · Übergangspflege", url: "https://pflege.gv.at/de/uebergangspflege")
    static let roundClock = DirectorySource(name: "Sozialministeriumservice · 24-Stunden-Betreuung", url: "https://www.sozialministeriumservice.gv.at/Angehoerige/Pflege_und_Betreuung/24-Stunden-Betreuung/24-Stunden-Betreuung.de.html")
    static let children = DirectorySource(name: "pflege.gv.at · Kinder und Jugendliche zu Hause", url: "https://pflege.gv.at/de/pflege-und-betreuung-von-kindern-und-jugendlichen-zu-hause")
    static let home = DirectorySource(name: "oesterreich.gv.at · Kosten für Pflegeheime", url: "https://www.oesterreich.gv.at/de/themen/pflege/2/Seite.360542")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "home-care": homeCare
        case "care-services": careServices
        default: nil
        }
    }
}
