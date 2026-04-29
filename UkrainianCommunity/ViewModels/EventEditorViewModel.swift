import Combine
import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    @Published var title = ""
    @Published var summary = ""
    @Published var details = ""
    @Published var city = ""
    @Published var venue = ""
    @Published var startDate = Date()
    @Published var endDate = Date().addingTimeInterval(60 * 60)
    @Published var isPublishing = false
    @Published var successMessage: String?
    @Published var errorMessage: String?

    private let repository: EventRepository

    init(repository: EventRepository) {
        self.repository = repository
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedDetails.isEmpty
            && !trimmedCity.isEmpty
            && !trimmedVenue.isEmpty
            && !isPublishing
    }

    func publish() async -> Bool {
        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return false
        }

        let now = Date()
        let newEvent = Event(
            id: UUID().uuidString,
            title: trimmedTitle,
            summary: trimmedSummary,
            details: trimmedDetails,
            city: trimmedCity,
            venue: trimmedVenue,
            startDate: startDate,
            endDate: endDate,
            createdAt: now,
            updatedAt: now,
            capacity: nil,
            registeredCount: 0,
            comments: [],
            moderationStatus: .approved,
            registrationState: .notRegistered,
            likeCount: 0,
            likeState: .notLiked
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            try await repository.createEvent(newEvent)
            successMessage = AppStrings.Events.publishedSuccessfully
            title = ""
            summary = ""
            details = ""
            city = ""
            venue = ""
            startDate = now
            endDate = now.addingTimeInterval(60 * 60)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetails: String {
        details.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedVenue: String {
        venue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate() -> Bool {
        guard !trimmedTitle.isEmpty else {
            errorMessage = AppStrings.Validation.eventTitleRequired
            return false
        }

        guard !trimmedSummary.isEmpty else {
            errorMessage = String(localized: "events.editor.validation.summary_required", defaultValue: "Summary is required.")
            return false
        }

        guard !trimmedDetails.isEmpty else {
            errorMessage = String(localized: "events.editor.validation.details_required", defaultValue: "Details are required.")
            return false
        }

        guard !trimmedCity.isEmpty else {
            errorMessage = AppStrings.Validation.eventCityRequired
            return false
        }

        guard !trimmedVenue.isEmpty else {
            errorMessage = AppStrings.Validation.eventVenueRequired
            return false
        }

        guard endDate > startDate else {
            errorMessage = AppStrings.Events.invalidDateOrder
            return false
        }

        return true
    }
}
