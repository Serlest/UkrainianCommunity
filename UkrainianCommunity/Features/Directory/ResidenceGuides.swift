import Foundation

enum ResidenceGuides {
    static let permits = DirectorySource(name: "BMI · Aufenthaltstitel", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/Seite.120221")
    static let conditions = DirectorySource(name: "BMI · Allgemeine Voraussetzungen", url: "https://eausweise.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/Seite.120217")
    static let firstApplication = DirectorySource(name: "BMI · Erstantrag", url: "https://eausweise.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/1/Seite.120222")
    static let visa = DirectorySource(name: "BMI · Visumkategorien", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/visum_fuer_oesterreich/Seite.3550020")
    static let protection = DirectorySource(name: "BMI · Erfassung und Aufenthalt Ukraine", url: "https://www.bmi.gv.at/ukraine/erfassung_und_aufenthalt.html")
    static let protectionTransition = DirectorySource(name: "BMI · Umstieg auf RWR-Karte plus", url: "https://www.bmi.gv.at/ukraine/informationen_zum_umstieg_auf_eine_rot-_weiss_rot_karte_plus.html")
    static let protectionChangeAnnouncement = DirectorySource(name: "BMI · Angekündigte Änderung der Vertriebenen-Verordnung", url: "https://www.bmi.gv.at/news52f3.html?id=2b2b5069366874715551633d")
    static let asylum = DirectorySource(name: "BMI · Asyl in Österreich", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/asyl-in-oesterreich/Seite.3210001")
    static let asylumFamily = DirectorySource(name: "BMI · Familiennachzug zu international Schutzberechtigten", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/Familienzusammenf%C3%BChrung-zu-international-Schutzberechtigten----Rot-Wei%C3%9F-Rot-%E2%80%93-Karte-plus--%E2%80%93-Antrag-%28%C2%A7-46a-NAG%29")
    static let student = DirectorySource(name: "BMI · Aufenthaltsbewilligung Student", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/1/1/Seite.120121")
    static let studentWork = DirectorySource(name: "BMAW · Studierende und Beschäftigung", url: "https://www.migration.gv.at/de/formen-der-zuwanderung/temporaerer-aufenthalt/")
    static let studentOeAD = DirectorySource(name: "OeAD · Aufenthalt Student 2026", url: "https://oead.at/de/nach-oesterreich/einreise-und-aufenthalt/aufenthaltsbewilligung-student-kein-mobilitaetsprogramm")
    static let austrianFamily = DirectorySource(name: "BMI · Aufenthaltstitel Familienangehöriger", url: "https://eausweise.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/Seite.120401")
    static let euFamily = DirectorySource(name: "BMI · EU-/EWR-Familie", url: "https://www.oesterreich.gv.at/de/lebenslagen/Ich-m%C3%B6chte-als-ausl%C3%A4ndischer-staatsb%C3%BCrger-in-%C3%B6sterreich-bleiben/EU-B%C3%BCrger_Angeh%C3%B6rige")
    static let euFamilyCard = DirectorySource(name: "BMI · Aufenthaltskarte für EU-Familien", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/1/Seite.120830")
    static let thirdCountryFamily = DirectorySource(name: "BMAW · Familienzusammenführung", url: "https://www.migration.gv.at/de/formen-der-zuwanderung/dauerhafte-zuwanderung/familienzusammenfuehrung/")
    static let work = DirectorySource(name: "BMAW · Dauerhafte Zuwanderung", url: "https://www.migration.gv.at/?id=34")
    static let rwrPlus = DirectorySource(name: "BMAW · Rot-Weiß-Rot-Karte plus", url: "https://www.migration.gv.at/de/formen-der-zuwanderung/dauerhafte-zuwanderung/rotweirotkarteplus/")
    static let renewal = DirectorySource(name: "BMI · Verlängerungsantrag", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/1/Seite.120223")
    static let permanent = DirectorySource(name: "BMI · Daueraufenthalt – EU", url: "https://www.oesterreich.gv.at/de/themen/menschen_aus_anderen_staaten/aufenthalt/3/2/Seite.120402")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "residence-permits": overview
        case "temporary-protection": temporaryProtection
        case "international-protection": internationalProtection
        case "student-residence": studentResidence
        case "austrian-family": austrianFamilyGuide
        case "eu-family": euFamilyGuide
        case "third-country-family": thirdCountryFamilyGuide
        case "work-residence": workResidence
        case "rwr-plus": rwrPlusGuide
        case "status-change": statusChange
        case "residence-renewal": residenceRenewal
        case "permanent-residence": permanentResidence
        default: nil
        }
    }
}
