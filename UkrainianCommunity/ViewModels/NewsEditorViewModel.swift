import Combine
import Foundation
import UIKit

@MainActor
final class NewsEditorViewModel: ObservableObject {
    @Published var title = ""
    @Published var summary = ""
    @Published var body = ""
    @Published var isPublishing = false
    @Published var isUploadingImage = false
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
            && !isPublishing
    }

    func setSelectedImageData(_ data: Data?) {
        guard let data else {
            selectedImageData = nil
            return
        }

        guard UIImage(data: data) != nil else {
            errorMessage = AppStrings.NewsEditor.imageLoadFailed
            return
        }

        successMessage = nil
        errorMessage = nil
        selectedImageData = data
    }

    func setAuthState(_ authState: AuthState?) {
        self.authState = authState
    }

    func publish() async {
        successMessage = nil
        errorMessage = nil

        guard validate() else {
            return
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
        print("Publishing started")

        do {
            if let selectedImageData {
                isUploadingImage = true
                let downloadURL = try await imageUploadService.uploadNewsCoverImage(data: selectedImageData, newsID: newsID)
                resolvedImageURL = downloadURL.absoluteString
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
            print("Publishing succeeded")
            title = ""
            summary = ""
            body = ""
            selectedImageData = nil
        } catch {
            isUploadingImage = false
            errorMessage = error.localizedDescription
            print("Publishing failed: \(error)")
        }

        isPublishing = false
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
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = AppStrings.NewsEditor.bodyRequired
            successMessage = nil
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        return true
    }
}
