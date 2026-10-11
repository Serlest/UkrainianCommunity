import Foundation

enum FamilyGuides {
    static let childcare = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuung", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/2/Seite.370110")
    static let childcareFunding = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsbeihilfe", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/Seite.370300")
    static let dayParents = DirectorySource(name: "oesterreich.gv.at · Tageseltern", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/2/Seite.370140")
    static let familyAdvice = DirectorySource(name: "Familienberatung · Häufige Fragen", url: "https://www.familienberatung.gv.at/faq.html")
    static let familySearch = DirectorySource(name: "Bundeskanzleramt · Familienberatung", url: "https://www.familienberatung.gv.at/")
    static let onlineAdvice = DirectorySource(name: "Familienberatung · Onlineberatung", url: "https://www.familienberatung.gv.at/was-ist-onlineberatung.html")
    static let childHelp = DirectorySource(name: "Rat auf Draht · Telefonberatung 147", url: "https://www.rataufdraht.at/telefonberatung")
    static let childrenAdvocate = DirectorySource(name: "oesterreich.gv.at · Kinder- und Jugendanwaltschaften", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/ombudsstellen_und_anwaltschaften/Seite.3240006")
    static let youthWelfare = DirectorySource(name: "Bundeskanzleramt · Kinder- und Jugendhilfe", url: "https://www.bundeskanzleramt.gv.at/agenda/familie/begleitung-beratung-hilfe/kinder-und-jugendhilfe/traeger-kinder-jugendhilfe.html")
    static let youthProtection = DirectorySource(name: "Bundeskanzleramt · Mitteilungspflichten", url: "https://www.bundeskanzleramt.gv.at/agenda/familie/begleitung-beratung-hilfe/kinder-und-jugendhilfe/mitteilungspflichten.html")
    static let familyCourt = DirectorySource(name: "Justiz · Familiengerichtshilfe", url: "https://www.justiz.gv.at/service/familienrecht/obsorge-und-kontaktrecht/familiengerichtshilfe.fed.de.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "childcare": childcareGuide
        case "parenting": parenting
        case "family-services": familyServices
        default: nil
        }
    }
}
