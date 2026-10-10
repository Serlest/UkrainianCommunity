import Foundation

enum RegistrationGuides {
    static let addressSource = DirectorySource(
        name: "oesterreich.gv.at · Wohnsitz anmelden",
        url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180200")
    static let formSource = DirectorySource(
        name: "oesterreich.gv.at · Meldezettel (PDF)",
        url: "https://www.oesterreich.gv.at/dam/jcr%3Ad0c97509-1a04-4b5a-8626-8a5f9e6b4b39/Meldezettel_2023_ausfuellbar.pdf")
    static let registrationSource = DirectorySource(
        name: "BMI · Erfassung und Aufenthalt Ukraine",
        url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    static let bfaContactSource = DirectorySource(
        name: "BFA · Regionaldirektionen und Kontakt",
        url: "https://www.bfa.gv.at/kontakt/")
    static let addressChangeSource = DirectorySource(
        name: "oesterreich.gv.at · Ummeldung",
        url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180210")
    static let addressDepartureSource = DirectorySource(
        name: "oesterreich.gv.at · Wohnsitz abmelden",
        url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180220")
    static let movingChecklistSource = DirectorySource(
        name: "oesterreich.gv.at · Nach dem Umzug",
        url: "https://www.oesterreich.gv.at/de/lebenslagen/Ich-wohne-bald-in-einem-neuen-Zuhause/Nach-dem-Umzug")
    static let confirmationSource = DirectorySource(
        name: "oesterreich.gv.at · Meldebestätigung",
        url: "https://www.oesterreich.gv.at/de/themen/persoenliche_dokumente_und_bestaetigungen/an__abmeldung_des_wohnsitzes/Seite.1180300")
    static let digitalServiceSource = DirectorySource(
        name: "oesterreich.gv.at · Digitale Amtsservices",
        url: "https://www.oesterreich.gv.at/de/hilfe/Hilfe-zu-oesterreich.gv.at/Digitale-Amtsservices-")
    static let bfaNameSource = DirectorySource(
        name: "BMI · Sonstige Fragen zur Ukraine",
        url: "https://www.bmi.gv.at/ukraine/sonstige_fragen.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "residence-registration": residence
        case "housing-types": housingTypes
        case "protection-registration": protection
        case "after-registration": afterRegistration
        case "address-change": moving
        case "leaving-austria": leaving
        case "registration-errors": errors
        default: nil
        }
    }
}
