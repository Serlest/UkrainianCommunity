import SwiftUI

struct GuideReportsManagementView: View {
    @StateObject private var viewModel: GuideReportsManagementViewModel

    init(repository: FeedbackRepository = FirestoreFeedbackRepository()) {
        _viewModel = StateObject(wrappedValue: GuideReportsManagementViewModel(repository: repository))
    }

    var body: some View {
        AdminScreenShell(
            title: screenTitle,
            subtitle: screenSubtitle,
            tabBarHidden: false
        ) {
            content
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var screenTitle: String {
        GuideAuthoringPresentation.localized(
            uk: "Повідомлення та пропозиції",
            de: "Meldungen und Vorschläge",
            en: "Reports / Suggestions"
        )
    }

    private var screenSubtitle: String {
        GuideAuthoringPresentation.localized(
            uk: "Звернення користувачів щодо помилок і покращень у матеріалах довідника.",
            de: "Rückmeldungen der Nutzerinnen und Nutzer zu Fehlern und Verbesserungsvorschlägen im Leitfaden.",
            en: "Reader-submitted issue reports and improvement suggestions."
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingStateCard(
                title: GuideAuthoringPresentation.localized(
                    uk: "Повідомлення",
                    de: "Meldungen",
                    en: "Reports"
                )
            )
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: GuideAuthoringPresentation.localized(
                    uk: "Не вдалося завантажити повідомлення",
                    de: "Meldungen konnten nicht geladen werden",
                    en: "Unable to load reports"
                ),
                message: errorMessage(for: error)
            ) {
                PrimaryActionButton(
                    title: GuideAuthoringPresentation.localized(
                        uk: "Спробувати ще раз",
                        de: "Erneut versuchen",
                        en: "Try again"
                    ),
                    systemImage: "arrow.clockwise"
                ) {
                    Task { await viewModel.refresh() }
                }
            }
        } else if viewModel.items.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "bubble.left.and.bubble.right",
                title: GuideAuthoringPresentation.localized(
                    uk: "Поки що немає звернень",
                    de: "Noch keine Meldungen",
                    en: "No reports yet"
                ),
                message: GuideAuthoringPresentation.localized(
                    uk: "Коли користувачі повідомлять про помилку або запропонують зміну в довіднику, вони з’являться тут.",
                    de: "Wenn Nutzerinnen und Nutzer Fehler melden oder Änderungen am Leitfaden vorschlagen, erscheinen sie hier.",
                    en: "Guide feedback from readers will appear here."
                )
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(viewModel.items) { item in
                    GuideFeedbackRow(item: item)
                }
            }
        }
    }

    private func errorMessage(for error: AppError) -> String {
        switch error {
        case .permissionDenied:
            return GuideAuthoringPresentation.localized(
                uk: "У вас немає доступу до цих звернень.",
                de: "Sie haben keinen Zugriff auf diese Meldungen.",
                en: "You do not have access to these reports."
            )
        case .network:
            return GuideAuthoringPresentation.localized(
                uk: "Перевірте з’єднання та спробуйте ще раз.",
                de: "Prüfen Sie die Verbindung und versuchen Sie es erneut.",
                en: "Check your connection and try again."
            )
        case .validationFailed, .notFound, .unknown:
            return GuideAuthoringPresentation.localized(
                uk: "Не вдалося завантажити звернення. Спробуйте ще раз пізніше.",
                de: "Die Meldungen konnten nicht geladen werden. Bitte versuchen Sie es später erneut.",
                en: "Unable to load reports. Please try again later."
            )
        }
    }
}

private struct GuideFeedbackRow: View {
    let item: GuideFeedbackEntry

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.type == .bug ? "exclamationmark.bubble" : "lightbulb")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(typeTitle)
                                .font(AppTheme.cardTitleFont)
                                .foregroundStyle(AppTheme.textPrimary)

                            Spacer(minLength: 0)

                            Text(item.status.title)
                                .font(AppTheme.metadataFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        if let materialTitle = item.materialTitle, !materialTitle.isEmpty {
                            Text(materialTitle)
                                .font(AppTheme.buttonLabelFont)
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let materialID = item.materialID, !materialID.isEmpty {
                            Text(materialID)
                                .font(AppTheme.metadataFont.monospaced())
                                .foregroundStyle(AppTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Text(item.message)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(item.userID.isEmpty ? GuideAuthoringPresentation.localized(uk: "Невідомий користувач", de: "Unbekannter Nutzer", en: "Unknown user") : item.userID, systemImage: "person")
                        .lineLimit(1)
                    Text("•")
                    Text(LocalizationStore.dateString(from: item.createdAt, dateStyle: .short, timeStyle: .short))
                        .lineLimit(1)
                }
                .font(AppTheme.metadataFont)
                .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var typeTitle: String {
        switch item.type {
        case .bug, .report:
            return GuideAuthoringPresentation.localized(
                uk: "Повідомлення про помилку",
                de: "Fehlermeldung",
                en: "Error report"
            )
        case .suggestion:
            return GuideAuthoringPresentation.localized(
                uk: "Пропозиція зміни",
                de: "Änderungsvorschlag",
                en: "Suggestion"
            )
        case .question:
            return item.type.title
        }
    }
}

#Preview {
    NavigationStack {
        GuideReportsManagementView(repository: MockFeedbackRepository())
    }
}
