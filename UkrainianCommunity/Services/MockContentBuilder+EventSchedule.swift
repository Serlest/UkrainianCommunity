import Foundation

extension MockContentBuilder {
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
            requiresRegistration: false, participationMode: .none,
            capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved,
            registrationState: .notRegistered, likeCount: 0, likeState: .notLiked
        )
    }
}
