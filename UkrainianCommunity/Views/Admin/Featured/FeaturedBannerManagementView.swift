import SwiftUI

struct FeaturedBannerManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: FeaturedBannerManagementViewModel
    @State private var deleteCandidate: FeaturedBanner?
    @State private var searchText = ""
    @State private var filter: FeaturedBannerManagementFilter = .all
    private let repository: FeaturedBannerRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository

    init(
        repository: FeaturedBannerRepository,
        publicCache: FeaturedBannerCache? = nil,
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        _viewModel = StateObject(wrappedValue: FeaturedBannerManagementViewModel(
            repository: repository,
            publicCache: publicCache
        ))
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
        .appRefreshable {
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
            LazyVStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: errorText(error))
                }

                createBannerLink

                FeaturedBannerManagementControls(
                    searchText: $searchText,
                    filter: $filter,
                    visibleCount: visibleBanners.count,
                    totalCount: viewModel.banners.count
                )

                if visibleBanners.isEmpty {
                    EmptyStateCard(
                        systemImage: "magnifyingglass",
                        title: AppStrings.FeaturedManagement.noMatchesTitle,
                        message: AppStrings.FeaturedManagement.noMatchesMessage
                    )
                }

                ForEach(visibleBanners) { banner in
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
                        },
                        duplicateDestination: {
                            FeaturedBannerEditorView(
                                repository: repository,
                                mode: .duplicate(banner),
                                newsRepository: newsRepository,
                                eventRepository: eventRepository,
                                organizationRepository: organizationRepository
                            ) {
                                viewModel.invalidatePublicCache()
                                await viewModel.refresh()
                            }
                        }
                    ) {
                        FeaturedBannerEditorView(
                            repository: repository,
                            mode: .edit(banner),
                            newsRepository: newsRepository,
                            eventRepository: eventRepository,
                            organizationRepository: organizationRepository
                        ) {
                            viewModel.invalidatePublicCache()
                            await viewModel.refresh()
                        }
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
                viewModel.invalidatePublicCache()
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

    private var visibleBanners: [FeaturedBanner] {
        return viewModel.banners.filter { banner in
            guard filter.includes(banner) else { return false }
            return LocalSearchMatcher.matches(
                query: searchText,
                values: [
                    banner.internalName,
                    banner.title,
                    banner.subtitle,
                    banner.id,
                    banner.federalState?.rawValue,
                    banner.actionTargetID
                ]
            )
        }
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
