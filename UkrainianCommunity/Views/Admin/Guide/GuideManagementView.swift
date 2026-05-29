import SwiftUI

struct GuideManagementView: View {
    @EnvironmentObject private var authState: AuthState
    let guideRepository: GuideRepository

    private let items: [GuideManagementItem] = [
        .createMaterial,
        .drafts,
        .inReview,
        .approved,
        .published
    ]
    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
        GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
    ]

    var body: some View {
        DetailPageContainer {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.GuideManagement.title,
                    subtitle: AppStrings.GuideManagement.subtitle
                )
            }

            LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(items) { item in
                    if item == .createMaterial {
                        NavigationLink {
                            GuideEditorView(viewModel: GuideEditorViewModel(
                                repository: guideRepository,
                                currentUserId: authState.user?.id
                            ))
                        } label: {
                            GuideManagementPlaceholderCard(item: item)
                        }
                        .buttonStyle(.plain)
                    } else if item == .drafts {
                        NavigationLink {
                            GuideDraftListView(
                                repository: guideRepository,
                                currentUserId: authState.user?.id
                            )
                        } label: {
                            GuideManagementPlaceholderCard(item: item)
                        }
                        .buttonStyle(.plain)
                    } else if item == .inReview {
                        NavigationLink {
                            GuideInReviewListView(repository: guideRepository)
                        } label: {
                            GuideManagementPlaceholderCard(item: item)
                        }
                        .buttonStyle(.plain)
                    } else if item == .approved {
                        NavigationLink {
                            GuideApprovedListView(repository: guideRepository)
                        } label: {
                            GuideManagementPlaceholderCard(item: item)
                        }
                        .buttonStyle(.plain)
                    } else if item == .published {
                        NavigationLink {
                            GuidePublishedListView(repository: guideRepository)
                        } label: {
                            GuideManagementPlaceholderCard(item: item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GuideManagementPlaceholderCard(item: item)
                    }
                }
            }
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.GuideManagement.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum GuideManagementItem: CaseIterable, Identifiable {
    case createMaterial
    case drafts
    case inReview
    case approved
    case published
    case needsReview
    case errorReports
    case subcategories
    case archive

    var id: String { title }

    var title: String {
        switch self {
        case .createMaterial:
            AppStrings.GuideManagement.createMaterial
        case .drafts:
            AppStrings.GuideManagement.drafts
        case .inReview:
            AppStrings.GuideManagement.inReview
        case .approved:
            AppStrings.GuideManagement.approved
        case .published:
            AppStrings.GuideManagement.published
        case .needsReview:
            AppStrings.GuideManagement.needsReview
        case .errorReports:
            AppStrings.GuideManagement.errorReports
        case .subcategories:
            AppStrings.GuideManagement.subcategories
        case .archive:
            AppStrings.GuideManagement.archive
        }
    }

    var subtitle: String {
        switch self {
        case .createMaterial:
            AppStrings.GuideManagement.createMaterialSubtitle
        case .drafts:
            AppStrings.GuideManagement.draftsSubtitle
        case .inReview:
            AppStrings.GuideManagement.inReviewSubtitle
        case .approved:
            AppStrings.GuideManagement.approvedSubtitle
        case .published:
            AppStrings.GuideManagement.publishedSubtitle
        case .needsReview:
            AppStrings.GuideManagement.needsReviewSubtitle
        case .errorReports:
            AppStrings.GuideManagement.errorReportsSubtitle
        case .subcategories:
            AppStrings.GuideManagement.subcategoriesSubtitle
        case .archive:
            AppStrings.GuideManagement.archiveSubtitle
        }
    }

    var systemImage: String {
        switch self {
        case .createMaterial:
            "square.and.pencil"
        case .drafts:
            "doc.text"
        case .inReview:
            "clock.badge.exclamationmark"
        case .approved:
            "checkmark.seal"
        case .published:
            "checkmark.seal.fill"
        case .needsReview:
            "exclamationmark.circle"
        case .errorReports:
            "exclamationmark.bubble"
        case .subcategories:
            "rectangle.3.group"
        case .archive:
            "archivebox"
        }
    }
}

private struct GuideManagementPlaceholderCard: View {
    let item: GuideManagementItem

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: item.systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.badgeBlueFill, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}
