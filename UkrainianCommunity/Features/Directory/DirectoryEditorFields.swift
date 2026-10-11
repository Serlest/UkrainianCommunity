import SwiftUI

enum DirectoryEditorText {
    static func value(_ ukrainian: String, _ german: String) -> String {
        DirectoryText(ukrainian: ukrainian, german: german).value(for: AppLanguage.stored)
    }
}

private struct DirectoryEditorAccessModifier: ViewModifier {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppBackgroundView())
            .tint(AppTheme.accentPrimaryForeground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .overlay {
                if !contentStore.canEdit {
                    ContentUnavailableView(
                        DirectoryText(ukrainian: "Доступ до редагування закрито",
                                      german: "Bearbeitungszugriff entzogen")
                            .value(for: AppLanguage(rawValue: languageCode) ?? .german),
                        systemImage: "lock.shield"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppBackgroundView())
                }
            }
    }
}

extension View {
    func directoryEditorChrome() -> some View {
        modifier(DirectoryEditorAccessModifier())
    }
}

struct DirectoryBilingualFields: View {
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    let title: String
    @Binding var text: DirectoryText
    var multiline = false

    var body: some View {
        Section(title) {
            if multiline {
                Text(DirectoryEditorText.value("Українською", "Ukrainisch"))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: field(\.ukrainian))
                    .frame(minHeight: 100)
                Text(DirectoryEditorText.value("Німецькою", "Deutsch"))
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: field(\.german))
                    .frame(minHeight: 100)
            } else {
                TextField(DirectoryEditorText.value("Українською", "Ukrainisch"), text: field(\.ukrainian))
                TextField(DirectoryEditorText.value("Німецькою", "Deutsch"), text: field(\.german))
            }
        }
    }

    private func field(_ keyPath: KeyPath<DirectoryText, String>) -> Binding<String> {
        Binding(
            get: { text[keyPath: keyPath] },
            set: { value in
                text = DirectoryText(
                    ukrainian: keyPath == \DirectoryText.ukrainian ? value : text.ukrainian,
                    german: keyPath == \DirectoryText.german ? value : text.german
                )
            }
        )
    }
}
