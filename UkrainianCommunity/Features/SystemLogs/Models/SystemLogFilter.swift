import Foundation

struct SystemLogFilter: Codable, Equatable {
    var categories: Set<SystemLogCategory>
    var severities: Set<SystemLogSeverity>
    var eventTypes: Set<SystemLogEventType>
    var actorRoles: Set<SystemLogActorRole>
    var targetTypes: Set<SystemLogTargetType>
    var outcomes: Set<SystemLogOutcome>
    var actorUserId: String?
    var targetId: String?
    var organizationId: String?
    var isReviewed: Bool?
    var searchText: String?
    var startDate: Date?
    var endDate: Date?

    nonisolated init(
        categories: Set<SystemLogCategory> = [],
        severities: Set<SystemLogSeverity> = [],
        eventTypes: Set<SystemLogEventType> = [],
        actorRoles: Set<SystemLogActorRole> = [],
        targetTypes: Set<SystemLogTargetType> = [],
        outcomes: Set<SystemLogOutcome> = [],
        actorUserId: String? = nil,
        targetId: String? = nil,
        organizationId: String? = nil,
        isReviewed: Bool? = nil,
        searchText: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.categories = categories
        self.severities = severities
        self.eventTypes = eventTypes
        self.actorRoles = actorRoles
        self.targetTypes = targetTypes
        self.outcomes = outcomes
        self.actorUserId = actorUserId
        self.targetId = targetId
        self.organizationId = organizationId
        self.isReviewed = isReviewed
        self.searchText = searchText
        self.startDate = startDate
        self.endDate = endDate
    }

    nonisolated static let empty = SystemLogFilter()
}
