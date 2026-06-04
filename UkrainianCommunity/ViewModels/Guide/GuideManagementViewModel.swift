import Combine
import Foundation

@MainActor
final class GuideManagementViewModel: ObservableObject {
    @Published private(set) var sections: [GuideManagementSection] = GuideManagementSection.defaultSections
}

struct GuideManagementSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String

    static let defaultSections: [GuideManagementSection] = [
        GuideManagementSection(
            id: "treeManagement",
            title: GuideAuthoringPresentation.localized(uk: "Розділи", de: "Abschnitte", en: "Tree Management"),
            subtitle: GuideAuthoringPresentation.localized(uk: "Перегляд структури довідника, розділів та їх розміщення.", de: "Struktur des Leitfadens, Abschnitte und Platzierung durchsuchen.", en: "Browse the node hierarchy and ordering model."),
            systemImage: "point.3.connected.trianglepath.dotted"
        ),
        GuideManagementSection(
            id: "reviewHealth",
            title: GuideAuthoringPresentation.localized(uk: "Перевірка актуальності", de: "Aktualitätsprüfung", en: "Review / Health"),
            subtitle: GuideAuthoringPresentation.localized(uk: "Матеріали, які скоро потребуватимуть перевірки або вже прострочені.", de: "Artikel, die bald geprüft werden müssen oder bereits überfällig sind.", en: "Materials that are due soon for review or already overdue."),
            systemImage: "checklist.checked"
        ),
        GuideManagementSection(
            id: "reportsSuggestions",
            title: GuideAuthoringPresentation.localized(uk: "Повідомлення та пропозиції", de: "Meldungen und Vorschläge", en: "Reports / Suggestions"),
            subtitle: GuideAuthoringPresentation.localized(uk: "Звернення користувачів щодо помилок і покращень у матеріалах довідника.", de: "Rückmeldungen der Nutzerinnen und Nutzer zu Fehlern und Verbesserungsvorschlägen im Leitfaden.", en: "Reader-submitted issue reports and improvement suggestions."),
            systemImage: "bubble.left.and.exclamationmark.bubble.right"
        )
    ]
}
