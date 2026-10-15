import SwiftUI

struct DirectoryEditingLanguagePicker: View {
    @Binding var language: AppLanguage

    var body: some View {
        Section {
            Picker(DirectoryEditorText.value("Мова тексту", "Textsprache"), selection: $language) {
                Text(AppLanguage.ukrainian.title).tag(AppLanguage.ukrainian)
                Text(AppLanguage.german.title).tag(AppLanguage.german)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("directory.editor.language")
        } footer: {
            Text(DirectoryEditorText.value(
                "Заповніть обидві мови перед публікацією.",
                "Füllen Sie vor der Veröffentlichung beide Sprachen aus."
            ))
        }
    }
}

struct DirectoryLocalizedEditorField: View {
    let field: DirectoryEditorField
    @Binding var text: DirectoryText
    let language: AppLanguage
    var multiline = false
    var required = true

    var body: some View {
        Section("\(field.title) · \(language.title)") {
            DirectoryEditorTextInput(field: field, text: $text.localized(language),
                                     language: language, multiline: multiline, required: required)
        }
    }
}

private struct DirectoryValidationEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var directoryShowsValidation: Bool {
        get { self[DirectoryValidationEnvironmentKey.self] }
        set { self[DirectoryValidationEnvironmentKey.self] = newValue }
    }
}

struct DirectoryEditorTextInput: View {
    @Environment(\.directoryShowsValidation) private var showsValidation
    let field: DirectoryEditorField
    @Binding var text: String
    let language: AppLanguage
    var multiline = false
    var required = true

    private var issue: String? {
        guard showsValidation || !text.isEmpty else { return nil }
        return field.issue(for: text, language: language, required: required)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if multiline {
                    TextEditor(text: $text).frame(minHeight: 100)
                } else {
                    TextField(field.title, text: $text)
                }
            }
            .font(.body)
            .accessibilityLabel(field.title)
            .accessibilityIdentifier("directory.field.\(field.rawValue).\(language.rawValue)")
            HStack {
                Text(required ? DirectoryEditorText.value("Обов’язково", "Pflichtfeld")
                              : DirectoryEditorText.value("Необов’язково", "Optional"))
                Spacer()
                Text("\(text.utf16.count)/\(field.limit)")
            }
            .font(.caption)
            .foregroundStyle(issue == nil ? AppTheme.textSecondary : AppTheme.accentDestructiveForeground)
            if let issue {
                Text(issue).font(.caption).foregroundStyle(AppTheme.accentDestructiveForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("directory.field.\(field.rawValue).\(language.rawValue).error")
            }
        }
    }
}
