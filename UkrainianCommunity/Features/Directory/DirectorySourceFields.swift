import SwiftUI

struct DirectorySourceFields: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Environment(\.directoryShowsValidation) private var showsValidation
    @Binding var source: DirectoryManagedSource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(DirectoryEditorText.value("Назва джерела", "Name der Quelle"),
                      text: $source.name)
                .accessibilityIdentifier("directory.source.name")
            feedback(source.name, limit: DirectorySourceValidation.nameLimit, issue: DirectorySourceValidation.nameIssue(source.name))
            TextField("https://", text: $source.url)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("directory.source.url")
            feedback(source.url, limit: DirectorySourceValidation.urlLimit, issue: DirectorySourceValidation.urlIssue(source.url))
            if let link = source.displaySource {
                Link(destination: link.url) {
                    Label(DirectoryEditorText.value("Відкрити джерело", "Quelle öffnen"),
                          systemImage: "arrow.up.right.square")
                        .font(.subheadline)
                }
            }
            Text(DirectoryEditorText.value(
                "Перед публікацією перевірте, що сторінка відкривається і підтверджує написане. Система перевіряє лише формат посилання.",
                "Prüfen Sie vor der Veröffentlichung, ob die Seite erreichbar ist und den Text belegt. Das System prüft nur das Linkformat."
            ))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func feedback(_ value: String, limit: Int, issue: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value.utf16.count) / \(limit)")
                .foregroundStyle(value.utf16.count > limit ? Color.red : AppTheme.textSecondary)
            if let issue, showsValidation || !value.isEmpty {
                Text(issue).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
    }
}
