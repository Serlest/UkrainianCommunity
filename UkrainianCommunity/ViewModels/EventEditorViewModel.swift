import Combine
import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    struct CreateContext {
        let organizationId: String?
        let organizationName: String?
        let organizationImageURL: String?

        nonisolated static let app = CreateContext(
            organizationId: nil,
            organizationName: nil,
            organizationImageURL: nil
        )

        var source: ContentSourceMetadata {
            guard let organizationId, !organizationId.isEmpty else {
                return ContentSourceMetadata(sourceType: .app)
            }

            return ContentSourceMetadata(
                sourceType: .organization,
                organizationId: organizationId,
                organizationName: organizationName,
                organizationImageURL: organizationImageURL
            )
        }
    }

    enum Mode {
        case create(context: CreateContext = .app)
        case edit(existing: Event)

        var isEditing: Bool {
            if case .edit = self {
                return true
            }
            return false
        }
    }

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
    private let mode: Mode

    init(repository: EventRepository, mode: Mode = .create()) {
        self.repository = repository
        self.mode = mode

        if case let .edit(existingEvent) = mode {
            title = existingEvent.title
            summary = existingEvent.summary
            details = existingEvent.details
            city = existingEvent.city
            venue = existingEvent.venue
            startDate = existingEvent.startDate
            endDate = existingEvent.endDate
        }
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

    var navigationTitle: String {
        mode.isEditing ? AppStrings.Events.editTitle : AppStrings.Events.editorTitle
    }

    var submitButtonTitle: String {
        mode.isEditing ? AppStrings.Events.saveChanges : AppStrings.Events.publish
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
        let eventID: String
        let createdAt: Date
        let existingImageURL: String?
        let existingRegisteredCount: Int
        let existingComments: [Comment]
        let existingModerationStatus: ModerationStatus
        let existingRegistrationState: EventRegistrationState
        let existingLikeCount: Int
        let existingLikeState: LikeState
        let existingCapacity: Int?
        let existingRegionScope: RegionScope?
        let existingFederalState: AustrianFederalState?
        let existingSource: ContentSourceMetadata
        switch mode {
        case let .create(context):
            eventID = UUID().uuidString
            createdAt = now
            existingImageURL = nil
            existingRegisteredCount = 0
            existingComments = []
            existingModerationStatus = .approved
            existingRegistrationState = .notRegistered
            existingLikeCount = 0
            existingLikeState = .notLiked
            existingCapacity = nil
            existingRegionScope = .city
            existingFederalState = .tirol
            existingSource = context.source
        case let .edit(existingEvent):
            eventID = existingEvent.id
            createdAt = existingEvent.createdAt
            existingImageURL = existingEvent.imageURL
            existingRegisteredCount = existingEvent.registeredCount
            existingComments = existingEvent.comments
            existingModerationStatus = existingEvent.moderationStatus
            existingRegistrationState = existingEvent.registrationState
            existingLikeCount = existingEvent.likeCount
            existingLikeState = existingEvent.likeState
            existingCapacity = existingEvent.capacity
            existingRegionScope = existingEvent.regionScope
            existingFederalState = existingEvent.federalState
            existingSource = existingEvent.source
        }
        var resolvedImageURL: String?
        let newEvent = Event(
            id: eventID,
            title: trimmedTitle,
            summary: trimmedSummary,
            details: trimmedDetails,
            regionScope: existingRegionScope,
            federalState: existingFederalState,
            source: existingSource,
            city: trimmedCity,
            venue: trimmedVenue,
            imageURL: nil,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: now,
            capacity: existingCapacity,
            registeredCount: existingRegisteredCount,
            comments: existingComments,
            moderationStatus: existingModerationStatus,
            registrationState: existingRegistrationState,
            likeCount: existingLikeCount,
            likeState: existingLikeState
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            if let selectedImageData {
                isUploadingImage = true
                let downloadURL = try await imageUploadService.uploadEventCoverImage(data: selectedImageData, eventID: eventID)
                resolvedImageURL = downloadURL.absoluteString
                isUploadingImage = false
            } else {
                resolvedImageURL = existingImageURL
            }

            let eventToCreate = Event(
                id: newEvent.id,
                title: newEvent.title,
                summary: newEvent.summary,
                details: newEvent.details,
                regionScope: newEvent.regionScope,
                federalState: newEvent.federalState,
                source: newEvent.source,
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

            switch mode {
            case .create:
                try await repository.createEvent(eventToCreate)
                successMessage = AppStrings.Events.publishedSuccessfully
            case .edit:
                try await repository.updateEvent(eventToCreate)
                successMessage = AppStrings.Events.updatedSuccessfully
            }
            AppContentChangeBus.postEventsChanged(organizationID: eventToCreate.source.organizationId)
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
