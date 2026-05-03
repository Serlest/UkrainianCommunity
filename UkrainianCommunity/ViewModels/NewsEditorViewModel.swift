import Combine
import Foundation

@MainActor
final class NewsEditorViewModel: ObservableObject {
    @Published var title = ""
    @Published var summary = ""
    @Published var body = ""
    @Published var isPublishing = false
    @Published var isUploadingImage = false
    @Published var isProcessingImage = false
    @Published var successMessage: String?
    @Published var errorMessage: String?
    @Published var selectedImageData: Data?

    private let repository: NewsRepository
    private let imageUploadService = ImageUploadService.shared
    private var authState: AuthState?

    init(repository: NewsRepository, authState: AuthState? = nil) {
        self.repository = repository
        self.authState = authState
    }

    var canPublish: Bool {
        !trimmedTitle.isEmpty
            && !trimmedBody.isEmpty
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
        let newsID = UUID().uuidString
        var resolvedImageURL: String?
        let news = NewsPost(
            id: newsID,
            title: trimmedTitle,
            subtitle: trimmedSummary,
            imageURL: nil,
            body: trimmedBody,
            authorName: resolvedAuthorName,
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            comments: [],
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
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
            }

            let newsToCreate = NewsPost(
                id: news.id,
                title: news.title,
                subtitle: news.subtitle,
                imageURL: resolvedImageURL,
                body: news.body,
                authorName: news.authorName,
                publishedAt: news.publishedAt,
                createdAt: news.createdAt,
                updatedAt: news.updatedAt,
                comments: news.comments,
                moderationStatus: news.moderationStatus,
                likeCount: news.likeCount,
                likeState: news.likeState
            )

            try await repository.createNews(newsToCreate)
            successMessage = AppStrings.NewsEditor.publishedSuccessfully
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

    private var resolvedAuthorName: String {
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

    private func validate() -> Bool {
        guard !trimmedTitle.isEmpty else {
            errorMessage = AppStrings.NewsEditor.titleRequired
            successMessage = nil
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = AppStrings.NewsEditor.bodyRequired
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
