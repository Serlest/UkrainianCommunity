import Foundation

struct OrganizationActivityCursor: Equatable {
    let date: Date
    let documentID: String
}

struct OrganizationActivityPage {
    let items: [OrganizationActivityItem]
    let nextCursor: OrganizationActivityCursor?
    let hasMore: Bool
}

@MainActor
protocol OrganizationActivityPageRepository {
    func fetchOrganizationActivityPage(organizationID: String, limit: Int, after: OrganizationActivityCursor?) async throws -> OrganizationActivityPage
}

extension OrganizationActivityPage {
    static func mock(items: [OrganizationActivityItem], limit: Int, after: OrganizationActivityCursor?, eventSchedule: Bool = false) -> Self {
        func date(_ item: OrganizationActivityItem) -> Date { eventSchedule ? item.eventEndDate ?? item.publishedAt : item.publishedAt }
        let ordered = items.sorted {
            if date($0) == date($1) { return eventSchedule ? $0.id < $1.id : $0.id > $1.id }
            return eventSchedule ? date($0) < date($1) : date($0) > date($1)
        }
        let remaining = ordered.filter { item in
            guard let after else { return true }
            if date(item) == after.date { return eventSchedule ? item.id > after.documentID : item.id < after.documentID }
            return eventSchedule ? date(item) > after.date : date(item) < after.date
        }
        let page = Array(remaining.prefix(max(1, min(limit, 50))))
        let hasMore = remaining.count > page.count
        return Self(items: page, nextCursor: hasMore ? page.last.map { .init(date: date($0), documentID: $0.id) } : nil, hasMore: hasMore)
    }
}
