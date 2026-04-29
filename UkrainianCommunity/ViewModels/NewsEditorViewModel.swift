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

    init(repository: NewsRepository) {
        self.repository = repository
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
            errorMessage = "Failed to load the selected image."
            return
        }

        successMessage = nil
        errorMessage = nil
        selectedImageData = data
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
            authorName: "Admin",
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
            successMessage = "News published successfully."
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

    private func validate() -> Bool {
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Title is required."
            successMessage = nil
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        guard !trimmedBody.isEmpty else {
            errorMessage = "Body is required."
            successMessage = nil
            print("Validation failed: \(errorMessage ?? "Unknown validation error.")")
            return false
        }

        return true
    }
}
