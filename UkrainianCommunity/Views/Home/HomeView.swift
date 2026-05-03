import SwiftUI

private func sanitizedHomeAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    guard trimmedValue.count >= 20 else {
        return trimmedValue
    }

    guard trimmedValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
        return trimmedValue
    }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    if trimmedValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @ObservedObject var marketplaceViewModel: MarketplaceViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GradientHeroCard(title: AppStrings.Home.title, subtitle: AppStrings.Home.subtitle) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.user.fullName)
                                .font(.headline)
                            Text(viewModel.user.city)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Text(viewModel.user.role.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Home.highlights)
                        .font(.title3.weight(.semibold))
                    AdaptiveCardGrid(items: homeHighlights) { item in
                        CommunityCard {
                            Label(item.title, systemImage: item.systemImage)
                                .font(.headline)
                                .foregroundStyle(AppTheme.primaryBlue)
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Home.latestNews)
                        .font(.title3.weight(.semibold))

                    if newsViewModel.isLoading && latestNews.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if newsViewModel.error != nil && latestNews.isEmpty {
                        CommunityCard {
                            Text(newsErrorText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if latestNews.isEmpty {
                        CommunityCard {
                            Text(AppStrings.News.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if newsViewModel.error != nil {
                            CommunityCard {
                                Text(newsErrorText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(latestNews) { post in
                            NavigationLink {
                                NewsDetailView(viewModel: newsViewModel, postID: post.id, onNewsDeleted: {})
                            } label: {
                                HomeNewsCard(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Events.title)
                        .font(.title3.weight(.semibold))

                    if eventsViewModel.isLoading && latestEvents.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if eventsViewModel.error != nil && latestEvents.isEmpty {
                        CommunityCard {
                            Text(eventErrorText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if latestEvents.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Events.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if eventsViewModel.error != nil {
                            CommunityCard {
                                Text(eventErrorText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(latestEvents) { event in
                            NavigationLink {
                                EventDetailView(viewModel: eventsViewModel, eventID: event.id, onEventDeleted: {})
                            } label: {
                                HomeEventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(AppStrings.Organizations.title)
                        .font(.title3.weight(.semibold))

                    if organizationsViewModel.isLoading && latestOrganizations.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else if organizationsViewModel.error != nil && latestOrganizations.isEmpty {
                        CommunityCard {
                            Text(organizationErrorText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if latestOrganizations.isEmpty {
                        CommunityCard {
                            Text(AppStrings.Organizations.empty)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if organizationsViewModel.error != nil {
                            CommunityCard {
                                Text(organizationErrorText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(latestOrganizations) { organization in
                            NavigationLink {
                                OrganizationDetailView(viewModel: organizationsViewModel, organizationID: organization.id)
                            } label: {
                                HomeOrganizationCard(organization: organization)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Tabs.home)
        .task {
            async let homeLoad: Void = viewModel.loadIfNeeded()
            async let newsLoad: Void = newsViewModel.loadIfNeeded()
            async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
            async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
            _ = await (homeLoad, newsLoad, eventsLoad, organizationsLoad)
        }
    }

    private var latestNews: [NewsPost] {
        Array(newsViewModel.posts.prefix(3))
    }

    private var latestEvents: [Event] {
        Array(eventsViewModel.events.prefix(3))
    }

    private var homeHighlights: [HomeHighlight] {
        [
            HomeHighlight(id: "news", title: AppStrings.Tabs.news, detail: AppStrings.homeHighlightNews(newsViewModel.posts.count), systemImage: "newspaper.fill"),
            HomeHighlight(id: "events", title: AppStrings.Tabs.events, detail: AppStrings.homeHighlightEvents(eventsViewModel.events.count), systemImage: "calendar"),
            HomeHighlight(id: "organizations", title: AppStrings.Tabs.organizations, detail: AppStrings.homeHighlightOrganizations(organizationsViewModel.organizations.count), systemImage: "building.2.fill"),
            HomeHighlight(id: "marketplace", title: AppStrings.Tabs.marketplace, detail: AppStrings.homeHighlightMarketplace(marketplaceViewModel.items.count), systemImage: "basket.fill")
        ]
    }

    private var newsErrorText: String {
        switch newsViewModel.error {
        case .network:
            AppStrings.News.loadNetworkError
        case .permissionDenied:
            AppStrings.News.loadPermissionError
        case .validationFailed:
            AppStrings.News.loadValidationError
        case .notFound:
            AppStrings.News.empty
        case .unknown:
            AppStrings.News.loadUnknownError
        case nil:
            ""
        }
    }

    private var eventErrorText: String {
        switch eventsViewModel.error {
        case .network:
            AppStrings.Events.loadNetworkError
        case .permissionDenied:
            AppStrings.Events.loadPermissionError
        case .validationFailed:
            AppStrings.Events.loadValidationError
        case .notFound:
            AppStrings.Events.empty
        case .unknown:
            AppStrings.Events.loadUnknownError
        case nil:
            ""
        }
    }

    private var latestOrganizations: [Organization] {
        Array(organizationsViewModel.organizations.prefix(3))
    }

    private var organizationErrorText: String {
        switch organizationsViewModel.error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.loadPermissionError
        case .validationFailed:
            AppStrings.Organizations.loadValidationError
        case .notFound:
            AppStrings.Organizations.empty
        case .unknown:
            AppStrings.Organizations.loadUnknownError
        case nil:
            ""
        }
    }
}

private struct HomeNewsCard: View {
    let post: NewsPost

    var body: some View {
        CommunityCard {
            Text(post.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(post.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(alignment: .center, spacing: 12) {
                Text(sanitizedHomeAuthorName(post.authorName))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Label("\(post.likeCount)", systemImage: post.likeState.isLiked ? "heart.fill" : "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(post.likeState.isLiked ? AppTheme.accentRed : .secondary)
            }
        }
    }
}

private struct HomeEventCard: View {
    let event: Event

    var body: some View {
        CommunityCard {
            Text(event.title)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(eventDateText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                Text(event.registrationState.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryBlue)

                Spacer()

                Label("\(event.likeCount)", systemImage: event.likeState.isLiked ? "heart.fill" : "heart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(event.likeState.isLiked ? AppTheme.accentRed : .secondary)
            }
        }
    }

    private var eventDateText: String {
        let startDateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .short)

        guard event.endDate > event.startDate else {
            return startDateText
        }

        let isSameDay = Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate)
        if isSameDay {
            let endTimeText = LocalizationStore.dateString(from: event.endDate, dateStyle: .none, timeStyle: .short)
            return "\(startDateText) - \(endTimeText)"
        }

        let endDateText = LocalizationStore.dateString(from: event.endDate, dateStyle: .medium, timeStyle: .short)
        return "\(startDateText) - \(endDateText)"
    }
}

private struct HomeOrganizationCard: View {
    let organization: Organization

    var body: some View {
        CommunityCard {
            if organization.imageURL != nil {
                RemoteCardImage(imageURL: organization.imageURL, height: 220)
            }

            Text(organization.name)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(organization.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(organization.city)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                userRepository: MockUserRepository()
            ),
            newsViewModel: NewsViewModel(repository: MockNewsRepository()),
            eventsViewModel: EventsViewModel(repository: MockEventRepository()),
            organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            marketplaceViewModel: MarketplaceViewModel(repository: MockMarketplaceRepository())
        )
    }
}
