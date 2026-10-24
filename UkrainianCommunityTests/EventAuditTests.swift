import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct EventAuditTests {
    func fixture() -> Event {
        let start = Date().addingTimeInterval(86400)
        return Event(id: "event-audit-" + UUID().uuidString, schemaVersion: 2,
            localizations: ["de": EventLocalizedContent(title: "Deutscher Titel", summary: "Zusammenfassung", details: "Beschreibung")],
            title: "Title", summary: "Summary", details: "Details", federalState: .tirol,
            source: ContentSourceMetadata(sourceType: .organization, organizationId: "test-org", organizationName: "Organizer"),
            authorId: "author", authorName: "Author", city: "Innsbruck", venue: "Hall", address: "Street 1",
            latitude: 47.26, longitude: 11.39, contactEmail: "test@example.org",
            imageURL: "https://example.org/image.jpg", mediaMetadata: EventMediaMetadata(caption: "Caption", alternativeText: "Alt", credit: "Credit"),
            startDate: start, endDate: start.addingTimeInterval(3600),
            occurrences: [EventOccurrence(id: "primary", startDate: start, endDate: start.addingTimeInterval(3600), status: .cancelled),
                          EventOccurrence(id: "second", startDate: start.addingTimeInterval(86400), endDate: start.addingTimeInterval(90000))],
            createdAt: .now, updatedAt: .now, scheduledAt: start.addingTimeInterval(-3600),
            requiresRegistration: true, pricing: EventPricing(kind: .free), capacity: 20, registeredCount: 5,
            comments: [], moderationStatus: .draft, registrationState: .registered,
            likeCount: 10, likeState: .liked, viewCount: 50, category: .meetups,
            tags: ["audit"], isBookmarked: true, commentCount: 130)
    }
    @Test func editorKeepsGermanAndOccurrenceIdentity() {
        let original = fixture()
        let editor = EventEditorViewModel(repository: MockEventRepository(), mode: .edit(existing: original))
        #expect(editor.germanTitle == original.localizations["de"]?.title)
        #expect(editor.allOccurrences == original.occurrences)
        #expect(editor.allOccurrences == editor.allOccurrences)
    }
    @Test func editSaveAndReadRetainsPublishingFieldsAndCounters() async throws {
        let repository = MockEventRepository()
        let original = fixture()
        try await repository.createEvent(original)
        defer { Task { try? await repository.deleteEvent(id: original.id) } }
        let editor = EventEditorViewModel(repository: repository, mode: .edit(existing: original))
        editor.title = "Changed title"
        #expect(await editor.publish())
        let stored = try await repository.fetchEvent(id: original.id)
        #expect(stored.title == "Changed title")
        #expect(stored.schemaVersion == 2 && stored.localizations["de"] == original.localizations["de"])
        #expect(stored.occurrences == original.occurrences)
        #expect(stored.scheduledAt == original.scheduledAt)
        #expect(stored.mediaMetadata == original.mediaMetadata && stored.imageURL == original.imageURL)
        #expect(stored.pricing == original.pricing && stored.participationMode == original.participationMode)
        #expect(stored.contactEmail == original.contactEmail && stored.authorId == original.authorId)
        #expect(stored.likeCount == 10 && stored.commentCount == 130 && stored.viewCount == 50)
        #expect(stored.registeredCount == 5 && stored.registrationState == .registered && stored.isBookmarked)
    }
    @Test func publishRejectsOversizedTranslationsBeforeWriting() async {
        let editor = EventEditorViewModel(repository: MockEventRepository(), mode: .edit(existing: fixture()))
        editor.germanDetails = String(repeating: "x", count: EventEditorViewModel.localizedDetailsLimit + 1)
        #expect(!editor.canPublish)
        #expect(await editor.publish() == false)
    }
    @Test func unsavedEditsIncludeDatesContactsTranslationsAndReverting() {
        let editor = EventEditorViewModel(repository: MockEventRepository(), mode: .edit(existing: fixture()))
        #expect(!editor.hasUnsavedEdits)
        let old = editor.contactEmail
        editor.contactEmail = "new@example.org"
        #expect(editor.hasUnsavedEdits)
        editor.contactEmail = old
        #expect(!editor.hasUnsavedEdits)
        editor.germanTitle += " Updated"
        #expect(editor.hasUnsavedEdits)
    }
    @Test func todayIncludesOngoingMultiDayEventsButNotOldOrCancelledSessions() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let event = fixture()
        let now = event.occurrences[1].startDate.addingTimeInterval(1800)
        #expect(EventDiscoveryFilter.today.matches(event, at: now, calendar: calendar))
        #expect(!EventDiscoveryFilter.today.matches(event, at: event.startDate, calendar: calendar))
        #expect(!EventDiscoveryFilter.today.matches(event, at: now.addingTimeInterval(86400), calendar: calendar))
        #expect(EventDiscoveryFilter.all.matches(event, at: now.addingTimeInterval(86400), calendar: calendar))
    }

    @Test func todayIncludesAnEventWhichStartedYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12))!
        let event = Event(id: "ongoing", title: "Ongoing", summary: "Summary", details: "Details", city: "Wien", venue: "Hall",
                          startDate: now.addingTimeInterval(-86400), endDate: now.addingTimeInterval(86400),
                          createdAt: now, updatedAt: now, capacity: nil, registeredCount: 0, comments: [],
                          moderationStatus: .approved, registrationState: .notRegistered, likeCount: 0, likeState: .notLiked)
        #expect(EventDiscoveryFilter.today.matches(event, at: now, calendar: calendar))
        #expect(EventDiscoveryFilter.thisWeek.matches(event, at: now, calendar: calendar))
        #expect(!EventDiscoveryFilter.today.matches(event, at: now.addingTimeInterval(3 * 86400), calendar: calendar))
    }

    @Test func allDayEditingDoesNotExtendTheLastDayOnEverySave() {
        let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let event = Event(id: "all-day", title: "Title", summary: "Summary", details: "Details", city: "Wien", venue: "Hall",
                          startDate: start, endDate: end, createdAt: .now, updatedAt: .now,
                          capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved,
                          registrationState: .notRegistered, likeCount: 0, likeState: .notLiked, isAllDay: true)
        let editor = EventEditorViewModel(repository: MockEventRepository(), mode: .edit(existing: event))
        #expect(editor.allOccurrences.first?.endDate == end)
        let additional = EventOccurrence(id: "all-day-session", startDate: start, endDate: end, isAllDay: true)
        editor.additionalOccurrences = [additional]
        editor.updateOccurrence(id: additional.id, isAllDay: true)
        editor.updateOccurrence(id: additional.id, isAllDay: true)
        #expect(editor.additionalOccurrences[0] == additional)
        #expect(EventEditorViewModel.editableEndDate(for: additional) == Calendar.current.date(byAdding: .day, value: -1, to: end))
    }

}
