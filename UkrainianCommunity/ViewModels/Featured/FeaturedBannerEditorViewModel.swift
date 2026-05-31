import Combine
import Foundation

@MainActor
final class FeaturedBannerEditorViewModel: ObservableObject {
    enum Mode {
        case create
        case edit(FeaturedBanner)

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    @Published var title: String
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

    private let repository: FeaturedBannerRepository
    private let imageUploadService: ImageUploadService
    private let validationService = FeaturedBannerValidationService()
    private let mode: Mode
    private let bannerID: String
    private let createdAt: Date
    private let createdBy: String
    private var selectedProcessedImage: ProcessedImageSelection?

    init(
        repository: FeaturedBannerRepository,
        mode: Mode = .create,
        imageUploadService: ImageUploadService? = nil
    ) {
        self.repository = repository
        self.mode = mode
        self.imageUploadService = imageUploadService ?? .shared

        switch mode {
        case .create:
            let now = Date()
            bannerID = UUID().uuidString
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
        case let .edit(existing):
            bannerID = existing.id
            title = existing.title
            subtitle = existing.subtitle ?? ""
            imageURL = existing.imageURL ?? ""
            regionScope = existing.regionScope
            federalState = existing.federalState
            visibleSections = existing.visibleSections
            actionType = existing.actionType
            actionTargetID = existing.actionTargetID ?? ""
            externalURL = existing.externalURL ?? ""
            displayDurationSeconds = existing.displayDurationSeconds
            priority = existing.priority
            isActive = existing.isActive
            hasStartDate = existing.startsAt != nil
            startsAt = existing.startsAt ?? Date()
            hasEndDate = existing.endsAt != nil
            endsAt = existing.endsAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
            createdAt = existing.createdAt
            createdBy = existing.createdBy
        }
    }

    var navigationTitle: String {
        mode.isEditing ? AppStrings.FeaturedEditor.editTitle : AppStrings.FeaturedEditor.createTitle
    }

    var saveButtonTitle: String {
        mode.isEditing ? AppStrings.FeaturedEditor.saveChanges : AppStrings.FeaturedEditor.createBanner
    }

    var existingImageURL: String? {
        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var canSave: Bool {
        !isSaving && !isProcessingImage && validationMessage == nil
    }

    var validationMessage: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.FeaturedEditor.validationTitleRequired
        }

        if selectedImageData == nil && imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.FeaturedEditor.validationImageRequired
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
        case .news, .event, .organization, .guide:
            return true
        case .none, .externalURL, .announcement, .emergency, .partner:
            return false
        }
    }

    var requiresExternalURL: Bool {
        switch actionType {
        case .externalURL, .partner:
            return true
        case .none, .news, .event, .organization, .guide, .announcement, .emergency:
            return false
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

        do {
            let resolvedImageURL = try await resolvedImageURL()
            let resolvedImageURLString = resolvedImageURL.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !resolvedImageURLString.isEmpty else {
                errorMessage = AppStrings.FeaturedEditor.validationImageRequired
                return false
            }

            let now = Date()
            let banner = FeaturedBanner(
                id: bannerID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: nonEmpty(subtitle),
                imageURL: resolvedImageURLString,
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
                updatedAt: now,
                createdBy: mode.isEditing ? createdBy : userID,
                updatedBy: userID
            )
            try validationService.validate(banner)

            switch mode {
            case .create:
                try await repository.createBanner(banner)
            case .edit:
                try await repository.updateBanner(banner)
            }

            imageURL = resolvedImageURLString
            selectedImageData = nil
            selectedProcessedImage = nil
            successMessage = AppStrings.FeaturedEditor.saveSuccess
            return true
        } catch let appError as AppError {
            errorMessage = errorText(appError)
        } catch {
            errorMessage = AppStrings.FeaturedEditor.saveUnknownError
        }
        return false
    }

    private var normalizedExternalURL: URL? {
        FeaturedBannerURLNormalizer.normalizedExternalURL(from: externalURL)
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
