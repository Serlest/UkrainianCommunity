import Foundation

enum AccessibilityGuides {
    static let pass = DirectorySource(name: "Sozialministeriumservice · Behindertenpass", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Behindertenpass/Behindertenpass.de.html")
    static let entries = DirectorySource(name: "Sozialministeriumservice · Zusatzeintragungen", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Behindertenpass/zusatzeintragungen/zusatzeintragungen.de.html")
    static let parking = DirectorySource(name: "Sozialministeriumservice · Parkausweis", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Behindertenpass_und_Parkausweis/Parkausweis/Parkausweis.de.html")
    static let employmentStatus = DirectorySource(name: "Sozialministeriumservice · Begünstigte Behinderte", url: "https://sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Ausbildung__Beruf_und_Beschaeftigung/Beguenstigte_Behinderte/Beguenstigte_Behinderte.html")
    static let equality = DirectorySource(name: "Sozialministeriumservice · Gleichstellung und Barrierefreiheit", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Gleichstellung/Barrierefreiheit/Gleichstellung-und-Barrierefreiheit.de.html")
    static let mediation = DirectorySource(name: "Sozialministeriumservice · Schlichtung", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Gleichstellung/Schlichtung/Schlichtung.de.html")
    static let advocate = DirectorySource(name: "Behindertenanwaltschaft · Beratung", url: "https://sozialministeriumservice.gv.at/Angehoerige/Gleichstellung/Behindertenanwaltschaft/BEHINDERTENANWALT.LL.html")
    static let workAssistance = DirectorySource(name: "Sozialministeriumservice · Persönliche Assistenz am Arbeitsplatz", url: "https://sozialministeriumservice.gv.at/weitere_Zielgruppen/Sonstige_Massnahmen_und_Projekte/Persoenliche_Assistenz_am_Arbeitsplatz/Persoenliche-Assistenz-am-Arbeitsplatz.de.html")
    static let workplace = DirectorySource(name: "Sozialministeriumservice · Arbeit und Ausbildung", url: "https://www.sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Ausbildung__Beruf_und_Beschaeftigung/Arbeit_und_Ausbildung/Arbeit_und_Ausbildung.de.html")
    static let medicalDevices = DirectorySource(name: "Gesundheitsportal · Heilbehelfe und Hilfsmittel", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/heilbehelfe-hilfsmittel.html")
    static let fund = DirectorySource(name: "Sozialministeriumservice · Unterstützungsfonds", url: "https://sozialministeriumservice.gv.at/Menschen_mit_Behinderung/Finanzielle_Unterstuetzung/Sonstige_finanzielle_Vorteile/Unterstuetzungsfonds/Unterstuetzungsfonds.de.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "disability": disability
        case "accessible-services": services
        case "assistive-devices": devices
        default: nil
        }
    }
}
