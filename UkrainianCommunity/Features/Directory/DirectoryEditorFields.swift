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
            .scrollDismissesKeyboard(.interactively)
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
    let field: DirectoryEditorField
    @Binding var text: DirectoryText
    var multiline = false
    var required = true

    var body: some View {
        Section(field.title) {
            ForEach([AppLanguage.ukrainian, .german], id: \.self) { language in
                Text(language.title).font(.caption).foregroundStyle(AppTheme.textSecondary)
                DirectoryEditorTextInput(field: field, text: $text.localized(language), language: language,
                                         multiline: multiline, required: required)
            }
        }
    }
}
