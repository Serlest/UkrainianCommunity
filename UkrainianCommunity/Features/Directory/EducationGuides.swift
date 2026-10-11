import Foundation

enum EducationGuides {
    static let kindergarten = DirectorySource(name: "oesterreich.gv.at · Kindergartenanmeldung", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/geburt-eines-kindes/3/1/Seite.080800")
    static let kindergartenRules = DirectorySource(name: "oesterreich.gv.at · Kindergärten nach Bundesland", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/2/Seite.370130")
    static let childcareSupport = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsbeihilfe", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/Seite.370300")
    static let school = DirectorySource(name: "oesterreich.gv.at · Schuleinschreibung", url: "https://www.oesterreich.gv.at/de/themen/bildung_und_ausbildung/schulen/4/Seite.110031")
    static let schoolDuty = DirectorySource(name: "oesterreich.gv.at · Allgemeine Schulpflicht", url: "https://www.oesterreich.gv.at/de/themen/bildung_und_ausbildung/schulen/Seite.110002")
    static let schoolUntil18 = DirectorySource(name: "oesterreich.gv.at · AusBildung bis 18", url: "https://eausweise.oesterreich.gv.at/de/themen/bildung_und_ausbildung/lehre-und-berufsbildende-schulen/ausbildung_bis_18")
    static let schoolLanguage = DirectorySource(name: "oesterreich.gv.at · Deutschförderung", url: "https://www.oesterreich.gv.at/de/themen/bildung_und_ausbildung/schulen/Seite.110005")
    static let schoolCounseling = DirectorySource(name: "Schulpsychologie · Beratungsstellen", url: "https://www.schulpsychologie.at/beratungsstellen")
    static let summerSchool = DirectorySource(name: "oesterreich.gv.at · Sommerschule", url: "https://www.oesterreich.gv.at/de/themen/bildung_und_ausbildung/schulen/sommerschule")
    static let higher = DirectorySource(name: "OeAD · Studiengebühren", url: "https://studyinaustria.at/de/studium-planen/studiengebuehr")
    static let ukraineHigher = DirectorySource(name: "OeAD · Informationen für Studierende aus der Ukraine", url: "https://studyinaustria.at/en/studium/oead4refugees/informacija-dlja-studentiv-ta-doslidnikiv-z-ukrajini")
    static let preparation = DirectorySource(name: "OeAD · Vorstudienlehrgänge", url: "https://studyinaustria.at/de/studium-planen/deutsch-lernen/vorstudienlehrgaenge")
    static let studentPermit = DirectorySource(name: "OeAD · Aufenthaltsbewilligung Student", url: "https://oead.at/de/nach-oesterreich/einreise-und-aufenthalt/aufenthaltsbewilligung-student-kein-mobilitaetsprogramm")
    static let scholarships = DirectorySource(name: "OeAD · Stipendien und Finanzierung", url: "https://studyinaustria.at/en/plan-your-studies/scholarships-funding")
    static let german = DirectorySource(name: "ÖIF · Deutschkurs-Anmeldung", url: "https://www.integration.at/angebote/integrationsmassnahmen/deutsch-lernen/deutschkurse/deutschkurs-anmeldung/")
    static let germanOnline = DirectorySource(name: "ÖIF · Sprachportal", url: "https://sprachportal.at/deutsch-lernen/")
    static let germanUkraine = DirectorySource(name: "ÖIF · Deutschkurse für Vertriebene", url: "https://www.integration.at/themen/ukraine/")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "kindergarten": kindergartenGuide
        case "school": schoolGuide
        case "higher-education": higherEducation
        case "language": language
        default: nil
        }
    }
}
