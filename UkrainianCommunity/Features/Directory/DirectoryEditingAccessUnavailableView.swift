import SwiftUI

/// Also used when a live permission update replaces an already-open editor.
/// A restricted route must explain the transition instead of rendering empty.
struct DirectoryEditingAccessUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label(DirectoryEditorText.value("Редагування недоступне", "Bearbeitung nicht verfügbar"),
                  systemImage: "lock.shield")
                .foregroundStyle(AppTheme.textPrimary)
        } description: {
            Text(DirectoryEditorText.value(
                "Ваш доступ до редагування змінився. Неопубліковані зміни не збережено. Довідник залишається доступним для читання.",
                "Ihr Bearbeitungszugriff hat sich geändert. Unveröffentlichte Änderungen wurden nicht gespeichert. Sie können den Ratgeber weiterhin lesen."
            ))
            .foregroundStyle(AppTheme.textSecondary)
        } actions: {
            Button { dismiss() } label: {
                Text(DirectoryEditorText.value("Назад", "Zurück"))
                    .frame(minWidth: 88, minHeight: 44)
            }
                .buttonStyle(.plain)
                .appGlassActionSurface(.prominent)
                .accessibilityIdentifier("directory.accessUnavailable.back")
        }
        .background(AppBackgroundView())
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }
}
