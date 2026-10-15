import Foundation

enum DirectoryEditorField: String {
    case categoryTitle, categorySummary, groupTitle, articleTitle, articleSummary
    case sectionTitle, sectionBody, contactTitle, contactDetail

    var title: String {
        switch self {
        case .categoryTitle: DirectoryEditorText.value("Назва категорії", "Name des Bereichs")
        case .categorySummary: DirectoryEditorText.value("Короткий опис категорії", "Kurzbeschreibung des Bereichs")
        case .groupTitle: DirectoryEditorText.value("Назва підкатегорії", "Name des Unterbereichs")
        case .articleTitle: DirectoryEditorText.value("Назва статті", "Beitragstitel")
        case .articleSummary: DirectoryEditorText.value("Короткий вступ", "Kurze Einleitung")
        case .sectionTitle: DirectoryEditorText.value("Заголовок інформації", "Überschrift der Information")
        case .sectionBody: DirectoryEditorText.value("Інформація", "Information")
        case .contactTitle: DirectoryEditorText.value("Назва контакту", "Kontaktname")
        case .contactDetail: DirectoryEditorText.value("Пояснення контакту", "Kontakthinweis")
        }
    }

    var limit: Int {
        switch self {
        case .categoryTitle, .groupTitle, .contactTitle: 100
        case .categorySummary: 500
        case .articleTitle: 140
        case .articleSummary: 800
        case .sectionTitle: 160
        case .sectionBody: 6000
        case .contactDetail: 200
        }
    }

    func issue(for value: String, language: AppLanguage, required: Bool = true) -> String? {
        let label = "\(title) · \(language.title)"
        if required && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DirectoryEditorText.value("\(label): заповніть це поле.", "\(label): Bitte ausfüllen.")
        }
        if value.utf16.count > limit {
            return DirectoryEditorText.value(
                "\(label): \(value.utf16.count) із \(limit) символів. Скоротіть текст.",
                "\(label): \(value.utf16.count) von \(limit) Zeichen. Bitte kürzen."
            )
        }
        return nil
    }
}
