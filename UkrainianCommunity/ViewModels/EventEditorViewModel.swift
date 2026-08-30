import Combine
import CoreLocation
import Foundation

@MainActor
final class EventEditorViewModel: ObservableObject {
    static let maximumOccurrenceCount = 30
    static let localizedTitleLimit = 120
    static let localizedSummaryLimit = 200
    static let localizedDetailsLimit = 2_000
    static let externalActionTitleLimit = 120
    static let externalActionURLLimit = 2_048
    static let priceNoteLimit = 500
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
    @Published var germanTitle = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanSummary = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var germanDetails = "" { didSet { scheduleCreateDraftAutosave() } }
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
    @Published var hasExplicitEndDate = true {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var additionalOccurrences: [EventOccurrence] = [] { didSet { scheduleCreateDraftAutosave() } }
    @Published var selectedCategory: EventCategory = .meetups {
        didSet {
            additionalCategories.removeAll { $0 == selectedCategory }
            markCreateDraftMetadataChanged()
        }
    }
    @Published var additionalCategories: [EventCategory] = [] {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var selectedAudience: EventAudience = .everyone {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var minimumAgeText = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var maximumAgeText = "" {
        didSet { scheduleCreateDraftAutosave() }
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
    @Published var participationMode: EventParticipationMode = .inAppRegistration {
        didSet {
            requiresRegistration = participationMode.usesInAppRegistration
            markCreateDraftMetadataChanged()
        }
    }
    @Published var externalActionTitle = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var externalActionURL = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var priceKind: EventPriceKind = .free { didSet { markCreateDraftMetadataChanged() } }
    @Published var maximumPriceText = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var priceNote = "" { didSet { scheduleCreateDraftAutosave() } }
    @Published var priceText = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var capacityText = "" {
        didSet { scheduleCreateDraftAutosave() }
    }
    @Published var publicationMode: ContentPublicationMode = .now {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var scheduledAt = Date().addingTimeInterval(60 * 60) {
        didSet { markCreateDraftMetadataChanged() }
    }
    @Published var isPublishing = false
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published private(set) var lastPublicationResult: ContentPlanningPublicationResult?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published private(set) var pendingRecoveryDraft: EventCreateDraft?
    private var selectedProcessedImage: ProcessedImageSelection?
    private var generatedImageURL: String?
    @Published private var selectedCreateContext: CreateContext?

    private let repository: EventRepository
    private let validationService = EventValidationService()
    private let draftRecoveryService: LocalDraftRecoveryService
    private let imageUploadService = ImageUploadService.shared
    private let mode: Mode
    private let sourceDraftID: String?
    private var draftAutosaveTask: Task<Void, Never>?
    private var hasCheckedCreateDraftRecovery = false
    private var hasCompletedCreateDraftRecoveryCheck = false
    private var isApplyingRecoveredDraft = false
    private var hasMeaningfulCreateDraftMetadata = false

    init(
        repository: EventRepository,
        mode: Mode = .create(),
        sourceDraft: OwnerContentDraft? = nil,
        draftRecoveryService: LocalDraftRecoveryService? = nil
    ) {
        self.repository = repository
        self.mode = mode
        self.sourceDraftID = sourceDraft?.id
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
            let primaryOccurrence = existingEvent.occurrences.first
            startDate = primaryOccurrence?.startDate ?? existingEvent.startDate
            endDate = primaryOccurrence?.endDate ?? existingEvent.endDate
            hasExplicitEndDate = endDate > startDate
            additionalOccurrences = Array(existingEvent.occurrences.dropFirst())
            selectedCategory = existingEvent.category
            additionalCategories = existingEvent.additionalCategories
            selectedAudience = existingEvent.audience
            minimumAgeText = existingEvent.minimumAge.map(String.init) ?? ""
            maximumAgeText = existingEvent.maximumAge.map(String.init) ?? ""
            tags = existingEvent.tags
            isAllDay = existingEvent.isAllDay
            requiresRegistration = existingEvent.requiresRegistration
            participationMode = existingEvent.participationMode
            externalActionTitle = existingEvent.externalAction?.title ?? ""
            externalActionURL = existingEvent.externalAction?.url ?? ""
            priceKind = existingEvent.pricing.kind
            maximumPriceText = Self.priceText(from: existingEvent.pricing.maximumAmount ?? 0)
            priceNote = existingEvent.pricing.note ?? ""
            priceText = Self.priceText(from: existingEvent.price)
            capacityText = existingEvent.capacity.map(String.init) ?? ""
            if let existingScheduledAt = existingEvent.scheduledAt {
                publicationMode = .scheduled
                scheduledAt = existingScheduledAt
            }
        }

        if case .create = mode, let draft = sourceDraft?.eventDraft {
            applyRecoveredDraft(draft)
            hasMeaningfulCreateDraftMetadata = true
            hasCheckedCreateDraftRecovery = true
            hasCompletedCreateDraftRecoveryCheck = true
        }
    }

    deinit {
        draftAutosaveTask?.cancel()
    }

    var canPublish: Bool {
        validationIssue == nil
            && isValidSchedule
            && isValidPublishingMetadata
            && isValidGermanContent
            && !isProcessingImage
            && !isUploadingImage
            && !isPublishing
    }

    var validationMessage: String? {
        validationIssue?.message ?? (isValidPublishingMetadata && isValidGermanContent ? nil : ContentPublishingStrings.publishingFieldsTooLong)
    }

    var canAdvanceBasics: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedDetails.isEmpty
            && isValidGermanContent
    }

    var canAdvanceSchedule: Bool {
        guard !trimmedCity.isEmpty,
              !trimmedVenue.isEmpty || !trimmedAddress.isEmpty else {
            return false
        }

        let primaryIsValid: Bool
        if !hasExplicitEndDate {
            let start = isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
            primaryIsValid = isEditing || start >= (isAllDay ? Calendar.current.startOfDay(for: Date()) : Date().addingTimeInterval(-60))
        } else if isAllDay {
            let start = Calendar.current.startOfDay(for: startDate)
            let end = Calendar.current.startOfDay(for: endDate)
            primaryIsValid = end >= start && (isEditing || start >= Calendar.current.startOfDay(for: Date()))
        } else {
            primaryIsValid = endDate > startDate && (isEditing || startDate >= Date().addingTimeInterval(-60))
        }

        guard primaryIsValid, allOccurrences.count <= Self.maximumOccurrenceCount else { return false }
        let earliestAllowedDate = Calendar.current.startOfDay(for: Date())
        return additionalOccurrences.allSatisfy { occurrence in
            occurrence.isValid && (isEditing || occurrence.startDate >= earliestAllowedDate)
        }
    }

    var canAdvanceAudience: Bool {
        guard !requiresOrganizationRegionBeforePublishing, isValidPublishingMetadata else { return false }
        guard !requiresRegistration || Self.isValidPositiveIntegerOrBlank(capacityText) else { return false }
        guard isValidPricing, isValidExternalParticipation else { return false }
        guard Self.isValidAgeOrBlank(minimumAgeText), Self.isValidAgeOrBlank(maximumAgeText) else { return false }

        if let minimumAge = resolvedMinimumAge, let maximumAge = resolvedMaximumAge {
            return maximumAge >= minimumAge
        }
        return true
    }

    var allOccurrences: [EventOccurrence] {
        [EventOccurrence(startDate: normalizedStart, endDate: normalizedEnd, isAllDay: isAllDay)]
            + additionalOccurrences.sorted { $0.startDate < $1.startDate }
    }

    var previewEvent: Event {
        let now = Date()
        let source = selectedCreateContext?.source ?? ContentSourceMetadata(sourceType: .organization, organizationName: publishingOrganizationName)
        let pricing = resolvedPricing
        return Event(
            id: "preview",
            schemaVersion: 2,
            localizations: resolvedLocalizations,
            title: trimmedTitle,
            summary: resolvedSummary,
            details: trimmedDetails,
            federalState: resolvedFederalState,
            source: source,
            city: trimmedCity,
            venue: trimmedVenue,
            address: resolvedAddress,
            locationNote: resolvedLocationNote,
            imageURL: existingImageURL,
            startDate: normalizedStart,
            endDate: normalizedEnd,
            occurrences: allOccurrences,
            createdAt: now,
            updatedAt: now,
            requiresRegistration: participationMode.usesInAppRegistration,
            participationMode: participationMode,
            externalAction: resolvedExternalAction,
            price: pricing.amount ?? 0,
            pricing: pricing,
            capacity: resolvedCapacity,
            registeredCount: 0,
            comments: [],
            moderationStatus: .approved,
            registrationState: .notRegistered,
            likeCount: 0,
            likeState: .notLiked,
            category: selectedCategory,
            additionalCategories: additionalCategories,
            audience: selectedAudience,
            minimumAge: resolvedMinimumAge,
            maximumAge: resolvedMaximumAge,
            tags: tags,
            isAllDay: isAllDay
        )
    }

    var isValidExternalParticipation: Bool {
        guard participationMode.requiresExternalURL else { return true }
        return ExternalContentAction(url: externalActionURL).webURL != nil
    }

    private var isValidGermanContent: Bool {
        germanTitle.count <= Self.localizedTitleLimit
            && germanSummary.count <= Self.localizedSummaryLimit
            && germanDetails.count <= Self.localizedDetailsLimit
    }

    private var isValidPublishingMetadata: Bool {
        externalActionTitle.count <= Self.externalActionTitleLimit
            && externalActionURL.count <= Self.externalActionURLLimit
            && priceNote.count <= Self.priceNoteLimit
            && allOccurrences.count <= Self.maximumOccurrenceCount
    }

    var isValidPricing: Bool {
        switch priceKind {
        case .unspecified, .free:
            return true
        case .exact, .startingFrom:
            return Self.isValidNonNegativeDecimalOrBlank(priceText) && parsedPrice != nil
        case .range:
            guard let minimum = parsedPrice,
                  let maximum = parsedMaximumPrice else { return false }
            return minimum >= 0 && maximum >= minimum
        }
    }

    func addOccurrence() {
        guard allOccurrences.count < Self.maximumOccurrenceCount else { return }
        let previous = additionalOccurrences.last ?? EventOccurrence(
            startDate: normalizedStart,
            endDate: normalizedEnd,
            isAllDay: isAllDay
        )
        let nextStart = Calendar.current.date(byAdding: .day, value: 1, to: previous.startDate) ?? previous.startDate
        let nextEnd = Calendar.current.date(byAdding: .day, value: 1, to: previous.endDate) ?? previous.endDate
        additionalOccurrences.append(EventOccurrence(startDate: nextStart, endDate: nextEnd, isAllDay: previous.isAllDay))
    }

    func updateOccurrence(
        id: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        hasExplicitEndDate: Bool? = nil,
        isAllDay: Bool? = nil
    ) {
        guard let index = additionalOccurrences.firstIndex(where: { $0.id == id }) else { return }
        let current = additionalOccurrences[index]
        let resolvedIsAllDay = isAllDay ?? current.isAllDay
        let resolvedHasExplicitEndDate = hasExplicitEndDate ?? (endDate.map { $0 > (startDate ?? current.startDate) } ?? (current.endDate > current.startDate))
        var resolvedStart = startDate ?? current.startDate
        var resolvedEnd = resolvedHasExplicitEndDate ? (endDate ?? current.endDate) : resolvedStart
        if resolvedIsAllDay && resolvedHasExplicitEndDate {
            resolvedStart = Calendar.current.startOfDay(for: resolvedStart)
            let endDay = Calendar.current.startOfDay(for: resolvedEnd)
            resolvedEnd = Calendar.current.date(byAdding: .day, value: 1, to: max(resolvedStart, endDay)) ?? resolvedEnd
        } else if resolvedIsAllDay {
            resolvedStart = Calendar.current.startOfDay(for: resolvedStart)
            resolvedEnd = resolvedStart
        }
        let replacement = EventOccurrence(
            id: current.id,
            startDate: resolvedStart,
            endDate: resolvedEnd,
            isAllDay: resolvedIsAllDay,
            status: current.status
        )
        guard replacement.isValid else { return }
        additionalOccurrences[index] = replacement
    }

    func removeOccurrence(id: String) {
        additionalOccurrences.removeAll { $0.id == id }
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
        return generatedImageURL
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
        if mode.isEditing { return AppStrings.Events.primarySaveChanges }
        return publicationMode == .scheduled
            ? AppStrings.ContentPublishing.scheduleAction
            : AppStrings.Events.primaryPublish
    }

    var isValidSchedule: Bool {
        !isCreateMode || publicationMode == .now || scheduledAt >= Date().addingTimeInterval(5 * 60)
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
        generatedImageURL = nil
    }

    func setSelectedImageSelection(_ selection: ProcessedImageSelection?) {
        selectedProcessedImage = selection
        selectedImageData = selection?.data
        if selection != nil { generatedImageURL = nil }
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
            organizationName: organization.localizedName,
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
        defer {
            hasCompletedCreateDraftRecoveryCheck = true
            if pendingRecoveryDraft == nil, currentEventCreateDraft().hasMeaningfulContent {
                scheduleCreateDraftAutosave()
            }
        }

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
        lastPublicationResult = nil
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
            existingModerationStatus = publicationMode == .scheduled ? .draft : .approved
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
        let localizations = resolvedLocalizations
        let eventPricing = resolvedPricing
        let externalAction = resolvedExternalAction
        let newEvent = Event(
            id: eventID,
            schemaVersion: 2,
            localizations: localizations,
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
            occurrences: allOccurrences,
            createdAt: createdAt,
            updatedAt: now,
            scheduledAt: isCreateMode && publicationMode == .scheduled ? scheduledAt : nil,
            requiresRegistration: participationMode.usesInAppRegistration,
            participationMode: participationMode,
            externalAction: externalAction,
            price: eventPricing.amount ?? 0,
            pricing: eventPricing,
            capacity: existingCapacity,
            registeredCount: existingRegisteredCount,
            comments: existingComments,
            moderationStatus: existingModerationStatus,
            registrationState: existingRegistrationState,
            likeCount: existingLikeCount,
            likeState: existingLikeState,
            viewCount: existingViewCount,
            category: selectedCategory,
            additionalCategories: additionalCategories,
            audience: selectedAudience,
            minimumAge: resolvedMinimumAge,
            maximumAge: resolvedMaximumAge,
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
                let generatedImageData = try await downloadGeneratedImageIfNeeded()
                try await repository.createEvent(newEvent)

                if selectedImageData != nil || generatedImageData != nil {
                    isUploadingImage = true
                    do {
                        let downloadURL: URL
                        if let selectedProcessedImage {
                            downloadURL = try await imageUploadService.uploadEventCoverImage(processedImage: selectedProcessedImage, eventID: eventID)
                        } else if let imageData = selectedImageData ?? generatedImageData {
                            downloadURL = try await imageUploadService.uploadEventCoverImage(data: imageData, eventID: eventID)
                        } else {
                            throw AppError.validationFailed
                        }
                        guard !downloadURL.absoluteString.isEmpty else {
                            throw AppError.unknown
                        }
                    } catch let uploadError {
                        isUploadingImage = false
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

                successMessage = publicationMode == .scheduled
                    ? AppStrings.ContentPublishing.scheduledSuccessfully
                    : AppStrings.Events.publishedSuccessfully
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
            lastPublicationResult = ContentPlanningPublicationResult(
                kind: .event,
                contentID: newEvent.id,
                scheduledAt: isCreateMode && publicationMode == .scheduled ? scheduledAt : nil
            )
            if isCreateMode {
                draftAutosaveTask?.cancel()
                try? await draftRecoveryService.deleteEventCreateDraft(key: createDraftStorageKey)
            }
            hasMeaningfulCreateDraftMetadata = false
            title = ""
            summary = ""
            details = ""
            germanTitle = ""
            germanSummary = ""
            germanDetails = ""
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
            hasExplicitEndDate = true
            additionalOccurrences = []
            selectedCategory = .meetups
            additionalCategories = []
            selectedAudience = .everyone
            minimumAgeText = ""
            maximumAgeText = ""
            tags = []
            tagInput = ""
            isAllDay = false
            requiresRegistration = true
            participationMode = .inAppRegistration
            externalActionTitle = ""
            externalActionURL = ""
            priceKind = .free
            priceText = ""
            maximumPriceText = ""
            priceNote = ""
            capacityText = ""
            return true
        } catch {
            isUploadingImage = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func rollbackCreatedEvent(id: String) async throws {
        try await repository.deleteEvent(id: id)
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

    private var parsedMaximumPrice: Double? {
        Double(maximumPriceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var resolvedLocalizations: [String: EventLocalizedContent] {
        var result = [PublishedContentLanguage.ukrainian.rawValue: EventLocalizedContent(
            title: trimmedTitle,
            summary: resolvedSummary,
            details: trimmedDetails
        )]
        if [germanTitle, germanSummary, germanDetails].contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            result[PublishedContentLanguage.german.rawValue] = EventLocalizedContent(
                title: germanTitle.trimmedOrFallback(trimmedTitle),
                summary: germanSummary.trimmedOrFallback(resolvedSummary),
                details: germanDetails.trimmedOrFallback(trimmedDetails)
            )
        }
        return result
    }

    private var resolvedPricing: EventPricing {
        EventPricing(
            kind: priceKind,
            amount: [.exact, .startingFrom, .range].contains(priceKind) ? parsedPrice : nil,
            maximumAmount: priceKind == .range ? parsedMaximumPrice : nil,
            note: priceNote
        )
    }

    private var resolvedExternalAction: ExternalContentAction? {
        guard participationMode.requiresExternalURL else { return nil }
        return ExternalContentAction(title: externalActionTitle, url: externalActionURL)
    }

    private var resolvedCapacity: Int? {
        guard requiresRegistration else { return nil }
        guard !trimmedCapacityText.isEmpty else { return nil }
        return Int(trimmedCapacityText)
    }

    private var resolvedMinimumAge: Int? {
        Int(minimumAgeText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var resolvedMaximumAge: Int? {
        Int(maximumAgeText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var normalizedStart: Date {
        isAllDay ? Calendar.current.startOfDay(for: startDate) : startDate
    }

    private var normalizedEnd: Date {
        guard hasExplicitEndDate else { return normalizedStart }
        guard isAllDay else { return endDate }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endDate)) ?? endDate
    }

    private var hasOrganizerForCreate: Bool {
        isEditing || (selectedCreateContext?.isOrganizationEvent ?? false)
    }

    private var validationIssue: EventValidationIssue? {
        validationService.firstIssue(
            in: EventValidationInput(
                title: title,
                summary: summary,
                details: details,
                city: city,
                venue: venue,
                address: address,
                startDate: startDate,
                endDate: endDate,
                hasExplicitEndDate: hasExplicitEndDate,
                isAllDay: isAllDay,
                isEditing: isEditing,
                hasOrganizer: hasOrganizerForCreate,
                requiresRegistration: requiresRegistration,
                capacityText: capacityText,
                priceText: priceText,
                minimumAgeText: minimumAgeText,
                maximumAgeText: maximumAgeText,
                federalState: resolvedFederalState
            )
        )
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

        if let sourceDraftID {
            return "event-owner-content-\(sourceDraftID)"
        }

        let organizationID = selectedCreateContext?.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !organizationID.isEmpty else {
            return "event-create"
        }
        return "event-create-organization-\(organizationID)"
    }

    private func scheduleCreateDraftAutosave() {
        guard isCreateMode, !isApplyingRecoveredDraft else { return }
        guard hasCompletedCreateDraftRecoveryCheck else { return }
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
            hasExplicitEndDate: hasExplicitEndDate,
            isAllDay: isAllDay,
            selectedCategory: selectedCategory,
            additionalCategories: additionalCategories,
            selectedAudience: selectedAudience,
            minimumAgeText: minimumAgeText,
            maximumAgeText: maximumAgeText,
            tags: tags,
            tagInput: tagInput,
            requiresRegistration: requiresRegistration,
            priceText: priceText,
            capacityText: capacityText,
            germanTitle: germanTitle,
            germanSummary: germanSummary,
            germanDetails: germanDetails,
            additionalOccurrences: additionalOccurrences,
            participationMode: participationMode,
            externalActionTitle: externalActionTitle,
            externalActionURL: externalActionURL,
            priceKind: priceKind,
            maximumPriceText: maximumPriceText,
            priceNote: priceNote,
            generatedImageURL: generatedImageURL,
            publicationMode: publicationMode,
            scheduledAt: scheduledAt
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
        hasExplicitEndDate = draft.hasExplicitEndDate ?? (draft.endDate > draft.startDate)
        isAllDay = draft.isAllDay
        selectedCategory = draft.selectedCategory
        additionalCategories = normalizedAdditionalCategories(draft.additionalCategories ?? [])
        selectedAudience = draft.selectedAudience ?? .everyone
        minimumAgeText = draft.minimumAgeText ?? ""
        maximumAgeText = draft.maximumAgeText ?? ""
        tags = draft.tags
        tagInput = draft.tagInput
        requiresRegistration = draft.requiresRegistration
        priceText = draft.priceText
        capacityText = draft.capacityText
        germanTitle = draft.germanTitle ?? ""
        germanSummary = draft.germanSummary ?? ""
        germanDetails = draft.germanDetails ?? ""
        additionalOccurrences = draft.additionalOccurrences ?? []
        participationMode = draft.participationMode ?? (draft.requiresRegistration ? .inAppRegistration : .none)
        externalActionTitle = draft.externalActionTitle ?? ""
        externalActionURL = draft.externalActionURL ?? ""
        priceKind = draft.priceKind ?? (draft.priceText.isEmpty ? .free : .exact)
        maximumPriceText = draft.maximumPriceText ?? ""
        priceNote = draft.priceNote ?? ""
        generatedImageURL = draft.generatedImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        publicationMode = draft.publicationMode ?? .now
        if let scheduledAt = draft.scheduledAt { self.scheduledAt = scheduledAt }
        hasMeaningfulCreateDraftMetadata = draft.hasMeaningfulMetadata == true

        isApplyingRecoveredDraft = false
    }

    func toggleAdditionalCategory(_ category: EventCategory) {
        guard category != selectedCategory, category != .unspecified else { return }
        if let index = additionalCategories.firstIndex(of: category) {
            additionalCategories.remove(at: index)
        } else if additionalCategories.count < EventCategory.maximumAdditionalCategoryCount {
            additionalCategories.append(category)
        }
    }

    func isAdditionalCategoryDisabled(_ category: EventCategory) -> Bool {
        category == selectedCategory
            || (!additionalCategories.contains(category)
                && additionalCategories.count >= EventCategory.maximumAdditionalCategoryCount)
    }

    private func normalizedAdditionalCategories(_ categories: [EventCategory]) -> [EventCategory] {
        Array(categories.reduce(into: [EventCategory]()) { result, candidate in
            guard candidate != selectedCategory,
                  candidate != .unspecified,
                  !result.contains(candidate) else { return }
            result.append(candidate)
        }.prefix(EventCategory.maximumAdditionalCategoryCount))
    }

    private func downloadGeneratedImageIfNeeded() async throws -> Data? {
        guard selectedImageData == nil else { return nil }
        guard let generatedImageURL else { return nil }
        guard let url = URL(string: generatedImageURL),
              url.scheme?.lowercased() == "https" else { throw AppError.validationFailed }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard data.count <= 15_000_000,
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              httpResponse.mimeType?.hasPrefix("image/") == true else {
            throw AppError.validationFailed
        }
        return data
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
        guard isValidExternalParticipation else {
            errorMessage = ContentPublishingStrings.secureWebLinkRequired
            return false
        }
        guard isValidPricing else {
            errorMessage = AppStrings.Events.invalidPrice
            return false
        }
        guard let validationIssue else { return true }
        errorMessage = validationIssue.message
        return false
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

    private static func isValidPositiveIntegerOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed).map { $0 > 0 } == true
    }

    private static func isValidNonNegativeDecimalOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map { $0 >= 0 } == true
    }

    private static func isValidAgeOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed).map { (0...120).contains($0) } == true
    }
}

private extension Event {
    func settingImageURL(_ imageURL: String?) -> Event {
        Event(
            id: id,
            schemaVersion: schemaVersion,
            localizations: localizations,
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
            occurrences: occurrences,
            createdAt: createdAt,
            updatedAt: updatedAt,
            scheduledAt: scheduledAt,
            requiresRegistration: requiresRegistration,
            participationMode: participationMode,
            externalAction: externalAction,
            price: price,
            pricing: pricing,
            capacity: capacity,
            registeredCount: registeredCount,
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: registrationState,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            category: category,
            additionalCategories: additionalCategories,
            audience: audience,
            minimumAge: minimumAge,
            maximumAge: maximumAge,
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
