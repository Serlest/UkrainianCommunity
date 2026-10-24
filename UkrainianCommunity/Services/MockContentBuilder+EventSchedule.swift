import Foundation

extension MockContentBuilder {
    nonisolated static func eventsAuditFixture() -> [Event]? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestEventsAudit"] == "1" else { return nil }
        let start = Date().addingTimeInterval(86400)
        return ["own", "foreign"].map { scope in
            Event(id: "audit-event-" + scope, schemaVersion: 2,
                  localizations: ["de": EventLocalizedContent(title: "Audit Event " + scope, summary: "Zusammenfassung", details: "Beschreibung des Termins")],
                  title: "Audit Event " + scope, summary: "Summary", details: "Details of this event",
                  regionScope: .federalState, federalState: .tirol,
                  source: ContentSourceMetadata(sourceType: .organization, organizationId: scope == "own" ? "role-fixture" : "org-1", organizationName: "Test Organizer"),
                  authorId: "audit-author", authorName: "Author", city: "Innsbruck", venue: "Test Hall", address: "Street 1",
                  latitude: 47.26, longitude: 11.39,
                  startDate: start, endDate: start.addingTimeInterval(3600), createdAt: .now, updatedAt: .now,
                  requiresRegistration: true, pricing: EventPricing(kind: .free), capacity: 20, registeredCount: 0,
                  comments: [], moderationStatus: .approved, registrationState: .notRegistered, likeCount: 0, likeState: .notLiked)
        }
        #else
        return nil
        #endif
    }

    /// Synthetic public events reached through the existing mock event repository.
    /// Fixed dates deliberately exercise both upcoming and past catalog sections.
    nonisolated static func multiDayScheduleFixture(scenario: String) -> Event? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let title: String
        let start: DateComponents
        let end: DateComponents
        switch scenario {
        case "hackathon":
            title = "AI Hackathon — Schedule Fixture"
            start = DateComponents(year: 2026, month: 9, day: 11, hour: 9)
            end = DateComponents(year: 2026, month: 9, day: 12, hour: 16)
        case "marktplatz":
            title = "Marktplatz — Schedule Fixture"
            start = DateComponents(year: 2026, month: 11, day: 13, hour: 11)
            end = DateComponents(year: 2026, month: 12, day: 23, hour: 21)
        default:
            return nil
        }
        guard let startDate = calendar.date(from: start), let endDate = calendar.date(from: end) else { return nil }
        return Event(
            id: "schedule-\(scenario)", title: title,
            summary: "Synthetic multi-day schedule", details: "Local schedule regression fixture.",
            regionScope: .austria, federalState: nil, source: ContentSourceMetadata(sourceType: .app),
            city: "Wien", venue: "Test venue", startDate: startDate, endDate: endDate,
            occurrences: [EventOccurrence(id: "schedule-\(scenario)", startDate: startDate, endDate: endDate)],
            createdAt: startDate, updatedAt: startDate,
            requiresRegistration: false, participationMode: EventParticipationMode.none,
            capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved,
            registrationState: .notRegistered, likeCount: 0, likeState: .notLiked
        )
    }
}
