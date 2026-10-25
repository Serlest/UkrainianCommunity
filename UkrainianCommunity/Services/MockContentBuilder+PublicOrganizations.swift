import Foundation

extension MockContentBuilder {
    nonisolated static var usesPublicOrganizationsAudit: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("-ui-testing") && ProcessInfo.processInfo.environment["UITestPublicOrganizationsAudit"] == "1"
        #else
        return false
        #endif
    }
    nonisolated static func publicOrganizationsAuditFixture() -> [Organization]? {
        guard usesPublicOrganizationsAudit else { return nil }
        let empty = ProcessInfo.processInfo.environment["UITestPublicOrganizationEmptySections"] == "1"
        return ["role-fixture", "audit-foreign-org"].map { id in
            Organization(id: id, name: id == "role-fixture" ? "Audit Community" : "Foreign Community",
                description: String(repeating: "Community support and cultural events for Ukrainian families. ", count: 5),
                regionScope: .federalState, federalState: .tirol, city: "Innsbruck",
                contactEmail: "audit@example.org", phone: "+43 512 123456", website: "https://example.org/community",
                address: "Museumstraße 1", latitude: 47.26, longitude: 11.39, organizationType: "culture",
                directoryProfile: OrganizationDirectoryProfile(services: ["Community meetings", "Language courses"]),
                ownerId: empty ? nil : id == "role-fixture" ? "org-owner-1" : "foreign-owner",
                adminIds: !empty && id == "role-fixture" ? ["org-admin-1", "mixed-1"] : [],
                moderatorIds: !empty && id == "role-fixture" ? ["org-moderator-1"] : [],
                createdAt: .now, updatedAt: .now, moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
        }
    }
    nonisolated static func publicOrganizationNewsFixture() -> [NewsPost]? {
        guard usesPublicOrganizationsAudit else { return nil }
        if ProcessInfo.processInfo.environment["UITestPublicOrganizationEmptySections"] == "1" { return [] }
        return (0..<26).map { index in
            let date = Date().addingTimeInterval(-Double(index) * 60)
            return NewsPost(id: "audit-org-news-\(index)", title: "Organization News \(index)", subtitle: "Community news",
                source: ContentSourceMetadata(sourceType: .organization, organizationId: "role-fixture", organizationName: "Audit Community"),
                body: "Publication details", authorName: "Author", publishedAt: date, createdAt: date, updatedAt: date,
                comments: [], moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
        }
    }
    nonisolated static func publicOrganizationEventsFixture() -> [Event]? {
        guard usesPublicOrganizationsAudit else { return nil }
        if ProcessInfo.processInfo.environment["UITestPublicOrganizationEmptySections"] == "1" { return [] }
        return ["ongoing", "future", "past"].map { state in
            let start = Date().addingTimeInterval(state == "ongoing" ? -86400 : state == "past" ? -172800 : 86400)
            let end = Date().addingTimeInterval(state == "ongoing" ? 86400 : state == "past" ? -86400 : 90000)
            return Event(id: "audit-org-event-" + state, title: "Organization Event " + state, summary: "Summary", details: "Details",
                source: ContentSourceMetadata(sourceType: .organization, organizationId: "role-fixture", organizationName: "Audit Community"),
                city: "Innsbruck", venue: "Community Hall", startDate: start, endDate: end, createdAt: .now, updatedAt: .now,
                capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved, registrationState: .notRegistered, likeCount: 0, likeState: .notLiked)
        }
    }
}
