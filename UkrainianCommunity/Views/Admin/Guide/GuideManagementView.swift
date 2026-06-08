import SwiftUI

struct GuideManagementView: View {
    @StateObject private var viewModel = GuideManagementViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        AdminScreenShell(
            title: GuideAuthoringPresentation.treeManagementTitle,
            subtitle: GuideAuthoringPresentation.localized(
                uk: "Робоча поверхня для керування структурою довідника.",
                de: "Arbeitsbereich für die Verwaltung der Leitfadenstruktur.",
                en: "Workspace for the guide management flow."
            ),
            tabBarHidden: false
        ) {
            LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(viewModel.sections) { section in
                    if section.id == "treeManagement" {
                        NavigationLink {
                            GuideTreeManagementView()
                        } label: {
                            GuideManagementSectionCard(section: section)
                        }
                        .buttonStyle(.plain)
                    } else if section.id == "reviewHealth" {
                        NavigationLink {
                            GuideReviewHealthManagementView()
                        } label: {
                            GuideManagementSectionCard(section: section)
                        }
                        .buttonStyle(.plain)
                    } else if section.id == "reportsSuggestions" {
                        NavigationLink {
                            GuideReportsManagementView()
                        } label: {
                            GuideManagementSectionCard(section: section)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GuideManagementSectionCard(section: section)
                    }
                }
            }

            AppEditorSectionCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(GuideAuthoringPresentation.localized(uk: "Поточний етап", de: "Aktueller Stand", en: "Current scope"))
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(GuideAuthoringPresentation.localized(
                        uk: "Керуйте структурою довідника, перевіркою актуальності та зверненнями користувачів з одного робочого простору.",
                        de: "Verwalten Sie Struktur, Aktualitätsprüfung und Rückmeldungen der Nutzerinnen und Nutzer in einem Arbeitsbereich.",
                        en: "Manage guide structure, review status, and reader feedback from one workspace."
                    ))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct GuideManagementSectionCard: View {
    let section: GuideManagementSection

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: section.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(iconTint)
                        .frame(width: 32, height: 32)
                        .background(iconBackground, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

                    Spacer(minLength: 8)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(section.subtitle)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconTint: Color {
        AppTheme.accentPrimary
    }

    private var iconBackground: Color {
        AppTheme.badgeBlueFill
    }
}

#Preview {
    NavigationStack {
        GuideManagementView()
    }
}
