import Foundation

struct DirectoryGuideSection: Identifiable {
    let id: String
    let symbol: String
    let title: DirectoryText
    let body: DirectoryText
    let phoneNumber: String?
    let source: DirectorySource?

    init(_ id: String, _ symbol: String, _ titleUK: String, _ titleDE: String,
         _ bodyUK: String, _ bodyDE: String, phoneNumber: String? = nil,
         source: DirectorySource? = nil) {
        self.id = id
        self.symbol = symbol
        title = DirectoryText(ukrainian: titleUK, german: titleDE)
        body = DirectoryText(ukrainian: bodyUK, german: bodyDE)
        self.phoneNumber = phoneNumber
        self.source = source
    }
}

struct DirectoryGuide {
    let cardSummary: DirectoryText
    let introduction: DirectoryText
    let sections: [DirectoryGuideSection]
    let sources: [DirectorySource]
}

enum DirectoryGuideCatalog {
    static let checkedOn = "07.10.2026"

    static func checkedOn(for categoryID: String) -> String {
        ["first-steps", "registration", "housing", "health", "mental-health", "insurance", "work", "qualifications", "education", "family", "transport", "finances", "social-support", "legal", "communication", "digital", "community", "leisure", "accessibility", "care", "seniors"].contains(categoryID) ? "10.10.2026" : checkedOn
    }

    static func guide(categoryID: String, topicID: String) -> DirectoryGuide? {
        switch categoryID {
        case "first-steps": FirstStepsGuides.guide(for: topicID)
        case "registration": RegistrationGuides.guide(for: topicID)
        case "residence": ResidenceGuides.guide(for: topicID)
        case "documents": DocumentGuides.guide(for: topicID)
        case "citizenship": CitizenshipGuides.guide(for: topicID)
        case "housing": HousingGuides.guide(for: topicID)
        case "health": HealthGuides.guide(for: topicID)
        case "mental-health": MentalHealthGuides.guide(for: topicID)
        case "insurance": InsuranceGuides.guide(for: topicID)
        case "work": WorkGuides.guide(for: topicID)
        case "qualifications": QualificationGuides.guide(for: topicID)
        case "education": EducationGuides.guide(for: topicID)
        case "family": FamilyGuides.guide(for: topicID)
        case "transport": TransportGuides.guide(for: topicID)
        case "finances": FinanceGuides.guide(for: topicID)
        case "social-support": SocialSupportGuides.guide(for: topicID)
        case "legal": LegalGuides.guide(for: topicID)
        case "communication": CommunicationGuides.guide(for: topicID)
        case "digital": DigitalGuides.guide(for: topicID)
        case "community": CommunityGuides.guide(for: topicID)
        case "leisure": LeisureGuides.guide(for: topicID)
        case "accessibility": AccessibilityGuides.guide(for: topicID)
        case "care": CareGuides.guide(for: topicID)
        case "seniors": SeniorsGuides.guide(for: topicID)
        default: nil
        }
    }
}
