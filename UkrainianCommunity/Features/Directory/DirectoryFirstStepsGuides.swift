import Foundation

enum FirstStepsGuides {
    static let bbu = DirectorySource(name: "BBU · Erstankunft / Прибуття", url: "https://www.bbu.gv.at/ukraine")
    static let bbuFAQ = DirectorySource(name: "BBU · Info/FAQ (UA)", url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")
    static let police = DirectorySource(name: "BMI · Erfassung und Aufenthalt", url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    static let housing = DirectorySource(name: "BMI · Unterkunft suchen", url: "https://www.bmi.gv.at/ukraine/suche_unterkunft.html")
    static let address = DirectorySource(name: "oesterreich.gv.at · Wohnsitz anmelden", url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180200")
    static let school = DirectorySource(name: "Bildungsministerium · Schule und Ukraine", url: "https://www.bmb.gv.at/Themen/schule/beratung/ukraine.html")
    static let work = DirectorySource(name: "AMS · Informationen für Vertriebene", url: "https://www.ams.at/arbeitsuchende/arbeiten-in-oesterreich-und-der-eu/ukraine/ukraine-informationen-deutsch")
    static let language = DirectorySource(name: "ÖIF · Deutschkurse", url: "https://www.integrationsfonds.at/angebote/integrationsmassnahmen/deutsch-lernen/deutschkurse/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "arrival": arrival
        case "checklist": checklist
        default: nil
        }
    }
}
