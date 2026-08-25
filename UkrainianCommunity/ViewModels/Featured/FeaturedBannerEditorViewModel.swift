import Combine
import Foundation

@MainActor
final class FeaturedBannerEditorViewModel: ObservableObject {
    private struct DraftSignature: Equatable {
        let title: String
        let internalName: String
        let subtitle: String
        let imageURL: String
        let regionScope: FeaturedBannerRegionScope
        let federalState: AustrianFederalState?
        let visibleSections: Set<FeaturedBannerVisibleSection>
        let actionType: FeaturedBannerActionType
        let actionTargetID: String
        let externalURL: String
        let displayDurationSeconds: Int
        let priority: Int
        let isActive: Bool
        let hasStartDate: Bool
        let startsAt: Date
        let hasEndDate: Bool
        let endsAt: Date
    }

    enum Mode {
        case create
        case duplicate(FeaturedBanner)
        case edit(FeaturedBanner)

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }

        var isDuplicating: Bool {
            if case .duplicate = self { return true }
            return false
        }
    }

    @Published var title: String
    @Published var internalName: String
    @Published var subtitle: String
    @Published var imageURL: String
    @Published var regionScope: FeaturedBannerRegionScope
    @Published var federalState: AustrianFederalState?
    @Published var visibleSections: Set<FeaturedBannerVisibleSection>
    @Published var actionType: FeaturedBannerActionType
    @Published var actionTargetID: String
    @Published var externalURL: String
    @Published var displayDurationSeconds: Int
    @Published var priority: Int
    @Published var isActive: Bool
    @Published var hasStartDate: Bool
    @Published var startsAt: Date
    @Published var hasEndDate: Bool
    @Published var endsAt: Date
    @Published var selectedImageData: Data?
    @Published var isProcessingImage = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published private(set) var actionTargetItemsByKind: [FeaturedBannerActionTargetKind: [FeaturedBannerActionTargetItem]] = [:]
    @Published private(set) var loadingActionTargetKinds: Set<FeaturedBannerActionTargetKind> = []
    @Published private(set) var actionTargetLoadError: String?
    @Published private(set) var selectedActionTargetSnapshot: FeaturedBannerActionTargetItem?

    private let repository: FeaturedBannerRepository
    private let actionTargetLoader: FeaturedBannerActionTargetLoader
    private let imageUploadService: any FeaturedBannerImageService
    private let validationService = FeaturedBannerValidationService()
    private let mode: Mode
    private let bannerID: String
    private let createdAt: Date
    private let createdBy: String
    private let originalImageURL: URL?
    let isMigratingLegacyBanner: Bool
    let isRepairingMalformedBanner: Bool
    private var selectedProcessedImage: ProcessedImageSelection?
    private var actionTargetLoadTasks: [FeaturedBannerActionTargetKind: Task<[FeaturedBannerActionTargetItem], Error>] = [:]
    private var initialDraftSignature: DraftSignature?

    init(
        repository: FeaturedBannerRepository,
        mode: Mode = .create,
        newsRepository: NewsRepository? = nil,
        eventRepository: EventRepository? = nil,
        organizationRepository: OrganizationRepository? = nil,
        imageUploadService: (any FeaturedBannerImageService)? = nil
    ) {
        self.repository = repository
        actionTargetLoader = FeaturedBannerActionTargetLoader(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )
        self.mode = mode
        self.imageUploadService = imageUploadService ?? ImageUploadService.shared

        switch mode {
        case .create:
            let now = Date()
            bannerID = UUID().uuidString
            internalName = ""
            title = ""
            subtitle = ""
            imageURL = ""
            regionScope = .allAustria
            federalState = nil
            visibleSections = [.home]
            actionType = .none
            actionTargetID = ""
            externalURL = ""
            displayDurationSeconds = 6
            priority = 0
            isActive = true
            hasStartDate = false
            startsAt = now
            hasEndDate = false
            endsAt = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            createdAt = now
            createdBy = ""
            originalImageURL = nil
            isMigratingLegacyBanner = false
            isRepairingMalformedBanner = false
        case let .duplicate(existing):
            let now = Date()
            bannerID = UUID().uuidString
            internalName = existing.internalName ?? ""
            title = existing.title
            subtitle = existing.subtitle ?? ""
            imageURL = existing.imageURL ?? ""
            regionScope = existing.regionScope
            federalState = existing.federalState
            let supportedSections = existing.supportedVisibleSections
            visibleSections = supportedSections.isEmpty ? [.home] : supportedSections
            actionType = existing.actionType.isSupported ? existing.actionType : .none
            actionTargetID = existing.actionType.isSupported ? (existing.actionTargetID ?? "") : ""
            externalURL = existing.externalURL ?? ""
            displayDurationSeconds = existing.displayDurationSeconds
            priority = existing.priority
            // A copy must never become public before the owner reviews it.
            isActive = false
            hasStartDate = existing.startsAt != nil
            startsAt = existing.startsAt ?? now
            hasEndDate = existing.endsAt != nil
            endsAt = existing.endsAt ?? Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            createdAt = now
            createdBy = ""
            // The copy reuses the published asset. It must not own or delete
            // the source banner's image when another image is selected.
            originalImageURL = nil
            isMigratingLegacyBanner = false
            isRepairingMalformedBanner = false
        case let .edit(existing):
            bannerID = existing.id
            internalName = existing.internalName ?? ""
            title = existing.title
            subtitle = existing.subtitle ?? ""
            imageURL = existing.imageURL ?? ""
            regionScope = existing.regionScope
            federalState = existing.federalState
            let supportedSections = existing.supportedVisibleSections
            visibleSections = supportedSections.isEmpty ? [.home] : supportedSections
            actionType = existing.actionType.isSupported ? existing.actionType : .none
            actionTargetID = existing.actionType.isSupported ? (existing.actionTargetID ?? "") : ""
            externalURL = existing.externalURL ?? ""
            displayDurationSeconds = existing.displayDurationSeconds
            priority = existing.priority
            isActive = existing.isActive
            hasStartDate = existing.startsAt != nil
            startsAt = existing.startsAt ?? Date()
            hasEndDate = existing.endsAt != nil
            endsAt = existing.endsAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            createdAt = existing.createdAt == .distantPast ? Date() : existing.createdAt
            createdBy = existing.createdBy
            if let existingImageURL = existing.imageURL {
                originalImageURL = URL(string: existingImageURL)
            } else {
                originalImageURL = nil
            }
            isMigratingLegacyBanner = existing.hasUnsupportedLegacyConfiguration
            isRepairingMalformedBanner = existing.requiresDataRepair
        }
        initialDraftSignature = draftSignature
    }

    deinit {
        actionTargetLoadTasks.values.forEach { $0.cancel() }
    }

    var navigationTitle: String {
        if mode.isEditing {
            return AppStrings.FeaturedEditor.editTitle
        }
        if mode.isDuplicating {
            return AppStrings.FeaturedManagement.duplicateBanner
        }
        return AppStrings.FeaturedEditor.createTitle
    }

    var saveButtonTitle: String {
        mode.isEditing ? AppStrings.FeaturedEditor.saveChanges : AppStrings.FeaturedEditor.createBanner
    }

    var existingImageURL: String? {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var previewBanner: FeaturedBanner {
        FeaturedBanner(
            id: bannerID,
            internalName: nonEmpty(internalName),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: nonEmpty(subtitle),
            imageURL: nonEmpty(imageURL),
            actionType: actionType,
            actionTargetID: requiresActionTarget ? nonEmpty(actionTargetID) : nil,
            externalURL: requiresExternalURL ? normalizedExternalURL?.absoluteString : nil,
            regionScope: regionScope,
            federalState: regionScope == .federalState ? federalState : nil,
            visibleSections: visibleSections,
            displayDurationSeconds: displayDurationSeconds,
            priority: priority,
            isActive: isActive,
            startsAt: hasStartDate ? startsAt : nil,
            endsAt: hasEndDate ? endsAt : nil,
            createdAt: createdAt,
            updatedAt: Date(),
            createdBy: nonEmpty(createdBy) ?? "preview"
        )
    }

    var canSave: Bool {
        let hasChangesToPersist = !mode.isEditing || hasUnsavedChanges || isMigratingLegacyBanner
        return hasChangesToPersist && !isSaving && !isProcessingImage && validationMessage == nil
    }

    var hasUnsavedChanges: Bool {
        guard let initialDraftSignature else { return true }
        return selectedImageData != nil || draftSignature != initialDraftSignature
    }

    var validationMessage: String? {
        if selectedImageData == nil && imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.FeaturedEditor.validationImageRequired
        }

        if selectedImageData == nil,
           FeaturedBannerURLNormalizer.normalizedExternalURL(from: imageURL) == nil {
            return AppStrings.FeaturedEditor.validationImageURL
        }

        if internalName.trimmingCharacters(in: .whitespacesAndNewlines).count > FeaturedBannerValidationService.internalNameMaxLength
            || title.trimmingCharacters(in: .whitespacesAndNewlines).count > FeaturedBannerValidationService.titleMaxLength
            || subtitle.trimmingCharacters(in: .whitespacesAndNewlines).count > FeaturedBannerValidationService.subtitleMaxLength {
            return AppStrings.FeaturedEditor.validationTextLength
        }

        if !FeaturedBannerValidationService.displayDurationBounds.contains(displayDurationSeconds) {
            return AppStrings.FeaturedEditor.validationDuration
        }

        if priority < 0 || priority > 1000 {
            return AppStrings.FeaturedEditor.validationPriority
        }

        if visibleSections.isEmpty {
            return AppStrings.FeaturedEditor.validationSections
        }

        if regionScope == .federalState && federalState == nil {
            return AppStrings.FeaturedEditor.validationFederalState
        }

        if requiresExternalURL {
            guard normalizedExternalURL != nil else {
                return AppStrings.FeaturedEditor.validationExternalURL
            }
        }

        if requiresActionTarget && actionTargetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.FeaturedEditor.validationTargetID
        }

        if hasStartDate && hasEndDate && startsAt >= endsAt {
            return AppStrings.FeaturedEditor.validationDateWindow
        }

        return nil
    }

    var requiresActionTarget: Bool {
        switch actionType {
        case .news, .event, .organization:
            return true
        case .none, .externalURL, .unsupportedLegacy:
            return false
        }
    }

    var requiresExternalURL: Bool {
        switch actionType {
        case .externalURL:
            return true
        case .none, .news, .event, .organization, .unsupportedLegacy:
            return false
        }
    }

    var actionTargetPickerKind: FeaturedBannerActionTargetKind? {
        FeaturedBannerActionTargetKind(actionType: actionType)
    }

    var selectedActionTargetItem: FeaturedBannerActionTargetItem? {
        guard let kind = actionTargetPickerKind,
              let targetID = nonEmpty(actionTargetID) else {
            return nil
        }

        if let item = actionTargetItemsByKind[kind]?.first(where: { $0.id == targetID }) {
            return item
        }

        if selectedActionTargetSnapshot?.kind == kind,
           selectedActionTargetSnapshot?.id == targetID {
            return selectedActionTargetSnapshot
        }

        return nil
    }

    var isLoadingCurrentActionTargets: Bool {
        guard let kind = actionTargetPickerKind else { return false }
        return loadingActionTargetKinds.contains(kind)
    }

    func handleActionTypeChanged(from oldActionType: FeaturedBannerActionType, to newActionType: FeaturedBannerActionType) {
        actionTargetLoadError = nil
        selectedActionTargetSnapshot = nil

        let oldKind = FeaturedBannerActionTargetKind(actionType: oldActionType)
        let newKind = FeaturedBannerActionTargetKind(actionType: newActionType)
        if !requiresActionTarget || oldKind != newKind {
            actionTargetID = ""
        }

        if !requiresExternalURL {
            externalURL = ""
        }

    }

    func setSelectedImageData(_ data: Data?) {
        selectedImageData = data
        selectedProcessedImage = nil
        errorMessage = nil
        successMessage = nil
    }

    func setSelectedImageSelection(_ selection: ProcessedImageSelection?) {
        selectedProcessedImage = selection
        selectedImageData = selection?.data
        errorMessage = nil
        successMessage = nil
    }

    func setImageProcessing(_ isProcessing: Bool) {
        isProcessingImage = isProcessing
    }

    func toggleVisibleSection(_ section: FeaturedBannerVisibleSection, isVisible: Bool) {
        if isVisible {
            visibleSections.insert(section)
        } else {
            visibleSections.remove(section)
        }
    }

    func actionTargetItems(matching query: String) -> [FeaturedBannerActionTargetItem] {
        guard let kind = actionTargetPickerKind else { return [] }
        let items = actionTargetItemsByKind[kind] ?? []
        let searchTokens = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)

        guard !searchTokens.isEmpty else { return items }
        return items.filter { item in
            searchTokens.allSatisfy { item.searchText.contains($0) }
        }
    }

    func loadActionTargetsIfNeeded() async {
        guard let kind = actionTargetPickerKind else { return }
        guard actionTargetItemsByKind[kind] == nil else { return }
        await loadActionTargets(kind: kind)
    }

    func refreshActionTargets() async {
        guard let kind = actionTargetPickerKind else { return }
        actionTargetItemsByKind[kind] = nil
        await loadActionTargets(kind: kind)
    }

    func selectActionTarget(_ item: FeaturedBannerActionTargetItem) {
        actionTargetID = item.id
        selectedActionTargetSnapshot = item
        actionTargetLoadError = nil
    }

    func save(updatedBy userID: String?) async -> Bool {
        guard !isSaving else { return false }
        errorMessage = nil
        successMessage = nil

        guard let userID = nonEmpty(userID) else {
            errorMessage = AppStrings.FeaturedEditor.validationOwnerRequired
            return false
        }

        if let validationMessage {
            errorMessage = validationMessage
            return false
        }

        isSaving = true
        defer { isSaving = false }

        var newlyUploadedImageURL: URL?
        do {
            let resolvedImageURL = try await resolvedImageURL()
            if selectedProcessedImage != nil || selectedImageData != nil {
                newlyUploadedImageURL = resolvedImageURL
            }
            let resolvedImageURLString = resolvedImageURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !resolvedImageURLString.isEmpty else {
                errorMessage = AppStrings.FeaturedEditor.validationImageRequired
                return false
            }

            let now = Date()
            let resolvedActionTargetID: String? = {
                switch actionType {
                case .news, .event, .organization:
                    return nonEmpty(actionTargetID)
                case .none, .externalURL, .unsupportedLegacy:
                    return nil
                }
            }()
            let banner = FeaturedBanner(
                id: bannerID,
                internalName: nonEmpty(internalName),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: nonEmpty(subtitle),
                imageURL: resolvedImageURLString,
                actionType: actionType,
                actionTargetID: resolvedActionTargetID,
                externalURL: requiresExternalURL ? normalizedExternalURL?.absoluteString : nil,
                regionScope: regionScope,
                federalState: regionScope == .federalState ? federalState : nil,
                visibleSections: visibleSections,
                displayDurationSeconds: displayDurationSeconds,
                priority: priority,
                isActive: isActive,
                startsAt: hasStartDate ? startsAt : nil,
                endsAt: hasEndDate ? endsAt : nil,
                createdAt: createdAt,
                updatedAt: now,
                createdBy: mode.isEditing ? (nonEmpty(createdBy) ?? userID) : userID,
                updatedBy: userID
            )
            try validationService.validate(banner)

            switch mode {
            case .create, .duplicate:
                try await repository.createBanner(banner)
            case .edit:
                try await repository.updateBanner(banner)
            }

            if let newlyUploadedImageURL,
               let originalImageURL,
               originalImageURL != newlyUploadedImageURL {
                try? await imageUploadService.deleteFeaturedBannerImage(
                    at: originalImageURL,
                    bannerId: bannerID
                )
            }

            imageURL = resolvedImageURLString
            selectedImageData = nil
            selectedProcessedImage = nil
            initialDraftSignature = draftSignature
            successMessage = AppStrings.FeaturedEditor.saveSuccess
            AppContentChangeBus.postFeaturedBannersChanged()
            return true
        } catch let appError as AppError {
            if let newlyUploadedImageURL {
                try? await imageUploadService.deleteFeaturedBannerImage(
                    at: newlyUploadedImageURL,
                    bannerId: bannerID
                )
            }
            errorMessage = errorText(appError)
        } catch {
            if let newlyUploadedImageURL {
                try? await imageUploadService.deleteFeaturedBannerImage(
                    at: newlyUploadedImageURL,
                    bannerId: bannerID
                )
            }
            errorMessage = AppStrings.FeaturedEditor.saveUnknownError
        }
        return false
    }

    private var normalizedExternalURL: URL? {
        FeaturedBannerURLNormalizer.normalizedExternalURL(from: externalURL)
    }

    private var draftSignature: DraftSignature {
        DraftSignature(
            title: title,
            internalName: internalName,
            subtitle: subtitle,
            imageURL: imageURL,
            regionScope: regionScope,
            federalState: federalState,
            visibleSections: visibleSections,
            actionType: actionType,
            actionTargetID: actionTargetID,
            externalURL: externalURL,
            displayDurationSeconds: displayDurationSeconds,
            priority: priority,
            isActive: isActive,
            hasStartDate: hasStartDate,
            startsAt: startsAt,
            hasEndDate: hasEndDate,
            endsAt: endsAt
        )
    }

    private func loadActionTargets(kind: FeaturedBannerActionTargetKind) async {
        if let task = actionTargetLoadTasks[kind] {
            await applyActionTargetResult(from: task, kind: kind)
            return
        }

        actionTargetLoadError = nil
        loadingActionTargetKinds.insert(kind)

        let task = Task<[FeaturedBannerActionTargetItem], Error> {
            try await actionTargetLoader.load(kind: kind)
        }

        actionTargetLoadTasks[kind] = task
        await applyActionTargetResult(from: task, kind: kind)
    }

    private func applyActionTargetResult(from task: Task<[FeaturedBannerActionTargetItem], Error>, kind: FeaturedBannerActionTargetKind) async {
        do {
            let items = try await task.value
            actionTargetItemsByKind[kind] = items
        } catch {
            actionTargetLoadError = AppStrings.FeaturedEditor.targetPickerLoadFailed
        }

        loadingActionTargetKinds.remove(kind)
        actionTargetLoadTasks[kind] = nil
    }

    private func resolvedImageURL() async throws -> URL {
        if let selectedProcessedImage {
            return try await imageUploadService.uploadFeaturedBannerImage(bannerId: bannerID, processedImage: selectedProcessedImage)
        }

        if let selectedImageData {
            return try await imageUploadService.uploadFeaturedBannerImage(bannerId: bannerID, imageData: selectedImageData)
        }

        guard let url = FeaturedBannerURLNormalizer.normalizedExternalURL(from: imageURL) else {
            throw AppError.validationFailed
        }
        return url
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func errorText(_ error: AppError) -> String {
        switch error {
        case .network:
            return AppStrings.FeaturedEditor.saveNetworkError
        case .permissionDenied:
            return AppStrings.FeaturedEditor.savePermissionError
        case .validationFailed:
            return AppStrings.FeaturedEditor.saveValidationError
        case .notFound:
            return AppStrings.FeaturedEditor.saveNotFoundError
        case .unknown:
            return AppStrings.FeaturedEditor.saveUnknownError
        }
    }
}
