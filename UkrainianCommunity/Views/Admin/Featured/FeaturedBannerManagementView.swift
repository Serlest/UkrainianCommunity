import SwiftUI

struct FeaturedBannerManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: FeaturedBannerManagementViewModel
    @State private var deleteCandidate: FeaturedBanner?
    private let repository: FeaturedBannerRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository

    init(
        repository: FeaturedBannerRepository,
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        _viewModel = StateObject(wrappedValue: FeaturedBannerManagementViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.FeaturedManagement.title,
            introSubtitle: AppStrings.FeaturedManagement.subtitle
        ) {
            managementContent
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .confirmationDialog(
            AppStrings.FeaturedManagement.deleteConfirmationTitle,
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.FeaturedManagement.deleteBanner, role: .destructive) {
                guard let banner = deleteCandidate else { return }
                deleteCandidate = nil
                Task {
                    await viewModel.delete(banner, requestedBy: authState.user?.id)
                }
            }
            Button(AppStrings.Action.cancel, role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            if let banner = deleteCandidate {
                Text(AppStrings.FeaturedManagement.deleteConfirmationMessage(managementTitle(for: banner)))
            }
        }
    }

    private var canDeleteBanners: Bool {
        PermissionService.canDeleteFeaturedBanners(user: authState.user)
    }

    @ViewBuilder
    private var managementContent: some View {
        if viewModel.isLoading && viewModel.banners.isEmpty {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if viewModel.banners.isEmpty, let error = viewModel.error {
            ErrorStateCard(
                systemImage: "sparkles.rectangle.stack",
                title: AppStrings.FeaturedManagement.title,
                message: errorText(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await viewModel.refresh() }
            }
        } else if viewModel.banners.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                EmptyStateCard(
                    systemImage: "sparkles.rectangle.stack",
                    title: AppStrings.FeaturedManagement.emptyTitle,
                    message: AppStrings.FeaturedManagement.emptyMessage
                )

                createBannerLink
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: errorText(error))
                }

                createBannerLink

                ForEach(viewModel.banners) { banner in
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        FeaturedBannerManagementRow(
                            banner: banner,
                            isUpdating: viewModel.updatingBannerIDs.contains(banner.id),
                            canDelete: canDeleteBanners,
                            onActiveChange: { isActive in
                                Task {
                                    await viewModel.setActive(isActive, for: banner, updatedBy: authState.user?.id)
                                }
                            },
                            onDelete: {
                                deleteCandidate = banner
                            }
                        )

                        NavigationLink {
                            FeaturedBannerEditorView(
                                repository: repository,
                                mode: .edit(banner),
                                newsRepository: newsRepository,
                                eventRepository: eventRepository,
                                organizationRepository: organizationRepository
                            ) {
                                await viewModel.refresh()
                            }
                        } label: {
                            ProfileModuleRow(
                                title: AppStrings.FeaturedEditor.editBanner,
                                subtitle: managementTitle(for: banner),
                                systemImage: "slider.horizontal.3",
                                status: .available
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var createBannerLink: some View {
        NavigationLink {
            FeaturedBannerEditorView(
                repository: repository,
                newsRepository: newsRepository,
                eventRepository: eventRepository,
                organizationRepository: organizationRepository
            ) {
                await viewModel.refresh()
            }
        } label: {
            ProfileModuleRow(
                title: AppStrings.FeaturedEditor.createBanner,
                subtitle: AppStrings.FeaturedEditor.createEntrySubtitle,
                systemImage: "plus.rectangle.on.rectangle",
                status: .available
            )
        }
        .buttonStyle(.plain)
    }

    private func errorText(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.FeaturedManagement.networkError
        case .permissionDenied:
            return AppStrings.FeaturedManagement.permissionError
        case .validationFailed:
            return AppStrings.FeaturedManagement.validationError
        case .notFound:
            return AppStrings.FeaturedManagement.notFoundError
        case .unknown:
            return AppStrings.FeaturedManagement.unknownError
        }
    }

    private func managementTitle(for banner: FeaturedBanner) -> String {
        if let internalName = nonEmpty(banner.internalName) {
            return internalName
        }
        if let title = nonEmpty(banner.title) {
            return title
        }
        return AppStrings.FeaturedManagement.fallbackBannerName(banner.id, date: banner.createdAt)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FeaturedBannerManagementRow: View {
    let banner: FeaturedBanner
    let isUpdating: Bool
    let canDelete: Bool
    let onActiveChange: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(managementTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let publicHeadline = publicHeadlineText {
                            Text(publicHeadline)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 12)

                    statusBadge
                }

                metadataGrid

                Toggle(isOn: Binding(
                    get: { banner.isActive },
                    set: { onActiveChange($0) }
                )) {
                    Text(AppStrings.FeaturedManagement.activeToggle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .disabled(isUpdating)

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label(AppStrings.FeaturedManagement.deleteBanner, systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(isUpdating)
                }

                if isUpdating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(AppStrings.FeaturedManagement.updating)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var statusBadge: some View {
        Text(banner.isActive ? AppStrings.Common.active : AppStrings.FeaturedManagement.inactive)
            .font(.caption.weight(.semibold))
            .foregroundStyle(banner.isActive ? AppTheme.accentPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((banner.isActive ? AppTheme.accentPrimary : AppTheme.textSecondary).opacity(0.10), in: Capsule())
            .lineLimit(1)
    }

    private var metadataGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.sectionsLabel, value: visibleSectionsText, systemImage: "rectangle.grid.2x2")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.regionLabel, value: regionText, systemImage: "globe.europe.africa")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.actionLabel, value: actionText, systemImage: "arrow.up.forward.app")
            FeaturedBannerMetadataLine(title: AppStrings.FeaturedManagement.priorityLabel, value: "\(banner.priority)", systemImage: "list.number")
        }
    }

    private var visibleSectionsText: String {
        banner.visibleSections
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.managementTitle)
            .joined(separator: ", ")
    }

    private var regionText: String {
        switch banner.regionScope {
        case .allAustria:
            return AppStrings.Home.regionAllAustria
        case .federalState:
            guard let federalState = banner.federalState else { return AppStrings.FeaturedManagement.missingRegion }
            return AppStrings.FederalStates.title(for: federalState)
        }
    }

    private var actionText: String {
        banner.actionType.managementTitle
    }

    private var managementTitle: String {
        if let internalName = nonEmpty(banner.internalName) {
            return internalName
        }
        if let title = nonEmpty(banner.title) {
            return title
        }
        return AppStrings.FeaturedManagement.fallbackBannerName(banner.id, date: banner.createdAt)
    }

    private var publicHeadlineText: String? {
        let title = nonEmpty(banner.title)
        let subtitle = nonEmpty(banner.subtitle)

        if nonEmpty(banner.internalName) != nil {
            return title ?? subtitle
        }
        return subtitle
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct FeaturedBannerMetadataLine: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            Text("\(title): \(value)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
    }
}

private extension FeaturedBannerVisibleSection {
    var managementTitle: String {
        switch self {
        case .home:
            return AppStrings.Tabs.home
        case .events:
            return AppStrings.Tabs.events
        case .organizations:
            return AppStrings.Tabs.organizations
        case .guide:
            return AppStrings.Guide.title
        }
    }
}

private extension FeaturedBannerActionType {
    var managementTitle: String {
        switch self {
        case .none:
            return AppStrings.FeaturedManagement.actionNone
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        case .guide:
            return AppStrings.Guide.title
        case .externalURL:
            return AppStrings.FeaturedManagement.actionExternalURL
        }
    }
}

#Preview {
    NavigationStack {
        FeaturedBannerManagementView(
            repository: MockFeaturedBannerRepository(),
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository()
        )
            .environmentObject(AuthState())
    }
}
