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
    @Published private(set) var actionTargetItemsByKind: [FeaturedBannerActionTargetKind: [FeaturedBannerActionTargetItem]] = [:]
    @Published private(set) var loadingActionTargetKinds: Set<FeaturedBannerActionTargetKind> = []
    @Published private(set) var actionTargetLoadError: String?
    @Published private(set) var selectedActionTargetSnapshot: FeaturedBannerActionTargetItem?

    private let repository: FeaturedBannerRepository
    private let newsRepository: NewsRepository?
    private let eventRepository: EventRepository?
    private let organizationRepository: OrganizationRepository?
    private let imageUploadService: ImageUploadService
    private let validationService = FeaturedBannerValidationService()
    private let mode: Mode
    private let bannerID: String
    private let createdAt: Date
    private let createdBy: String
    private var selectedProcessedImage: ProcessedImageSelection?
    private var actionTargetLoadTasks: [FeaturedBannerActionTargetKind: Task<[FeaturedBannerActionTargetItem], Error>] = [:]

    init(
        repository: FeaturedBannerRepository,
        mode: Mode = .create,
        newsRepository: NewsRepository? = nil,
        eventRepository: EventRepository? = nil,
        organizationRepository: OrganizationRepository? = nil,
        imageUploadService: ImageUploadService? = nil
    ) {
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
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

    deinit {
        actionTargetLoadTasks.values.forEach { $0.cancel() }
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

    var actionTargetPickerKind: FeaturedBannerActionTargetKind? {
        FeaturedBannerActionTargetKind(actionType: actionType)
    }

    var supportsActionTargetPicker: Bool {
        actionTargetPickerKind != nil
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
            let haystack = [
                item.title,
                item.subtitle,
                item.metadata,
                item.id
            ]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()

            return searchTokens.allSatisfy { haystack.contains($0) }
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

    private func loadActionTargets(kind: FeaturedBannerActionTargetKind) async {
        if let task = actionTargetLoadTasks[kind] {
            await applyActionTargetResult(from: task, kind: kind)
            return
        }

        actionTargetLoadError = nil
        loadingActionTargetKinds.insert(kind)

        let task = Task<[FeaturedBannerActionTargetItem], Error> {
            switch kind {
            case .news:
                guard let newsRepository else { throw AppError.validationFailed }
                let posts = try await newsRepository.fetchNews()
                return posts
                    .filter { $0.moderationStatus == .approved }
                    .sorted { $0.publishedAt > $1.publishedAt }
                    .map(FeaturedBannerActionTargetItem.init(news:))
            case .event:
                guard let eventRepository else { throw AppError.validationFailed }
                let events = try await eventRepository.fetchEvents()
                return events
                    .filter { $0.moderationStatus == .approved }
                    .sorted { $0.startDate > $1.startDate }
                    .map(FeaturedBannerActionTargetItem.init(event:))
            case .organization:
                guard let organizationRepository else { throw AppError.validationFailed }
                let organizations = try await organizationRepository.fetchOrganizations()
                return organizations
                    .filter { $0.moderationStatus == .approved }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map(FeaturedBannerActionTargetItem.init(organization:))
            }
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

enum FeaturedBannerActionTargetKind: String, CaseIterable, Identifiable, Hashable {
    case news
    case event
    case organization

    var id: String { rawValue }

    init?(actionType: FeaturedBannerActionType) {
        switch actionType {
        case .news:
            self = .news
        case .event:
            self = .event
        case .organization:
            self = .organization
        case .none, .guide, .externalURL, .announcement, .emergency, .partner:
            return nil
        }
    }

    var title: String {
        switch self {
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .news:
            return "newspaper"
        case .event:
            return "calendar"
        case .organization:
            return "building.2"
        }
    }
}

struct FeaturedBannerActionTargetItem: Identifiable, Hashable {
    let id: String
    let kind: FeaturedBannerActionTargetKind
    let title: String
    let subtitle: String?
    let metadata: String?

    init(news: NewsPost) {
        id = news.id
        kind = .news
        title = news.title
        subtitle = Self.nonEmpty(news.subtitle)
        metadata = Self.joined([
            news.source.displayOrganizationName ?? news.authorName,
            Self.dateText(news.publishedAt)
        ])
    }

    init(event: Event) {
        id = event.id
        kind = .event
        title = event.title
        subtitle = Self.nonEmpty(event.summary)
        metadata = Self.joined([
            Self.nonEmpty(event.organizerName) ?? event.source.displayOrganizationName,
            Self.joined([Self.nonEmpty(event.city), Self.nonEmpty(event.venue)]),
            Self.dateText(event.startDate)
        ])
    }

    init(organization: Organization) {
        id = organization.id
        kind = .organization
        title = organization.name
        subtitle = Self.nonEmpty(organization.shortDescription)
        metadata = Self.joined([
            Self.nonEmpty(organization.organizationType),
            Self.nonEmpty(organization.city)
        ])
    }

    private static func joined(_ values: [String?]) -> String? {
        let joined = values.compactMap { nonEmpty($0) }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
