import SwiftUI

struct DirectorySyncNoticeView: View {
    @EnvironmentObject private var contentStore: DirectoryContentStore
    let language: AppLanguage

    var body: some View {
        if let message {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.value(for: language))
                        .font(.subheadline)
                    if contentStore.syncState == .failed || contentStore.syncState == .invalidContent {
                        Button {
                            contentStore.retryObserving()
                        } label: {
                            Text(DirectoryText(ukrainian: "Спробувати знову", german: "Erneut versuchen")
                                .value(for: language))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appGlassCard(material: .regularMaterial)
            .accessibilityIdentifier("directory.syncNotice")
        }
    }

    private var message: DirectoryText? {
        switch contentStore.syncState {
        case .loading, .current:
            return nil
        case .cached:
            return DirectoryText(
                ukrainian: "Показано збережені дані. Оновлення довідника ще не підтверджені сервером.",
                german: "Gespeicherte Daten werden angezeigt. Aktualisierungen des Ratgebers sind noch nicht vom Server bestätigt."
            )
        case .failed:
            return DirectoryText(
                ukrainian: "Не вдалося завантажити оновлення. Показано вбудовані або збережені дані.",
                german: "Aktualisierungen konnten nicht geladen werden. Integrierte oder gespeicherte Daten werden angezeigt."
            )
        case .invalidContent:
            return DirectoryText(
                ukrainian: "Частину оновлень не вдалося прочитати. Показано доступні дані.",
                german: "Einige Aktualisierungen konnten nicht gelesen werden. Verfügbare Daten werden angezeigt."
            )
        }
    }
}
