import Foundation

@MainActor
struct FeaturedBannerActionTargetLoader {
    private let newsRepository: NewsRepository?
    private let eventRepository: EventRepository?
    private let organizationRepository: OrganizationRepository?
    private let pageSize = 50
    private let resultLimit = 250

    init(
        newsRepository: NewsRepository?,
        eventRepository: EventRepository?,
        organizationRepository: OrganizationRepository?
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
    }

    func load(kind: FeaturedBannerActionTargetKind) async throws -> [FeaturedBannerActionTargetItem] {
        switch kind {
        case .news:
            guard let newsRepository else { throw AppError.validationFailed }
            return try await fetchAllNews(from: newsRepository)
                .filter { $0.moderationStatus == .approved }
                .sorted {
                    $0.publishedAt == $1.publishedAt ? $0.id < $1.id : $0.publishedAt > $1.publishedAt
                }
                .map(FeaturedBannerActionTargetItem.init(news:))
        case .event:
            guard let eventRepository else { throw AppError.validationFailed }
            return try await fetchAllEvents(from: eventRepository)
                .filter { $0.moderationStatus == .approved }
                .sorted {
                    $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate > $1.startDate
                }
                .map(FeaturedBannerActionTargetItem.init(event:))
        case .organization:
            guard let organizationRepository else { throw AppError.validationFailed }
            return try await fetchAllOrganizations(from: organizationRepository)
                .filter { $0.moderationStatus == .approved }
                .sorted {
                    let result = LocalizationStore.compareForSorting($0.name, $1.name)
                    return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
                }
                .map(FeaturedBannerActionTargetItem.init(organization:))
        }
    }

    private func fetchAllNews(from repository: NewsRepository) async throws -> [NewsPost] {
        var items: [NewsPost] = []
        var cursor: NewsPageCursor?

        repeat {
            let page = try await repository.fetchNewsPage(limit: pageSize, after: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if !page.hasMore || cursor == nil || items.count >= resultLimit { break }
        } while !Task.isCancelled

        return Array(items.prefix(resultLimit))
    }

    private func fetchAllEvents(from repository: EventRepository) async throws -> [Event] {
        var items: [Event] = []
        var cursor: EventPageCursor?

        repeat {
            let page = try await repository.fetchEventsPage(limit: pageSize, after: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if !page.hasMore || cursor == nil || items.count >= resultLimit { break }
        } while !Task.isCancelled

        return Array(items.prefix(resultLimit))
    }

    private func fetchAllOrganizations(from repository: OrganizationRepository) async throws -> [Organization] {
        var items: [Organization] = []
        var cursor: OrganizationPageCursor?

        repeat {
            let page = try await repository.fetchOrganizationsPage(limit: pageSize, after: cursor)
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
            if !page.hasMore || cursor == nil || items.count >= resultLimit { break }
        } while !Task.isCancelled

        return Array(items.prefix(resultLimit))
    }
}
