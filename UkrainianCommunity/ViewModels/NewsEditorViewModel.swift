import Combine
import Foundation

@MainActor
final class NewsEditorViewModel: ObservableObject {
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

        var isOrganizationPost: Bool {
            guard let organizationId else { return false }
            return !organizationId.isEmpty
        }
    }

    enum Mode {
        case create(context: CreateContext = .app)
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
    @Published var category: NewsCategory = .news
    @Published var tagsInput = ""
    @Published var selectedFederalState: AustrianFederalState = .tirol
    @Published var isPublishing = false
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?

    private let repository: NewsRepository
    private let imageUploadService = ImageUploadService.shared
    private var authState: AuthState?
    private let mode: Mode

    init(repository: NewsRepository, authState: AuthState? = nil, mode: Mode = .create()) {
        self.repository = repository
        self.authState = authState
        self.mode = mode

        if case let .edit(existingNews) = mode {
            title = existingNews.title
            summary = existingNews.subtitle
            body = existingNews.body
            category = existingNews.category
            tagsInput = existingNews.tags.joined(separator: ", ")
            selectedFederalState = existingNews.federalState ?? .tirol
        }
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedSummary.isEmpty
            && !trimmedBody.isEmpty
            && resolvedFederalState != nil
            && !isProcessingImage
            && !isUploadingImage
            && !isPublishing
    }

    var isEditing: Bool {
        mode.isEditing
    }

    var showsRegionPicker: Bool {
        guard isAppLevelPost else { return false }
        return PermissionService.canManageAppNews(user: authState?.user)
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
        let publishedAt: Date
        let newsFederalState = resolvedFederalState
        switch mode {
        case let .create(context):
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
        }
        var resolvedImageURL: String?
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
            isBookmarked: existingIsBookmarked
        )

        isPublishing = true
        defer { isPublishing = false }

        do {
            if let selectedImageData {
                isUploadingImage = true
                do {
                    let downloadURL = try await imageUploadService.uploadNewsCoverImage(data: selectedImageData, newsID: newsID)
                    resolvedImageURL = downloadURL.absoluteString
                } catch {
                    isUploadingImage = false
                    errorMessage = readableUploadErrorMessage(for: error)
                    return false
                }
                isUploadingImage = false
            } else {
                resolvedImageURL = existingImageURL
            }

            let newsToCreate = NewsPost(
                id: news.id,
                title: news.title,
                subtitle: news.subtitle,
                regionScope: news.regionScope,
                federalState: news.federalState,
                city: news.city,
                category: news.category,
                tags: news.tags,
                source: news.source,
                imageURL: resolvedImageURL,
                body: news.body,
                authorName: news.authorName,
                publishedAt: news.publishedAt,
                createdAt: news.createdAt,
                updatedAt: news.updatedAt,
                comments: news.comments,
                moderationStatus: news.moderationStatus,
                likeCount: news.likeCount,
                likeState: news.likeState,
                viewCount: news.viewCount,
                isBookmarked: news.isBookmarked
            )

            switch mode {
            case .create:
                try await repository.createNews(newsToCreate)
                successMessage = AppStrings.NewsEditor.publishedSuccessfully
            case .edit:
                try await repository.updateNews(newsToCreate)
                successMessage = AppStrings.NewsEditor.updatedSuccessfully
            }
            AppContentChangeBus.postNewsChanged(organizationID: newsToCreate.source.organizationId)
            title = ""
            summary = ""
            body = ""
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
        case let .create(context):
            return context.isOrganizationPost
        case let .edit(existingNews):
            return existingNews.source.sourceType == .organization
        }
    }

    private var isAppLevelPost: Bool {
        !isOrganizationPost
    }

    private var resolvedFederalState: AustrianFederalState? {
        switch mode {
        case let .create(context):
            return context.isOrganizationPost ? context.organizationFederalState : selectedFederalState
        case let .edit(existingNews):
            return existingNews.source.sourceType == .organization ? existingNews.federalState : selectedFederalState
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
}
