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
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?

    private let repository: EventRepository
    private let imageUploadService = ImageUploadService.shared

    init(repository: EventRepository) {
        self.repository = repository
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedDetails.isEmpty
            && !trimmedCity.isEmpty
            && !trimmedVenue.isEmpty
            && !isProcessingImage
            && !isUploadingImage
            && !isPublishing
    }

    func setSelectedImageData(_ data: Data?) {
        guard let data else {
            selectedImageData = nil
            return
        }

        successMessage = nil
        errorMessage = nil
        selectedImageData = data
    }

    func setImageProcessing(_ isProcessing: Bool) {
        isProcessingImage = isProcessing
    }

    func publish() async -> Bool {
        guard !isPublishing else { return false }

        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return false
        }

        let now = Date()
        let eventID = UUID().uuidString
        var resolvedImageURL: String?
        let newEvent = Event(
            id: eventID,
            title: trimmedTitle,
            summary: trimmedSummary,
            details: trimmedDetails,
            city: trimmedCity,
            venue: trimmedVenue,
            imageURL: nil,
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
            if let selectedImageData {
                isUploadingImage = true
                let downloadURL = try await imageUploadService.uploadEventCoverImage(data: selectedImageData, eventID: eventID)
                resolvedImageURL = downloadURL.absoluteString
                isUploadingImage = false
            }

            let eventToCreate = Event(
                id: newEvent.id,
                title: newEvent.title,
                summary: newEvent.summary,
                details: newEvent.details,
                city: newEvent.city,
                venue: newEvent.venue,
                imageURL: resolvedImageURL,
                startDate: newEvent.startDate,
                endDate: newEvent.endDate,
                createdAt: newEvent.createdAt,
                updatedAt: newEvent.updatedAt,
                capacity: newEvent.capacity,
                registeredCount: newEvent.registeredCount,
                comments: newEvent.comments,
                moderationStatus: newEvent.moderationStatus,
                registrationState: newEvent.registrationState,
                likeCount: newEvent.likeCount,
                likeState: newEvent.likeState
            )

            try await repository.createEvent(eventToCreate)
            successMessage = AppStrings.Events.publishedSuccessfully
            title = ""
            summary = ""
            details = ""
            city = ""
            venue = ""
            selectedImageData = nil
            startDate = now
            endDate = now.addingTimeInterval(60 * 60)
            return true
        } catch {
            isUploadingImage = false
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
            errorMessage = AppStrings.Events.summaryRequired
            return false
        }

        guard !trimmedDetails.isEmpty else {
            errorMessage = AppStrings.Events.detailsRequired
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
