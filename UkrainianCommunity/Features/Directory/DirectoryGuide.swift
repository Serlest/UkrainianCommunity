import Foundation

struct DirectoryGuideSection: Identifiable {
    let id: String
    let symbol: String
    let title: DirectoryText
    let body: DirectoryText
    let phoneNumber: String?

    init(_ id: String, _ symbol: String, _ titleUK: String, _ titleDE: String,
         _ bodyUK: String, _ bodyDE: String, phoneNumber: String? = nil) {
        self.id = id
        self.symbol = symbol
        title = DirectoryText(ukrainian: titleUK, german: titleDE)
        body = DirectoryText(ukrainian: bodyUK, german: bodyDE)
        self.phoneNumber = phoneNumber
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

    static func guide(categoryID: String, topicID: String) -> DirectoryGuide? {
        switch categoryID {
        case "first-steps": FirstStepsGuides.guide(for: topicID)
        case "registration": RegistrationGuides.guide(for: topicID)
        default: nil
        }
    }
}
