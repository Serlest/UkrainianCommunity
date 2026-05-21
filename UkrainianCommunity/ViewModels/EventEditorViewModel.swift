import Combine
import CoreLocation
import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    struct CreateContext {
        let organizationId: String?
        let organizationName: String?
        let organizationImageURL: String?
        let organizationFederalState: AustrianFederalState?

        nonisolated static let app = CreateContext(
            organizationId: nil,
            organizationName: nil,
            organizationImageURL: nil,
            organizationFederalState: nil
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

        var isOrganizationEvent: Bool {
            guard let organizationId else { return false }
            return !organizationId.isEmpty
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
    @Published var address = ""
    @Published var locationNote = ""
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var selectedFederalState: AustrianFederalState = .tirol
    @Published var startDate = Date()
    @Published var endDate = Date().addingTimeInterval(60 * 60)
    @Published var selectedCategory: EventCategory = .meetups
    @Published var visibility: EventVisibility = .public
    @Published var isAllDay = false
    @Published var priceText = ""
    @Published var capacityText = ""
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
            address = existingEvent.address ?? ""
            locationNote = existingEvent.locationNote ?? ""
            latitude = existingEvent.latitude
            longitude = existingEvent.longitude
            selectedFederalState = existingEvent.federalState ?? .tirol
            startDate = existingEvent.startDate
            endDate = existingEvent.endDate
            selectedCategory = existingEvent.category
            visibility = existingEvent.visibility
            isAllDay = existingEvent.isAllDay
            priceText = Self.priceText(from: existingEvent.price)
            capacityText = existingEvent.capacity.map(String.init) ?? ""
        }
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedDetails.isEmpty
            && !trimmedCity.isEmpty
            && hasLocationText
            && resolvedFederalState != nil
            && hasValidPrice
            && hasValidCapacity
            && hasValidDateRange
            && hasValidStartDate
            && !isProcessingImage
            && !isUploadingImage
            && !isPublishing
    }

    var navigationTitle: String {
        mode.isEditing ? AppStrings.Events.editTitle : AppStrings.Events.editorTitle
    }

    var isEditing: Bool {
        mode.isEditing
    }

    var showsRegionPicker: Bool {
        isAppLevelEvent
    }

    var requiresOrganizationRegionBeforePublishing: Bool {
        isOrganizationEvent && resolvedFederalState == nil
    }

    var existingImageURL: String? {
        if case let .edit(existingEvent) = mode {
            guard let imageURL = existingEvent.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        }
        return nil
    }

    var organizerName: String? {
        switch mode {
        case let .create(context):
            context.organizationName
        case let .edit(existingEvent):
            existingEvent.source.organizationName
        }
    }

    var organizerImageURL: String? {
        switch mode {
        case let .create(context):
            guard let imageURL = context.organizationImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        case let .edit(existingEvent):
            guard let imageURL = existingEvent.source.organizationImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        }
    }

    var submitButtonTitle: String {
        mode.isEditing ? AppStrings.Events.saveChanges : AppStrings.Events.publish
    }

    var primarySubmitButtonTitle: String {
        mode.isEditing ? AppStrings.Events.primarySaveChanges : AppStrings.Events.primaryPublish
    }

    var selectedCoordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationSearchQuery: String {
        [venue, address, city]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
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

    func applyLocation(
        venueName: String?,
        address: String?,
        city: String?,
        federalState: AustrianFederalState?,
        latitude: Double?,
        longitude: Double?
    ) {
        if let venueName = venueName?.trimmingCharacters(in: .whitespacesAndNewlines), !venueName.isEmpty {
            venue = venueName
        }
        if let address = address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            self.address = address
        }
        if let city = city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            self.city = city
        }
        if let federalState {
            selectedFederalState = federalState
        }
        self.latitude = latitude
        self.longitude = longitude
    }

    func clearResolvedCoordinates() {
        latitude = nil
        longitude = nil
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
        let existingViewCount: Int
        let existingIsBookmarked: Bool
        let existingCapacity: Int?
        let existingRegionScope: RegionScope?
        var eventFederalState: AustrianFederalState?
        let existingSource: ContentSourceMetadata
        let existingAuthorId: String?
        let existingAuthorName: String?
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
            existingViewCount = 0
            existingIsBookmarked = false
            existingCapacity = resolvedCapacity
            existingRegionScope = .federalState
            eventFederalState = context.isOrganizationEvent ? context.organizationFederalState : selectedFederalState
            existingSource = ContentSourceMetadata(sourceType: .app, organizationName: AppStrings.Home.brandTitle)
            existingAuthorId = nil
            existingAuthorName = nil
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
            existingViewCount = existingEvent.viewCount
            existingIsBookmarked = existingEvent.isBookmarked
            existingCapacity = resolvedCapacity
            existingRegionScope = existingEvent.regionScope
            eventFederalState = existingEvent.federalState
            existingSource = existingEvent.source
            existingAuthorId = existingEvent.authorId
            existingAuthorName = existingEvent.authorName
        }
        let normalizedStartDate = normalizedStart
        let normalizedEndDate = normalizedEnd
        await resolveCoordinatesIfNeeded()
        if isAppLevelEvent {
            eventFederalState = selectedFederalState
        }
        var resolvedImageURL: String?
        let newEvent = Event(
            id: eventID,
            title: trimmedTitle,
            summary: resolvedSummary,
            details: trimmedDetails,
            regionScope: existingRegionScope,
            federalState: eventFederalState,
            source: existingSource,
            authorId: existingAuthorId,
            authorName: existingAuthorName,
            city: trimmedCity,
            venue: trimmedVenue,
            address: resolvedAddress,
            locationNote: resolvedLocationNote,
            latitude: latitude,
            longitude: longitude,
            imageURL: nil,
            startDate: normalizedStartDate,
            endDate: normalizedEndDate,
            createdAt: createdAt,
            updatedAt: now,
            price: resolvedPrice,
            capacity: existingCapacity,
            registeredCount: existingRegisteredCount,
            comments: existingComments,
            moderationStatus: existingModerationStatus,
            registrationState: existingRegistrationState,
            likeCount: existingLikeCount,
            likeState: existingLikeState,
            viewCount: existingViewCount,
            category: selectedCategory,
            visibility: .public,
            isAllDay: isAllDay,
            isBookmarked: existingIsBookmarked
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            if let selectedImageData {
                isUploadingImage = true
                logPublishStage("upload image", path: "storage/events/\(eventID)/cover.jpg")
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
                authorId: newEvent.authorId,
                authorName: newEvent.authorName,
                city: newEvent.city,
                venue: newEvent.venue,
                address: newEvent.address,
                locationNote: newEvent.locationNote,
                latitude: newEvent.latitude,
                longitude: newEvent.longitude,
                imageURL: resolvedImageURL,
                startDate: newEvent.startDate,
                endDate: newEvent.endDate,
                createdAt: newEvent.createdAt,
                updatedAt: newEvent.updatedAt,
                price: newEvent.price,
                capacity: newEvent.capacity,
                registeredCount: newEvent.registeredCount,
                comments: newEvent.comments,
                moderationStatus: newEvent.moderationStatus,
                registrationState: newEvent.registrationState,
                likeCount: newEvent.likeCount,
                likeState: newEvent.likeState,
                viewCount: newEvent.viewCount,
                category: newEvent.category,
                visibility: .public,
                isAllDay: newEvent.isAllDay,
                isBookmarked: newEvent.isBookmarked
            )

            switch mode {
            case .create:
                logPublishStage("create event", path: "firestore/events/\(eventToCreate.id)")
                try await repository.createEvent(eventToCreate)
                successMessage = AppStrings.Events.publishedSuccessfully
            case .edit:
                logPublishStage("update event", path: "firestore/events/\(eventToCreate.id)")
                try await repository.updateEvent(eventToCreate)
                successMessage = AppStrings.Events.updatedSuccessfully
            }
            AppContentChangeBus.postEventsChanged(organizationID: eventToCreate.source.organizationId)
            title = ""
            summary = ""
            details = ""
            city = ""
            venue = ""
            address = ""
            locationNote = ""
            latitude = nil
            longitude = nil
            selectedImageData = nil
            startDate = now
            endDate = now.addingTimeInterval(60 * 60)
            selectedCategory = .meetups
            visibility = .public
            isAllDay = false
            priceText = ""
            capacityText = ""
            return true
        } catch {
            isUploadingImage = false
            logPublishFailure(error)
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

    private var resolvedSummary: String {
        let singleLineSummary = trimmedSummary
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        return String(singleLineSummary.prefix(200))
    }

    private var trimmedCity: String {
        city.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedVenue: String {
        venue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasLocationText: Bool {
        !trimmedVenue.isEmpty || !trimmedAddress.isEmpty
    }

    private var resolvedAddress: String? {
        trimmedAddress.isEmpty ? nil : trimmedAddress
    }

    private var trimmedLocationNote: String {
        locationNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedLocationNote: String? {
        trimmedLocationNote.isEmpty ? nil : trimmedLocationNote
    }

    private var trimmedCapacityText: String {
        capacityText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPriceText: String {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedPrice: Double {
        guard !trimmedPriceText.isEmpty else { return 0 }
        return parsedPrice ?? -1
    }

    private var parsedPrice: Double? {
        let normalized = trimmedPriceText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var hasValidPrice: Bool {
        guard !trimmedPriceText.isEmpty else { return true }
        guard let value = parsedPrice else { return false }
        return value >= 0
    }

    private var resolvedCapacity: Int? {
        guard !trimmedCapacityText.isEmpty else { return nil }
        return Int(trimmedCapacityText)
    }

    private var hasValidCapacity: Bool {
        guard !trimmedCapacityText.isEmpty else { return true }
        guard let value = Int(trimmedCapacityText) else { return false }
        return value > 0
    }

    private var normalizedStart: Date {
        isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
    }

    private var normalizedEnd: Date {
        guard isAllDay else { return endDate }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
    }

    private var hasValidDateRange: Bool {
        normalizedEnd > normalizedStart
    }

    private var hasValidStartDate: Bool {
        isEditing || normalizedStart >= Date().addingTimeInterval(-60)
    }

    private var isOrganizationEvent: Bool {
        switch mode {
        case let .create(context):
            return context.isOrganizationEvent
        case let .edit(existingEvent):
            return existingEvent.source.sourceType == .organization
        }
    }

    private var isAppLevelEvent: Bool {
        !isOrganizationEvent
    }

    private var resolvedFederalState: AustrianFederalState? {
        switch mode {
        case let .create(context):
            return context.isOrganizationEvent ? context.organizationFederalState : selectedFederalState
        case let .edit(existingEvent):
            return existingEvent.federalState
        }
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

        guard hasLocationText else {
            errorMessage = AppStrings.Validation.eventVenueRequired
            return false
        }

        guard hasValidDateRange else {
            errorMessage = AppStrings.Events.invalidDateOrder
            return false
        }

        guard hasValidStartDate else {
            errorMessage = AppStrings.Events.startDateInPast
            return false
        }

        guard hasValidCapacity else {
            errorMessage = AppStrings.Events.invalidCapacity
            return false
        }

        guard hasValidPrice else {
            errorMessage = AppStrings.Events.invalidPrice
            return false
        }

        guard resolvedFederalState != nil else {
            errorMessage = AppStrings.Events.organizationRegionRequired
            return false
        }

        return true
    }

    private func resolveCoordinatesIfNeeded() async {
        guard latitude == nil || longitude == nil else { return }

        let locationParts = [trimmedAddress, trimmedVenue, trimmedCity, "Austria"]
            .filter { !$0.isEmpty }
        guard !locationParts.isEmpty else { return }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(locationParts.joined(separator: ", "))
            guard let placemark = placemarks.first,
                  let coordinate = placemark.location?.coordinate else {
                return
            }

            latitude = coordinate.latitude
            longitude = coordinate.longitude

            if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let locality = placemark.locality ?? placemark.subAdministrativeArea {
                city = locality
            }

            if let federalState = AustrianFederalState(administrativeArea: placemark.administrativeArea) {
                selectedFederalState = federalState
            }
        } catch {
            return
        }
    }

    private func logPublishStage(_ stage: String, path: String) {
        print("Event publish stage=\(stage) path=\(path)")
    }

    private func logPublishFailure(_ error: Error) {
        let nsError = error as NSError
        print("Event publish failed domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)")
    }

    private static func priceText(from price: Double) -> String {
        guard price > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }
}

extension AustrianFederalState {
    init?(administrativeArea: String?) {
        guard let value = administrativeArea?.lowercased() else { return nil }
        let normalized = value
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")

        if normalized.contains("burgenland") {
            self = .burgenland
        } else if normalized.contains("kaernten") || normalized.contains("carinthia") {
            self = .kaernten
        } else if normalized.contains("niederoesterreich") || normalized.contains("lower austria") {
            self = .niederoesterreich
        } else if normalized.contains("oberoesterreich") || normalized.contains("upper austria") {
            self = .oberoesterreich
        } else if normalized.contains("salzburg") {
            self = .salzburg
        } else if normalized.contains("steiermark") || normalized.contains("styria") {
            self = .steiermark
        } else if normalized.contains("tirol") || normalized.contains("tyrol") {
            self = .tirol
        } else if normalized.contains("vorarlberg") {
            self = .vorarlberg
        } else if normalized.contains("wien") || normalized.contains("vienna") {
            self = .wien
        } else {
            return nil
        }
    }
}
