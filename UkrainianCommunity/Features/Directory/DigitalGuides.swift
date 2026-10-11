import Foundation

enum DigitalGuides {
    static let catalog = DirectorySource(name: "oesterreich.gv.at · Digitale Services", url: "https://www.oesterreich.gv.at/de/digitalservices")
    static let onlineProcesses = DirectorySource(name: "oesterreich.gv.at · Digitale Amtswege", url: "https://www.oesterreich.gv.at/de/themen/transparenz_und_partizipation_in_der_demokratie/digitale-amtswege")
    static let finance = DirectorySource(name: "BMF · FinanzOnline Zugang", url: "https://www.bmf.gv.at/services/finanzonline/informationen-fuer-buerger/einstiegsinformationen.html")
    static let financeRecovery = DirectorySource(name: "BMF · FinanzOnline Anmeldehilfe", url: "https://www.bmf.gv.at/services/finanzonline/anmeldehilfe.html")
    static let elga = DirectorySource(name: "Gesundheitsportal · ELGA Login", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/elga/elga-login-teilnahme.html")
    static let postbox = DirectorySource(name: "oesterreich.gv.at · Mein Postkorb", url: "https://www.oesterreich.gv.at/de/hilfe/Die-elektronische-Zustellung-und-Mein-Postkorb")
    static let delivery = DirectorySource(name: "oesterreich.gv.at · Zustellung über Mein Postkorb", url: "https://www.oesterreich.gv.at/de/themen/egovernment_moderne_verwaltung/Elektronische-Zustellung/ablauf-der-zustellung-%C3%BCber-meinpostkorb")
    static let pdfSignature = DirectorySource(name: "oesterreich.gv.at · PDF Signatur", url: "https://www.oesterreich.gv.at/de/landingpages/pdf_signatur_services")
    static let registration = DirectorySource(name: "oesterreich.gv.at · ID Austria Registrierung", url: "https://www.oesterreich.gv.at/id-austria/haeufige-fragen/registrierung.html")
    static let app = DirectorySource(name: "oesterreich.gv.at · App ID Austria", url: "https://www.oesterreich.gv.at/de/ueber-oesterreichgvat/neu")
    static let identityManagement = DirectorySource(name: "ID Austria · Konto verwalten", url: "https://www.id-austria.gv.at/de/verwalten")
    static let newPhone = DirectorySource(name: "ID Austria · Neues Smartphone verknüpfen", url: "https://www.id-austria.gv.at/de/hilfe/hilfe-zur-app-ida/smartphone-anmelden-in-der-app-id-austria")
    static let identityContact = DirectorySource(name: "oesterreich.gv.at · Kontakt und Widerruf", url: "https://www.oesterreich.gv.at/de/kontakt")
    static let digitalCards = DirectorySource(name: "oesterreich.gv.at · eAusweise", url: "https://www.oesterreich.gv.at/eausweise/haeufige-fragen/haeufige-fragen-eausweise-allgemein.html")
    static let phishing = DirectorySource(name: "Bundeskriminalamt · Phishing/Smishing/Quishing", url: "https://www.bundeskriminalamt.at/212/internet/phishing_smishing.html")
    static let police = DirectorySource(name: "Bundeskriminalamt · Anzeige erstatten", url: "https://www.bundeskriminalamt.at/212/wie_erstatte_ich_anzeige/start.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "online-services": onlineServices
        case "digital-identity": digitalIdentity
        case "online-safety": onlineSafety
        default: nil
        }
    }
}
