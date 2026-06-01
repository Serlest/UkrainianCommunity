import Combine
import CoreLocation
import FirebaseFirestore
import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    static let locationNoteCharacterLimit = 160

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

    @Published var title = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var summary = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var details = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var city = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var venue = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var address = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var locationNote = "" {
        didSet {
            guard locationNote.count > Self.locationNoteCharacterLimit else {
                scheduleCreateDraftAutosave()
                return
            }
            locationNote = String(locationNote.prefix(Self.locationNoteCharacterLimit))
            scheduleCreateDraftAutosave()
        }
    }
    @Published var latitude: Double? {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var longitude: Double? {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var eventOrganizerName = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var organizerURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var contactPhone = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var contactEmail = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var contactURL = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var selectedFederalState: AustrianFederalState = .tirol {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var startDate = Date() {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var endDate = Date().addingTimeInterval(60 * 60) {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var selectedCategory: EventCategory = .meetups {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var tags: [String] = [] {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var tagInput = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var isAllDay = false {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var requiresRegistration = true {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var priceText = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var capacityText = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var isPublishing = false
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published private(set) var pendingRecoveryDraft: EventCreateDraft?
    private var selectedProcessedImage: ProcessedImageSelection?
    @Published private var selectedCreateContext: CreateContext?

    private let repository: EventRepository
    private let draftRecoveryService: LocalDraftRecoveryService
    private let imageUploadService = ImageUploadService.shared
    private let mode: Mode
    private var draftAutosaveTask: Task<Void, Never>?
    private var hasCheckedCreateDraftRecovery = false
    private var isApplyingRecoveredDraft = false
    private var hasMeaningfulCreateDraftMetadata = false

    init(
        repository: EventRepository,
        mode: Mode = .create(),
        draftRecoveryService: LocalDraftRecoveryService? = nil
    ) {
        self.repository = repository
        self.mode = mode
        self.draftRecoveryService = draftRecoveryService ?? .shared

        if case let .create(context) = mode {
            selectedCreateContext = context
        }

        if case let .edit(existingEvent) = mode {
            title = existingEvent.title
            summary = existingEvent.summary
            details = existingEvent.details
            city = existingEvent.city
            venue = existingEvent.venue
            address = existingEvent.address ?? ""
            locationNote = String((existingEvent.locationNote ?? "").prefix(Self.locationNoteCharacterLimit))
            latitude = existingEvent.latitude
            longitude = existingEvent.longitude
            eventOrganizerName = existingEvent.organizerName ?? ""
            organizerURL = existingEvent.organizerURL ?? ""
            contactPhone = existingEvent.contactPhone ?? ""
            contactEmail = existingEvent.contactEmail ?? ""
            contactURL = existingEvent.contactURL ?? ""
            selectedFederalState = existingEvent.federalState ?? .tirol
            startDate = existingEvent.startDate
            endDate = existingEvent.endDate
            selectedCategory = existingEvent.category
            tags = existingEvent.tags
            isAllDay = existingEvent.isAllDay
            requiresRegistration = existingEvent.requiresRegistration
            priceText = Self.priceText(from: existingEvent.price)
            capacityText = existingEvent.capacity.map(String.init) ?? ""
        }
    }

    deinit {
        draftAutosaveTask?.cancel()
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
            && hasOrganizerForCreate
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

    var hasPendingRecoveryDraft: Bool {
        pendingRecoveryDraft != nil
    }

    var shouldConfirmDraftBeforeDismiss: Bool {
        guard isCreateMode else { return false }
        guard !isPublishing, !isUploadingImage, !isProcessingImage else { return false }
        return currentEventCreateDraft().hasMeaningfulContent
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
        publishingOrganizationName
    }

    var publishingOrganizationName: String? {
        switch mode {
        case .create:
            selectedCreateContext?.organizationName
        case let .edit(existingEvent):
            existingEvent.source.organizationName
        }
    }

    var organizerImageURL: String? {
        switch mode {
        case .create:
            guard let imageURL = selectedCreateContext?.organizationImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
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

    var selectedOrganizationId: String? {
        switch mode {
        case .create:
            selectedCreateContext?.organizationId
        case let .edit(existingEvent):
            existingEvent.source.organizationId
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
            selectedProcessedImage = nil
            return
        }

        successMessage = nil
        errorMessage = nil
        selectedImageData = data
        selectedProcessedImage = nil
    }

    func setSelectedImageSelection(_ selection: ProcessedImageSelection?) {
        selectedProcessedImage = selection
        selectedImageData = selection?.data
        successMessage = nil
        errorMessage = nil
    }

    func setImageProcessing(_ isProcessing: Bool) {
        isProcessingImage = isProcessing
    }

    func setStartDateComponent(_ dateValue: Date) {
        startDate = Self.combinedDate(dateFrom: dateValue, timeFrom: startDate)
        correctDateRangeAfterStartChange()
    }

    func setStartTimeComponent(_ timeValue: Date) {
        startDate = Self.combinedDate(dateFrom: startDate, timeFrom: timeValue)
        correctDateRangeAfterStartChange()
    }

    func setEndDateComponent(_ dateValue: Date) {
        endDate = Self.combinedDate(dateFrom: dateValue, timeFrom: endDate)
        correctDateRangeAfterEndChange()
    }

    func setEndTimeComponent(_ timeValue: Date) {
        endDate = Self.combinedDate(dateFrom: endDate, timeFrom: timeValue)
        correctDateRangeAfterEndChange()
    }

    func setAllDay(_ isAllDay: Bool) {
        self.isAllDay = isAllDay
        correctDateRangeAfterEndChange()
    }

    func selectOrganizer(_ organization: Organization) {
        guard case .create = mode else { return }
        selectedCreateContext = CreateContext(
            organizationId: organization.id,
            organizationName: organization.name,
            organizationImageURL: organization.imageURL,
            organizationFederalState: organization.federalState
        )
        if currentEventCreateDraft().hasMeaningfulContent {
            scheduleCreateDraftAutosave()
        }
    }

    func loadRecoverableDraftIfNeeded() async {
        guard isCreateMode, !hasCheckedCreateDraftRecovery else { return }
        hasCheckedCreateDraftRecovery = true

        do {
            guard let draft = try await draftRecoveryService.loadEventCreateDraft(key: createDraftStorageKey),
                  draft.hasMeaningfulContent else {
                pendingRecoveryDraft = nil
                return
            }
            pendingRecoveryDraft = draft
        } catch {
            pendingRecoveryDraft = nil
        }
    }

    func continueRecoveredDraft() {
        guard let draft = pendingRecoveryDraft, isCreateMode else { return }
        applyRecoveredDraft(draft)
        pendingRecoveryDraft = nil
    }

    func createNewInsteadOfRecoveredDraft() async {
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
    }

    func deleteRecoveredDraft() async {
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
    }

    func saveDraftBeforeClosing() async {
        await saveCurrentCreateDraftIfNeeded()
    }

    func discardCreateDraft() async {
        draftAutosaveTask?.cancel()
        pendingRecoveryDraft = nil
        hasMeaningfulCreateDraftMetadata = false
        try? await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
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

    func addTagFromInput() {
        addTag(tagInput)
        tagInput = ""
    }

    func addTag(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        tags.append(trimmed)
    }

    func removeTag(_ tag: String) {
        tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
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
        let existingCommentCount: Int
        let existingCapacity: Int?
        let existingRegionScope: RegionScope?
        var eventFederalState: AustrianFederalState?
        let existingSource: ContentSourceMetadata
        let existingAuthorId: String?
        let existingAuthorName: String?
        switch mode {
        case .create:
            let context = selectedCreateContext ?? .app
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
            existingCommentCount = 0
            existingCapacity = resolvedCapacity
            existingRegionScope = .federalState
            eventFederalState = context.isOrganizationEvent ? context.organizationFederalState : selectedFederalState
            existingSource = context.isOrganizationEvent
                ? context.source
                : ContentSourceMetadata(sourceType: .app, organizationName: AppStrings.Home.brandTitle)
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
            existingCommentCount = existingEvent.commentCount
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
        let resolvedEventOrganizerName = resolvedOrganizerName()
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
            organizerName: resolvedEventOrganizerName,
            organizerURL: resolvedOrganizerURL,
            contactPhone: resolvedContactPhone,
            contactEmail: resolvedContactEmail,
            contactURL: resolvedContactURL,
            imageURL: nil,
            startDate: normalizedStartDate,
            endDate: normalizedEndDate,
            createdAt: createdAt,
            updatedAt: now,
            requiresRegistration: requiresRegistration,
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
            tags: tags,
            isAllDay: isAllDay,
            isBookmarked: existingIsBookmarked,
            commentCount: existingCommentCount
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            switch mode {
            case .create:
                try await repository.createEvent(newEvent)

                if selectedImageData != nil {
                    isUploadingImage = true
                    var uploadedDraftImage = false
                    let organizationID = newEvent.source.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    do {
                        let downloadURL: URL
                        if !organizationID.isEmpty {
                            if let selectedProcessedImage {
                                downloadURL = try await imageUploadService.uploadOrganizationEventDraftImage(
                                    processedImage: selectedProcessedImage,
                                    organizationID: organizationID,
                                    eventID: eventID
                                )
                            } else if let selectedImageData {
                                downloadURL = try await imageUploadService.uploadOrganizationEventDraftImage(
                                    data: selectedImageData,
                                    organizationID: organizationID,
                                    eventID: eventID
                                )
                            } else {
                                throw AppError.validationFailed
                            }
                            uploadedDraftImage = true
                        } else if let selectedProcessedImage {
                            downloadURL = try await imageUploadService.uploadEventCoverImage(processedImage: selectedProcessedImage, eventID: eventID)
                        } else if let selectedImageData {
                            downloadURL = try await imageUploadService.uploadEventCoverImage(data: selectedImageData, eventID: eventID)
                        } else {
                            throw AppError.validationFailed
                        }
                        try await repository.updateEventImageURL(id: eventID, imageURL: downloadURL.absoluteString)
                    } catch let uploadError {
                        isUploadingImage = false
                        if uploadedDraftImage, !organizationID.isEmpty {
                            try? await imageUploadService.deleteOrganizationEventDraftImage(
                                organizationID: organizationID,
                                eventID: eventID
                            )
                        }
                        do {
                            try await rollbackCreatedEvent(id: newEvent.id)
                            errorMessage = uploadError.localizedDescription
                        } catch {
                            errorMessage = "\(uploadError.localizedDescription) \(error.localizedDescription)"
                        }
                        return false
                    }
                    isUploadingImage = false
                }

                successMessage = AppStrings.Events.publishedSuccessfully
            case .edit:
                var resolvedImageURL = existingImageURL
                if selectedImageData != nil {
                    isUploadingImage = true
                    let downloadURL: URL
                    if let selectedProcessedImage {
                        downloadURL = try await imageUploadService.uploadEventCoverImage(processedImage: selectedProcessedImage, eventID: eventID)
                    } else if let selectedImageData {
                        downloadURL = try await imageUploadService.uploadEventCoverImage(data: selectedImageData, eventID: eventID)
                    } else {
                        throw AppError.validationFailed
                    }
                    resolvedImageURL = downloadURL.absoluteString
                    isUploadingImage = false
                }

                try await repository.updateEvent(newEvent.settingImageURL(resolvedImageURL))
                successMessage = AppStrings.Events.updatedSuccessfully
            }

            AppContentChangeBus.postEventsChanged(organizationID: newEvent.source.organizationId)
            if isCreateMode {
                draftAutosaveTask?.cancel()
                try? await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
            }
            hasMeaningfulCreateDraftMetadata = false
            title = ""
            summary = ""
            details = ""
            city = ""
            venue = ""
            address = ""
            locationNote = ""
            latitude = nil
            longitude = nil
            eventOrganizerName = ""
            organizerURL = ""
            contactPhone = ""
            contactEmail = ""
            contactURL = ""
            selectedImageData = nil
            selectedProcessedImage = nil
            startDate = now
            endDate = now.addingTimeInterval(60 * 60)
            selectedCategory = .meetups
            tags = []
            tagInput = ""
            isAllDay = false
            requiresRegistration = true
            priceText = ""
            capacityText = ""
            return true
        } catch {
            isUploadingImage = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func rollbackCreatedEvent(id: String) async throws {
        try await Firestore.firestore().collection("events").document(id).delete()
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
        trimmedLocationNote.isEmpty ? nil : String(trimmedLocationNote.prefix(Self.locationNoteCharacterLimit))
    }

    private func resolvedOrganizerName() -> String? {
        let trimmedOrganizerName = eventOrganizerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOrganizerName.isEmpty {
            return trimmedOrganizerName
        }

        return nil
    }

    private var resolvedOrganizerURL: String? {
        normalizedURLString(from: organizerURL)
    }

    private var resolvedContactPhone: String? {
        contactPhone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventEditor
    }

    private var resolvedContactEmail: String? {
        contactEmail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForEventEditor
    }

    private var resolvedContactURL: String? {
        normalizedURLString(from: contactURL)
    }

    private func normalizedURLString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host?.isEmpty == false {
            return url.absoluteString
        }

        guard !trimmed.contains("://"), trimmed.contains("."),
              let url = URL(string: "https://\(trimmed)"),
              url.host?.isEmpty == false else {
            return trimmed
        }

        return url.absoluteString
    }

    private var trimmedCapacityText: String {
        capacityText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPriceText: String {
        priceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedPrice: Double {
        guard requiresRegistration else { return 0 }
        guard !trimmedPriceText.isEmpty else { return 0 }
        return parsedPrice ?? -1
    }

    private var parsedPrice: Double? {
        let normalized = trimmedPriceText.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private var hasValidPrice: Bool {
        guard requiresRegistration else { return true }
        guard !trimmedPriceText.isEmpty else { return true }
        guard let value = parsedPrice else { return false }
        return value >= 0
    }

    private var resolvedCapacity: Int? {
        guard requiresRegistration else { return nil }
        guard !trimmedCapacityText.isEmpty else { return nil }
        return Int(trimmedCapacityText)
    }

    private var hasValidCapacity: Bool {
        guard requiresRegistration else { return true }
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

    private var hasChronologicalDateRange: Bool {
        guard !isAllDay else {
            return Calendar.current.startOfDay(for: endDate) >= Calendar.current.startOfDay(for: startDate)
        }

        return endDate > startDate
    }

    private var hasValidStartDate: Bool {
        isEditing || normalizedStart >= Date().addingTimeInterval(-60)
    }

    private var hasOrganizerForCreate: Bool {
        isEditing || (selectedCreateContext?.isOrganizationEvent ?? false)
    }

    private var isOrganizationEvent: Bool {
        switch mode {
        case .create:
            return selectedCreateContext?.isOrganizationEvent ?? false
        case let .edit(existingEvent):
            return existingEvent.source.sourceType == .organization
        }
    }

    private var isAppLevelEvent: Bool {
        !isOrganizationEvent
    }

    private var isCreateMode: Bool {
        if case .create = mode {
            return true
        }
        return false
    }

    private var createDraftStorageKey: String {
        guard case .create = mode else {
            return "event-create-edit-ignored"
        }

        let organizationID = selectedCreateContext?.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !organizationID.isEmpty else {
            return "event-create"
        }
        return "event-create-organization-\(organizationID)"
    }

    private func scheduleCreateDraftAutosave() {
        guard isCreateMode, !isApplyingRecoveredDraft else { return }
        guard !isPublishing, !isUploadingImage, !isProcessingImage else { return }

        draftAutosaveTask?.cancel()
        draftAutosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await self?.saveCurrentCreateDraftIfNeeded()
        }
    }

    private func markCreateDraftMetadataChanged() {
        guard isCreateMode, !isApplyingRecoveredDraft else { return }
        guard !isPublishing, !isUploadingImage, !isProcessingImage else { return }
        hasMeaningfulCreateDraftMetadata = true
        scheduleCreateDraftAutosave()
    }

    private func saveCurrentCreateDraftIfNeeded() async {
        guard isCreateMode else { return }
        guard !isPublishing, !isUploadingImage, !isProcessingImage else { return }

        let draft = currentEventCreateDraft()
        do {
            if draft.hasMeaningfulContent {
                try await draftRecoveryService.saveEventCreateDraft(draft, key: createDraftStorageKey)
            } else {
                try await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
            }
        } catch {
            // Draft recovery is best-effort and must not block event publishing.
        }
    }

    private func currentEventCreateDraft(updatedAt: Date = Date()) -> EventCreateDraft {
        EventCreateDraft(
            version: EventCreateDraft.currentVersion,
            hasMeaningfulMetadata: hasMeaningfulCreateDraftMetadata,
            updatedAt: updatedAt,
            organizationId: selectedCreateContext?.organizationId,
            organizationName: selectedCreateContext?.organizationName,
            organizationImageURL: selectedCreateContext?.organizationImageURL,
            organizationFederalState: selectedCreateContext?.organizationFederalState,
            title: title,
            summary: summary,
            details: details,
            city: city,
            venue: venue,
            address: address,
            locationNote: locationNote,
            latitude: latitude,
            longitude: longitude,
            eventOrganizerName: eventOrganizerName,
            organizerURL: organizerURL,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactURL: contactURL,
            selectedFederalState: selectedFederalState,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            selectedCategory: selectedCategory,
            tags: tags,
            tagInput: tagInput,
            requiresRegistration: requiresRegistration,
            priceText: priceText,
            capacityText: capacityText
        )
    }

    private func applyRecoveredDraft(_ draft: EventCreateDraft) {
        isApplyingRecoveredDraft = true

        if let organizationId = draft.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines), !organizationId.isEmpty {
            selectedCreateContext = CreateContext(
                organizationId: organizationId,
                organizationName: draft.organizationName,
                organizationImageURL: draft.organizationImageURL,
                organizationFederalState: draft.organizationFederalState
            )
        }

        title = draft.title
        summary = draft.summary
        details = draft.details
        city = draft.city
        venue = draft.venue
        address = draft.address
        locationNote = draft.locationNote
        latitude = draft.latitude
        longitude = draft.longitude
        eventOrganizerName = draft.eventOrganizerName
        organizerURL = draft.organizerURL
        contactPhone = draft.contactPhone
        contactEmail = draft.contactEmail
        contactURL = draft.contactURL
        selectedFederalState = draft.selectedFederalState
        startDate = draft.startDate
        endDate = draft.endDate
        isAllDay = draft.isAllDay
        selectedCategory = draft.selectedCategory
        tags = draft.tags
        tagInput = draft.tagInput
        requiresRegistration = draft.requiresRegistration
        priceText = draft.priceText
        capacityText = draft.capacityText
        hasMeaningfulCreateDraftMetadata = draft.hasMeaningfulMetadata == true

        isApplyingRecoveredDraft = false
    }

    private var resolvedFederalState: AustrianFederalState? {
        switch mode {
        case .create:
            guard let selectedCreateContext, selectedCreateContext.isOrganizationEvent else {
                return selectedFederalState
            }
            return selectedCreateContext.organizationFederalState
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

        guard hasChronologicalDateRange else {
            errorMessage = AppStrings.Events.invalidDateOrder
            return false
        }

        guard hasValidStartDate else {
            errorMessage = AppStrings.Events.startDateInPast
            return false
        }

        guard hasOrganizerForCreate else {
            errorMessage = AppStrings.Events.organizationRequired
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

    private func correctDateRangeAfterStartChange() {
        if isAllDay {
            if Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: startDate) {
                endDate = Self.combinedDate(dateFrom: startDate, timeFrom: endDate)
            }
            return
        }

        if endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
        }
    }

    private func correctDateRangeAfterEndChange() {
        if isAllDay {
            if Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: startDate) {
                endDate = Self.combinedDate(dateFrom: startDate, timeFrom: endDate)
            }
            return
        }

        if endDate <= startDate {
            endDate = Calendar.current.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
        }
    }

    private static func combinedDate(dateFrom dateValue: Date, timeFrom timeValue: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: dateValue)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeValue)

        var components = DateComponents()
        components.year = dateComponents.year
        components.month = dateComponents.month
        components.day = dateComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second ?? 0

        return calendar.date(from: components) ?? dateValue
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

private extension Event {
    func settingImageURL(_ imageURL: String?) -> Event {
        Event(
            id: id,
            title: title,
            summary: summary,
            details: details,
            regionScope: regionScope,
            federalState: federalState,
            source: source,
            authorId: authorId,
            authorName: authorName,
            city: city,
            venue: venue,
            address: address,
            locationNote: locationNote,
            latitude: latitude,
            longitude: longitude,
            organizerName: organizerName,
            organizerURL: organizerURL,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactURL: contactURL,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            requiresRegistration: requiresRegistration,
            price: price,
            capacity: capacity,
            registeredCount: registeredCount,
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: registrationState,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            category: category,
            tags: tags,
            isAllDay: isAllDay,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
    }
}

private extension String {
    var nilIfBlankForEventEditor: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
