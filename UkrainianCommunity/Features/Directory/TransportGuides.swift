import Foundation

enum TransportGuides {
    static let climate = DirectorySource(name: "KlimaTicket · Gültigkeit", url: "https://www.klimaticket.at/gueltigkeitskarte/")
    static let regionalTickets = DirectorySource(name: "oesterreich.gv.at · KlimaTicket und regionale Tickets", url: "https://www.oesterreich.gv.at/de/themen/mobilitaet/klimaticket")
    static let routePlanner = DirectorySource(name: "ÖBB · Scotty Fahrplanauskunft", url: "https://www.oebb.at/de/fahrplan/fahrplanauskunft/scottymobil")
    static let ticketModels = DirectorySource(name: "BMIMI · Verbundtarifmodelle", url: "https://www.bmimi.gv.at/themen/mobilitaet/transport/nahverkehr/verkehrsverbuende/verbundtarife/modelle.html")
    static let localTickets = DirectorySource(name: "ÖBB · Verkehrsverbund-Tickets", url: "https://www.oebb.at/de/tickets-kundenkarten/oesterreich-europa/verbundtickets")
    static let rail = DirectorySource(name: "ÖBB · Tickets und Buchungen", url: "https://www.oebb.at/de/fragen-und-antworten/tickets-kaufen/online-mobile-ticketing/tickets-buchungen")
    static let railFare = DirectorySource(name: "ÖBB · Sparschiene", url: "https://www.oebb.at/de/tickets-kundenkarten/oesterreich-europa/sparschiene")
    static let railRights = DirectorySource(name: "apf · Verspätung und Zugausfall", url: "https://www.apf.gv.at/bahn-verspaetung-zugausfall")
    static let railComplaint = DirectorySource(name: "apf · Fristen Bahn", url: "https://www.apf.gv.at/bahn-fristen")
    static let busRights = DirectorySource(name: "apf · Fahrgastrechte Bus", url: "https://www.apf.gv.at/bus-fahrgastrechte")
    static let busDelay = DirectorySource(name: "apf · Busverspätung und Ausfall", url: "https://www.apf.gv.at/bus-verspaetung-ausfall")
    static let taxi = DirectorySource(name: "BMIMI · Gelegenheitsverkehr und Taxi", url: "https://www.bmimi.gv.at/themen/mobilitaet/transport/personen_gueter/recht/gelegenheitsverkehr.html")
    static let taxiLicence = DirectorySource(name: "oesterreich.gv.at · Taxilenkerausweis", url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/fuehrerschein/Seite.040103")
    static let taxiTariff = DirectorySource(name: "Stadt Wien · Taxitarif als Beispiel", url: "https://www.wien.gv.at/wirtschaft/taxi-gewerbe")
    static let mobility = DirectorySource(name: "ÖBB · Mobilitätsservice", url: "https://www.oebb.at/de/reiseplanung-services/barrierefrei-reisen/mobilitaetsservice")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "local-transport": localTransport
        case "rail": railGuide
        case "bus": bus
        case "taxi": taxiGuide
        case "accessible-travel": accessibleTravel
        default: nil
        }
    }
}
