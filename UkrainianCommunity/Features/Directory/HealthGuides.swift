import Foundation

/// Public Austrian health-system guidance. Insurance eligibility is handled in its own category.
enum HealthGuides {
    static let healthAdvice = SafetyContact(
        number: "1450",
        title: .init(ukrainian: "Медична консультація", german: "Gesundheitsberatung"),
        detail: .init(ukrainian: "Цілодобово: порада, куди звернутися", german: "Rund um die Uhr: passende Anlaufstelle"))
    static let hotline = DirectorySource(name: "Gesundheitsportal · 1450, 141, 144", url: "https://www.gesundheit.gv.at/service/notruf/hotline.html")
    static let onCallDoctors = DirectorySource(name: "Gesundheitsportal · Ärztenotdienst 141", url: "https://www.gesundheit.gv.at/service/notruf/aerztenotdienst.html")
    static let providerSearch = DirectorySource(name: "Gesundheitsportal · Gesundheitssuchen", url: "https://www.gesundheit.gv.at/service/gesundheitssuche.html")
    static let doctorSearch = DirectorySource(name: "Gesundheitsportal · Arztsuche nach Bundesland", url: "https://www.gesundheit.gv.at/service/gesundheitssuche/arztsuche/")
    static let ecard = DirectorySource(name: "Gesundheitsportal · e-card beim Arzt", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/arztbesuch/e-card/")
    static let doctorCosts = DirectorySource(name: "Gesundheitsportal · Kassen-, Wahl- und Privatarzt", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/arztbesuch/wahlarzt-kosten.html")
    static let referral = DirectorySource(name: "Gesundheitsportal · Facharztüberweisung", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/arztbesuch/ueberweisung-facharzt1.html")
    static let clinicSearch = DirectorySource(name: "Gesundheitsportal · Kliniksuche", url: "https://www.gesundheit.gv.at/service/gesundheitssuche/kliniksuche.html")
    static let hospitalCosts = DirectorySource(name: "Gesundheitsportal · Kosten im Spital", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/krankenhausaufenthalt/selbstbehalt-krankenhaus/")
    static let dental = DirectorySource(name: "ÖGK · Zahngesundheitszentren", url: "https://www.oegk.at/cdscontent/?contentid=10007.870136&portal=oegkportal")
    static let pharmacySearch = DirectorySource(name: "Gesundheitsportal · Apothekensuche", url: "https://www.gesundheit.gv.at/service/gesundheitssuche/apothekensuche.html")
    static let prescription = DirectorySource(name: "Gesundheitsportal · Rezept und e-Rezept", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/medikamente/rezept1.html")
    static let medicationRegister = DirectorySource(name: "BASG · Arzneimittelregister", url: "https://www.basg.gv.at/marktbeobachtung/oeffentliche-register")
    static let eMedication = DirectorySource(name: "Gesundheitsportal · eMedikation", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/elga/e-medikation.html")
    static let onlinePharmacy = DirectorySource(name: "Gesundheitsportal · Online-Apotheken", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/medikamente/online-apotheke.html")
    static let physiotherapy = DirectorySource(name: "Gesundheitsportal · Physiotherapie", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/berufe/gesundheitsberufe-a-z/medizinisch-therapeutisch-diagnostische-gesundheitsberufe/physiotherapeut.html")
    static let parentChildPass = DirectorySource(name: "Gesundheitsportal · Eltern-Kind-Pass ab Oktober 2026", url: "https://www.gesundheit.gv.at/leben/eltern/eltern-kind-pass/eltern-kind-pass-untersuchungen.html")
    static let pregnancyChecks = DirectorySource(name: "Gesundheitsportal · Untersuchungen in der Schwangerschaft", url: "https://www.gesundheit.gv.at/leben/eltern/eltern-kind-pass/untersuchungen-schwangerschaft.html")
    static let birth = DirectorySource(name: "Gesundheitsportal · Wahl des Geburtsortes", url: "https://www.gesundheit.gv.at/leben/eltern/geburt/spitalsgeburt-hausgeburt.html")
    static let viennaBirth = DirectorySource(name: "Stadt Wien · Schwangerschaft und Geburt", url: "https://www.wien.gv.at/gesundheit/geburt-schwangerschaft")
    static let midwife = DirectorySource(name: "Gesundheitsportal · Hebammen und Kosten", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/berufe/gesundheitsberufe-a-z/hebammen/hebammen.html")
    static let childChecks = DirectorySource(name: "Gesundheitsportal · Kindesuntersuchungen", url: "https://www.gesundheit.gv.at/leben/eltern/eltern-kind-pass/kindesuntersuchungen.html")
    static let childVaccines = DirectorySource(name: "Gesundheitsportal · Impfungen für Kinder", url: "https://www.gesundheit.gv.at/leben/gesundheitsvorsorge/impfungen/kinderimpfungen.html")
    static let vaccines = DirectorySource(name: "Gesundheitsportal · Impfungen und Impfplan", url: "https://www.gesundheit.gv.at/leben/gesundheitsvorsorge/impfungen.html")
    static let screening = DirectorySource(name: "Gesundheitsportal · Vorsorgeuntersuchung", url: "https://www.gesundheit.gv.at/leben/gesundheitsvorsorge/vorsorgeuntersuchung/was-wird-gemacht.html")
    static let patientRights = DirectorySource(name: "Gesundheitsportal · Patientenrechte", url: "https://www.gesundheit.gv.at/gesundheitsleistungen/arztbesuch/patientenrechte.html")
    static let patientAdvocacy = DirectorySource(name: "Gesundheitsportal · Patientenanwaltschaften", url: "https://www.gesundheit.gv.at/service/beratungsstellen/gesundheitssystem/patientenrechte/patientenanwaltschaft.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "where-to-go": whereToGo
        case "doctors": doctors
        case "specialists": specialists
        case "clinics": clinics
        case "dental": dentalCare
        case "medication": medicines
        case "ongoing-care": ongoingCare
        case "pregnancy": pregnancy
        case "child-health": childHealth
        case "prevention": prevention
        case "patient-rights": rights
        default: nil
        }
    }
}
