import Foundation

enum CommunicationGuides {
    static let contracts = DirectorySource(name: "RTR · Telefon- und Internetverträge", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_Vertraege.de.html")
    static let billing = DirectorySource(name: "RTR · Rechnungen für Telekom und Internet", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_Rechnung.de.html")
    static let mediation = DirectorySource(name: "RTR · Voraussetzungen für Schlichtung", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/voraussetzungen-schlichtungsverfahren.de.html")
    static let prepaid = DirectorySource(name: "RTR · Registrierung von Wertkarten", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/Wertkartenregistrierung.de.html")
    static let portability = DirectorySource(name: "RTR · Mobilnummer mitnehmen", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_PortierungMN.de.html")
    static let roaming = DirectorySource(name: "RTR · Roaming in der EU und Ukraine", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/information/informationen_fuer_konsumenten/TKKS_RoamingEU.de.html")
    static let moving = DirectorySource(name: "RTR · Internetvertrag bei Umzug", url: "https://www.rtr.at/TKP/was_wir_tun/telekommunikation/konsumentenservice/faq/rechnung_und_vertrag.de.html")
    static let post = DirectorySource(name: "Österreichische Post · Briefempfang", url: "https://www.post.at/p/c/brief-empfangen")
    static let postTracking = DirectorySource(name: "Österreichische Post · Sendungsstatus und Zustellung", url: "https://www.post.at/p/c/hilfe-sendungsstatus")
    static let deadlines = DirectorySource(name: "oesterreich.gv.at · Fristen bei Hinterlegung", url: "https://www.oesterreich.gv.at/de/lexicon/F/Seite.991113")
    static let postlagernd = DirectorySource(name: "Österreichische Post · Postlagernd", url: "https://www.post.at/p/a/postlagernd")
    static let forwarding = DirectorySource(name: "Österreichische Post · Nachsendeauftrag", url: "https://www.post.at/p/a/nachsenden")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "phone": phone
        case "internet": internet
        case "postal": postal
        default: nil
        }
    }
}
