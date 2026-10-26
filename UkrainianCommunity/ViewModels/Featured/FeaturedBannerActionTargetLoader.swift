import Foundation

@MainActor
struct FeaturedBannerActionTargetLoader {
    private let newsRepository: NewsRepository?
    private let eventRepository: EventRepository?
    private let organizationRepository: OrganizationRepository?

    init(
        newsRepository: NewsRepository?,
        eventRepository: EventRepository?,
        organizationRepository: OrganizationRepository?
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
    }

}

extension FeaturedBannerActionTargetLoader {
    enum Cursor: Equatable {
        case news(NewsPageCursor), event(EventPageCursor), organization(OrganizationPageCursor)
    }
    struct Page { let items:[FeaturedBannerActionTargetItem];let next:Cursor? }
    func page(kind:FeaturedBannerActionTargetKind,after:Cursor?) async throws->Page {
        try Task.checkCancellation()
        switch kind {
        case .news:
            guard let newsRepository else {throw AppError.validationFailed}
            let cursor:NewsPageCursor?;if case .news(let value)=after {cursor=value}else{cursor=nil}
            let page=try await newsRepository.fetchNewsPage(limit:50,after:cursor)
            let next=page.hasMore ? page.nextCursor.map(Cursor.news):nil
            guard next != after || next == nil else {throw AppError.validationFailed}
            return Page(items:page.items.filter{$0.moderationStatus == .approved}.map(FeaturedBannerActionTargetItem.init(news:)),next:next)
        case .event:
            guard let eventRepository else {throw AppError.validationFailed}
            let cursor:EventPageCursor?;if case .event(let value)=after {cursor=value}else{cursor=nil}
            let page=try await eventRepository.fetchEventsPage(limit:50,after:cursor)
            let next=page.hasMore ? page.nextCursor.map(Cursor.event):nil
            guard next != after || next == nil else {throw AppError.validationFailed}
            return Page(items:page.items.filter{$0.moderationStatus == .approved}.map(FeaturedBannerActionTargetItem.init(event:)),next:next)
        case .organization:
            guard let organizationRepository else {throw AppError.validationFailed}
            let cursor:OrganizationPageCursor?;if case .organization(let value)=after {cursor=value}else{cursor=nil}
            let page=try await organizationRepository.fetchOrganizationsPage(limit:50,after:cursor)
            let next=page.hasMore ? page.nextCursor.map(Cursor.organization):nil
            guard next != after || next == nil else {throw AppError.validationFailed}
            return Page(items:page.items.filter{$0.moderationStatus == .approved}.map(FeaturedBannerActionTargetItem.init(organization:)),next:next)
        }
    }
    func selected(kind:FeaturedBannerActionTargetKind,id:String) async throws->FeaturedBannerActionTargetItem? {
        switch kind {
        case .news:
            guard let newsRepository else {return nil};let value=try await newsRepository.fetchNews(id:id)
            return value.moderationStatus == .approved ? FeaturedBannerActionTargetItem(news:value):nil
        case .event:
            guard let eventRepository else {return nil};let value=try await eventRepository.fetchEvent(id:id)
            return value.moderationStatus == .approved ? FeaturedBannerActionTargetItem(event:value):nil
        case .organization:
            guard let organizationRepository else {return nil};let value=try await organizationRepository.fetchOrganization(id:id)
            return value.moderationStatus == .approved ? FeaturedBannerActionTargetItem(organization:value):nil
        }
    }
}
