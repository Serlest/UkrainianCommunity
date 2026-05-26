import Combine
import Foundation

@MainActor
final class NewsEditorViewModel: ObservableObject {
    struct CreateContext {
        let organizationId: String
        let organizationName: String?
        let organizationImageURL: String?
        let organizationFederalState: AustrianFederalState?

        var source: ContentSourceMetadata {
            return ContentSourceMetadata(
                sourceType: .organization,
                organizationId: organizationId,
                organizationName: organizationName,
                organizationImageURL: organizationImageURL
            )
        }

        var isOrganizationPost: Bool {
            return !organizationId.isEmpty
        }
    }

    enum Mode {
        case create(context: CreateContext? = nil)
        case edit(existing: NewsPost)

        var isEditing: Bool {
            if case .edit = self {
                return true
            }
            return false
        }
    }

    @Published var title = ""
    @Published var summary = ""
    @Published var body = ""
    @Published var tagsInput = ""
    @Published var selectedFederalState: AustrianFederalState = .tirol
    @Published var isPublishing = false
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?
    @Published private var selectedCreateContext: CreateContext?

    private let repository: NewsRepository
    private let imageUploadService = ImageUploadService.shared
    private var authState: AuthState?
    private let mode: Mode

    init(repository: NewsRepository, authState: AuthState? = nil, mode: Mode = .create()) {
        self.repository = repository
        self.authState = authState
        self.mode = mode

        if case let .create(context) = mode {
            selectedCreateContext = context
        }

        if case let .edit(existingNews) = mode {
            title = existingNews.title
            summary = existingNews.subtitle
            body = existingNews.body
            tagsInput = existingNews.tags.joined(separator: ", ")
            selectedFederalState = existingNews.federalState ?? .tirol
        }
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedBody.isEmpty
            && resolvedFederalState != nil
            && hasOrganizerForCreate
            && !isProcessingImage
            && !isUploadingImage
            && !isPublishing
    }

    var isEditing: Bool {
        mode.isEditing
    }

    var showsRegionPicker: Bool {
        false
    }

    var requiresOrganizationRegionBeforePublishing: Bool {
        isOrganizationPost && resolvedFederalState == nil
    }

    var existingImageURL: String? {
        if case let .edit(existingNews) = mode {
            return existingNews.imageURL
        }
        return nil
    }

    var organizerName: String? {
        switch mode {
        case .create:
            selectedCreateContext?.organizationName
        case let .edit(existingNews):
            existingNews.source.organizationName
        }
    }

    var organizerImageURL: String? {
        switch mode {
        case .create:
            guard let imageURL = selectedCreateContext?.organizationImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        case let .edit(existingNews):
            guard let imageURL = existingNews.source.organizationImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty else {
                return nil
            }
            return imageURL
        }
    }

    var selectedOrganizationId: String? {
        switch mode {
        case .create:
            selectedCreateContext?.organizationId
        case let .edit(existingNews):
            existingNews.source.organizationId
        }
    }

    var navigationTitle: String {
        mode.isEditing ? AppStrings.NewsEditor.editTitle : AppStrings.NewsEditor.title
    }

    var submitButtonTitle: String {
        mode.isEditing ? AppStrings.NewsEditor.saveChanges : AppStrings.NewsEditor.publish
    }

    var primarySubmitButtonTitle: String {
        mode.isEditing ? AppStrings.NewsEditor.primarySaveChanges : AppStrings.NewsEditor.primaryPublish
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

    func setAuthState(_ authState: AuthState?) {
        self.authState = authState
    }

    func selectOrganizer(_ organization: Organization) {
        guard case .create = mode else { return }
        selectedCreateContext = CreateContext(
            organizationId: organization.id,
            organizationName: organization.name,
            organizationImageURL: organization.imageURL,
            organizationFederalState: organization.federalState
        )
    }

    func publish() async -> Bool {
        guard !isPublishing else { return false }

        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return false
        }

        let now = Date()
        let newsID: String
        let createdAt: Date
        let existingImageURL: String?
        let existingCity: String?
        let existingSource: ContentSourceMetadata
        let existingComments: [Comment]
        let existingLikeCount: Int
        let existingLikeState: LikeState
        let existingViewCount: Int
        let existingIsBookmarked: Bool
        let existingCommentCount: Int
        let publishedAt: Date
        let newsFederalState = resolvedFederalState
        switch mode {
        case .create:
            guard let context = selectedCreateContext, context.isOrganizationPost else {
                errorMessage = AppStrings.NewsEditor.organizationRequired
                return false
            }
            newsID = UUID().uuidString
            createdAt = now
            publishedAt = now
            existingImageURL = nil
            existingCity = nil
            existingSource = context.source
            existingComments = []
            existingLikeCount = 0
            existingLikeState = .notLiked
            existingViewCount = 0
            existingIsBookmarked = false
            existingCommentCount = 0
        case let .edit(existingNews):
            newsID = existingNews.id
            createdAt = existingNews.createdAt
            publishedAt = existingNews.publishedAt
            existingImageURL = existingNews.imageURL
            existingCity = existingNews.city
            existingSource = existingNews.source
            existingComments = existingNews.comments
            existingLikeCount = existingNews.likeCount
            existingLikeState = existingNews.likeState
            existingViewCount = existingNews.viewCount
            existingIsBookmarked = existingNews.isBookmarked
            existingCommentCount = existingNews.commentCount
        }
        let news = NewsPost(
            id: newsID,
            title: trimmedTitle,
            subtitle: trimmedSummary,
            regionScope: .federalState,
            federalState: newsFederalState,
            city: existingCity,
            category: .news,
            tags: parsedTags,
            source: existingSource,
            imageURL: nil,
            body: trimmedBody,
            authorName: resolvedAuthorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: now,
            comments: existingComments,
            moderationStatus: existingModerationStatus,
            likeCount: existingLikeCount,
            likeState: existingLikeState,
            viewCount: existingViewCount,
            isBookmarked: existingIsBookmarked,
            commentCount: existingCommentCount
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            switch mode {
            case .create:
                try await repository.createNews(news)

                if let selectedImageData {
                    isUploadingImage = true
                    var uploadedDraftImage = false
                    let organizationID = news.source.organizationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    do {
                        guard !organizationID.isEmpty else {
                            throw AppError.validationFailed
                        }
                        let downloadURL = try await imageUploadService.uploadOrganizationNewsDraftImage(
                            data: selectedImageData,
                            organizationID: organizationID,
                            newsID: newsID
                        )
                        uploadedDraftImage = true
                        try await repository.updateNewsImageURL(id: newsID, imageURL: downloadURL.absoluteString)
                    } catch let uploadError {
                        isUploadingImage = false
                        if uploadedDraftImage, !organizationID.isEmpty {
                            try? await imageUploadService.deleteOrganizationNewsDraftImage(
                                organizationID: organizationID,
                                newsID: newsID
                            )
                        }
                        do {
                            try await repository.deleteNews(id: news.id)
                            errorMessage = readableUploadErrorMessage(for: uploadError)
                        } catch {
                            errorMessage = readableRollbackErrorMessage(uploadError: uploadError)
                        }
                        return false
                    }
                    isUploadingImage = false
                }

                successMessage = AppStrings.NewsEditor.publishedSuccessfully

            case .edit:
                var resolvedImageURL = existingImageURL
                if let selectedImageData {
                    isUploadingImage = true
                    let downloadURL = try await imageUploadService.uploadNewsCoverImage(data: selectedImageData, newsID: newsID)
                    resolvedImageURL = downloadURL.absoluteString
                    isUploadingImage = false
                }

                try await repository.updateNews(news.settingImageURL(resolvedImageURL))
                successMessage = AppStrings.NewsEditor.updatedSuccessfully
            }

            AppContentChangeBus.postNewsChanged(organizationID: news.source.organizationId)
            title = ""
            summary = ""
            body = ""
            tagsInput = ""
            selectedImageData = nil
            return true
        } catch {
            isUploadingImage = false
            errorMessage = readablePublishErrorMessage(for: error)
            return false
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedSummary: String {
        summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedTags: [String] {
        var seen = Set<String>()
        return tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { tag in
                let key = tag.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    private var isOrganizationPost: Bool {
        switch mode {
        case .create:
            return selectedCreateContext?.isOrganizationPost ?? false
        case let .edit(existingNews):
            return existingNews.source.sourceType == .organization
        }
    }

    private var resolvedFederalState: AustrianFederalState? {
        switch mode {
        case .create:
            return selectedCreateContext?.organizationFederalState
        case let .edit(existingNews):
            return existingNews.federalState
        }
    }

    private var resolvedAuthorName: String {
        if case let .edit(existingNews) = mode, selectedImageData == nil, authState?.user == nil {
            return existingNews.authorName
        }

        if let fullName = authState?.user?.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            return fullName
        }

        if let userID = authState?.user?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !userID.isEmpty {
            return userID
        }

        return AppStrings.NewsEditor.authorFallback
    }

    private var existingModerationStatus: ModerationStatus {
        if case let .edit(existingNews) = mode {
            return existingNews.moderationStatus
        }
        return .approved
    }

    private var hasOrganizerForCreate: Bool {
        isEditing || (selectedCreateContext?.isOrganizationPost ?? false)
    }

    private func validate() -> Bool {
        guard !trimmedTitle.isEmpty else {
            errorMessage = AppStrings.NewsEditor.titleRequired
            successMessage = nil
            return false
        }

        guard !trimmedSummary.isEmpty else {
            errorMessage = AppStrings.NewsEditor.summaryRequired
            successMessage = nil
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = AppStrings.NewsEditor.bodyRequired
            successMessage = nil
            return false
        }

        guard hasOrganizerForCreate else {
            errorMessage = AppStrings.NewsEditor.organizationRequired
            successMessage = nil
            return false
        }

        guard resolvedFederalState != nil else {
            errorMessage = AppStrings.NewsEditor.organizationRegionRequired
            successMessage = nil
            return false
        }

        return true
    }

    private func readableUploadErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.NewsEditor.imageProcessingFailed : message
    }

    private func readablePublishErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.News.actionUnknownError : message
    }

    private func readableRollbackErrorMessage(uploadError: Error) -> String {
        let uploadMessage = readableUploadErrorMessage(for: uploadError)
        return "\(uploadMessage) \(AppStrings.News.actionUnknownError)"
    }
}

private extension NewsPost {
    func settingImageURL(_ imageURL: String?) -> NewsPost {
        NewsPost(
            id: id,
            title: title,
            subtitle: subtitle,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            category: category,
            tags: tags,
            source: source,
            imageURL: imageURL,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            comments: comments,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
    }
}
