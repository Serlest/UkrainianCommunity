import Foundation

extension MockContentBuilder {
    nonisolated static func registrationAuditEvents() -> [Event]? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestMyRegistrations"] == "1" else { return nil }
        let now = Date()
        return (0..<24).map { index in
            let offset: TimeInterval = index == 0 ? 7200 : index == 1 && ProcessInfo.processInfo.environment["UITestMyRegistrationsOffline"] != "1" ? -1800 : -Double(index + 1) * 86400
            let start = now.addingTimeInterval(offset)
            return Event(id: String(format: "registration-%02d", index),
                         title: index == 0 ? "Майбутня зустріч громади / Kommendes Treffen" : "Подія громади / Veranstaltung \(index)",
                         summary: "Спільнота українців в Австрії / Ukrainische Gemeinschaft in Österreich",
                         details: "Registration audit fixture", source: ContentSourceMetadata(sourceType: .organization, organizationId: "org-1", organizationName: "Community"),
                         city: "Wien", venue: "Community House", startDate: start, endDate: start.addingTimeInterval(3600),
                         createdAt: now, updatedAt: now, requiresRegistration: true,
                         capacity: 100, registeredCount: 1, comments: [], moderationStatus: .approved,
                         registrationState: .registered, likeCount: 0, likeState: .notLiked,
                         cancellationState: index == 3 ? "cancelled" : nil)
        }
        #else
        return nil
        #endif
    }
}
