import Foundation

enum SocialSupportGuides {
    static let social = DirectorySource(name: "oesterreich.gv.at · Sozialhilfe nach Bundesland", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/4/Seite.1693914")
    static let foreignEligibility = DirectorySource(name: "oesterreich.gv.at · Sozialhilfe für ausländische Staatsbürger", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/4/Seite.1693906")
    static let familyPayment = DirectorySource(name: "oesterreich.gv.at · Familienbeihilfe beantragen", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familienbeihilfe/Seite.450233")
    static let childPayment = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsgeld", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/finanzielle-unterstuetzungen/3/2/2")
    static let ukraine = DirectorySource(name: "BBU · Ukraine FAQ und Grundversorgung", url: "https://www.bbu.gv.at/ukraine-info-faq-ukrainian")
    static let familyLaw = DirectorySource(name: "Parlament · Familienleistungen Beschluss 8.10.2026", url: "https://www.parlament.gv.at/gegenstand/XXVIII/BNR/209")
    static let familyStatus = DirectorySource(name: "oesterreich.gv.at · Gesetzliche Neuerung", url: "https://www.oesterreich.gv.at/de/Gesetzliche-Neuerungen/Beschluss-des-Nationalrates/flag-ua")
    static let debt = DirectorySource(name: "Staatlich anerkannte Schuldenberatung · Standorte", url: "https://schuldenberatung.at/beratungsstellen/")
    static let homelessness = DirectorySource(name: "oesterreich.gv.at · Wohnungslosigkeit und Beratung", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/2/Seite.1694300")
    static let kbgSystems = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsgeld-Systeme", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/finanzielle-unterstuetzungen/3/2/Seite.080613")
    static let kbgApplication = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsgeld beantragen", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/finanzielle-unterstuetzungen/3/2/2/Seite.080643")
    static let aid = DirectorySource(name: "oesterreich.gv.at · Beratungsstellen in Not", url: "https://www.oesterreich.gv.at/de/themen/hilfe_und_finanzielle_unterstuetzung_erhalten/2/Seite.1694100")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "benefits": benefits
        case "family-benefits": familyBenefits
        case "basic-support": basicSupport
        case "aid-organizations": aidOrganizations
        default: nil
        }
    }
}
