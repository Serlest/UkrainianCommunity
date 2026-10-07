import Foundation

enum CitizenshipGuides {
    static let six = DirectorySource(name: "Österreich.gv.at · Verleihung nach 6 Jahren", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/staatsbuergerschaft/1/Vorzeitige-Verleihung-nach-sechs-Jahren")
    static let ten = DirectorySource(name: "Österreich.gv.at · Verleihung nach 10 Jahren", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/staatsbuergerschaft/1/Verleihung-nach-zehn-Jahren")
    static let conditions = DirectorySource(name: "Österreich.gv.at · Allgemeine Voraussetzungen", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/staatsbuergerschaft/1/Seite.260421")
    static let vienna = DirectorySource(name: "Stadt Wien · Verleihung und Aufenthaltszeiten", url: "https://www.wien.gv.at/amtswege/verleihung-staatsbuergerschaft")
    static let language = DirectorySource(name: "Stadt Wien · Deutschnachweise", url: "https://www.wien.gv.at/zusammenleben/staatsbuergerschaft-deutschkenntnisse")
    static let integration = DirectorySource(name: "Österreich.gv.at · Integrationsvereinbarung", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/Seite.120500")
    static let test = DirectorySource(name: "Stadt Wien · Staatsbürgerschaftstest", url: "https://www.wien.gv.at/zusammenleben/staatsbuergerschaftstest")
    static let documents = DirectorySource(name: "Stadt Wien · Unterlagen für den Antrag", url: "https://www.wien.gv.at/zusammenleben/staatsbuergerschaft-unterlagen")
    static let costs = DirectorySource(name: "Stadt Wien · Kosten", url: "https://www.wien.gv.at/zusammenleben/staatsbuergerschaft-kosten")
    static let dual = DirectorySource(name: "Österreich.gv.at · Doppelstaatsbürgerschaft", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/staatsbuergerschaft/Seite.260430")
    static let children = DirectorySource(name: "Österreich.gv.at · Staatsbürgerschaft für Kinder", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/staatsbuergerschaft/Staatsbuergerschaft-minderjaehriges-Kind")
    static let protection = ResidenceGuides.protection
    static let transition = ResidenceGuides.protectionTransition
    static let student = ResidenceGuides.student
    static let graduates = DirectorySource(name: "Österreich.gv.at · RWR-Karte für Studienabsolventen", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/2/Seite.120229")
    static let ukrainianLaw = DirectorySource(name: "ДМС України · Зміни громадянства 2026", url: "https://dmsu.gov.ua/news/dms/20205.html")
    static let ukrainianExit = DirectorySource(name: "МЗС України · Вихід з громадянства", url: "https://mfa.gov.ua/consul/forua/gromadyanstvo-ua/vyhid")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "overview": overview
        case "six-years": sixYears
        case "ten-years": tenYears
        case "protection": temporaryProtection
        case "student": studentRoute
        case "austrian-spouse": austrianSpouse
        case "other-statuses": otherStatuses
        case "language": languageAndTest
        case "livelihood": livelihood
        case "absences": absences
        case "dual-citizenship": dualCitizenship
        case "children": childrenGuide
        case "documents": applicationDocuments
        case "application": application
        default: nil
        }
    }
}
