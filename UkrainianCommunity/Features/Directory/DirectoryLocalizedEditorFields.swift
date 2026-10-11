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
    let title: String
    @Binding var text: DirectoryText
    let language: AppLanguage
    var multiline = false

    var body: some View {
        Section("\(title) · \(language == .ukrainian ? "Українська" : "Deutsch")") {
            if multiline {
                TextEditor(text: value)
                    .frame(minHeight: 100)
                    .accessibilityLabel(title)
            } else {
                TextField(title, text: value)
            }
        }
    }

    private var value: Binding<String> {
        Binding(
            get: { text.value(for: language) },
            set: { newValue in
                text = .init(
                    ukrainian: language == .ukrainian ? newValue : text.ukrainian,
                    german: language == .german ? newValue : text.german
                )
            }
        )
    }
}
